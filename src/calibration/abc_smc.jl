using LinearAlgebra: Symmetric, I, Diagonal

################## ABC-SMC Core Algorithm ##################
#
# This file is framework-agnostic: the ABC-SMC loop operates on a generic
# `evaluate_particle` callback. PhysiCell-specific wiring (Monad creation,
# addVariations, run) is handled by the caller in abc.jl.
#

"""
    _ParticleResult

Internal: result of evaluating a single ABC-SMC particle.
"""
struct _ParticleResult
    params::Dict{String,Float64}
    distance::Float64
    metadata::Any  # caller-specific payload (e.g., monad_id)
end

"""
    _runABCSMC(method, param_names, priors, evaluate_particle, on_generation;
               start_generations)

Run the ABC-SMC algorithm. This is the framework-agnostic core.

Generation 1 samples fresh from the prior (no warm-start bias). Exact-match reuse of
previously evaluated parameter points is handled by the caller's `evaluate_particle`
(e.g. PCMM's `Monad(...; use_previous=true)`) — this keeps the gen-1 population an
unbiased prior sample while still avoiding redundant simulation work.

# Arguments
- `method::ABCSMC`: Algorithm settings.
- `param_names::Vector{String}`: Parameter names (column order in results).
- `priors::Vector{<:Distribution}`: Prior distributions, one per parameter.
- `evaluate_particle::Function`: `(params::Dict{String,Float64}) → (distance::Float64, metadata::Any)`.
  Called for each proposed particle. `metadata` is opaque to the algorithm (e.g., monad ID).
- `on_generation::Function`: `(gen::GenerationResult) → nothing`.
  Called after each completed generation (for persistence / logging).
- `start_generations::Vector{GenerationResult}`: Previously-completed generations to
  resume from (empty for a fresh run). Used by `resumeABC`.

# Returns
`Vector{GenerationResult}`: All completed generations (including resumed ones).
"""
function _runABCSMC(method::ABCSMC, param_names::Vector{String},
                    priors::Vector{<:Distribution}, evaluate_particle::Function,
                    on_generation::Function;
                    start_generations::Vector{GenerationResult}=GenerationResult[])

    generations = copy(start_generations)
    t_start = length(generations) + 1

    for t in t_start:method.max_nr_populations
        if t == 1
            gen = _runFirstGeneration(method, param_names, priors, evaluate_particle)
        else
            prev = generations[end]
            epsilon_t = _adaptEpsilon(prev.distances, method.epsilon_quantile, method.minimum_epsilon)
            if epsilon_t <= method.minimum_epsilon && length(generations) > 0
                @info "ABC-SMC: epsilon ($epsilon_t) reached minimum_epsilon ($(method.minimum_epsilon)) — stopping."
                break
            end
            gen = _runSubsequentGeneration(method, param_names, priors, evaluate_particle, prev, epsilon_t, t)
        end

        push!(generations, gen)
        on_generation(gen)

        @info "ABC-SMC generation $t: ε=$(round(gen.epsilon; digits=6)), " *
              "accepted=$(length(gen.distances))/$(gen.n_evaluations) " *
              "($(round(100 * length(gen.distances) / gen.n_evaluations; digits=1))%)"

        if gen.epsilon <= method.minimum_epsilon
            @info "ABC-SMC: epsilon reached minimum_epsilon — stopping."
            break
        end
    end

    return generations
end

################## Generation Runners ##################

"""
    _runFirstGeneration(method, param_names, priors, evaluate_particle)

Run generation 1: sample `population_size` particles from the prior, evaluate, accept all.

Unlike later generations, there is no epsilon threshold — all proposals are kept, giving
an unbiased prior sample. Exact-match reuse of prior simulations is handled transparently
by the caller's `evaluate_particle` (e.g. `Monad(...; use_previous=true)`).
"""
function _runFirstGeneration(method::ABCSMC, param_names::Vector{String},
                             priors::Vector{<:Distribution}, evaluate_particle::Function)
    accepted = _ParticleResult[]
    n_evaluations = 0

    while length(accepted) < method.population_size
        params = _sampleFromPrior(param_names, priors)
        distance, metadata = evaluate_particle(params)
        n_evaluations += 1
        push!(accepted, _ParticleResult(params, distance, metadata))
    end

    # Uniform weights for generation 1
    N = length(accepted)
    weights = fill(1.0 / N, N)

    return _buildGenerationResult(1, accepted, weights, n_evaluations, param_names)
end

"""
    _runSubsequentGeneration(method, param_names, priors, evaluate_particle, prev, epsilon, t)

Run generation t > 1: resample from previous generation, perturb, accept if distance <= epsilon.
"""
function _runSubsequentGeneration(method::ABCSMC, param_names::Vector{String},
                                  priors::Vector{<:Distribution}, evaluate_particle::Function,
                                  prev::GenerationResult, epsilon::Float64, t::Int)
    kernel = _buildPerturbationKernel(prev.particles, prev.weights, param_names)
    accepted = _ParticleResult[]
    n_evaluations = 0

    while length(accepted) < method.population_size
        # Resample a particle from previous generation
        j = _weightedSample(prev.weights)
        prev_params = Dict(name => prev.particles[j, name] for name in param_names)

        # Perturb
        params = _perturbParticle(prev_params, kernel, param_names, priors)
        isnothing(params) && continue  # outside prior support — skip

        # Evaluate
        distance, metadata = evaluate_particle(params)
        n_evaluations += 1

        # Accept/reject
        if distance <= epsilon
            push!(accepted, _ParticleResult(params, distance, metadata))
        end
    end

    # Compute importance weights
    weights = _computeWeights(accepted, param_names, priors, prev, kernel)

    return _buildGenerationResult(t, accepted, weights, n_evaluations, param_names)
end

################## Sampling and Perturbation ##################

"""
    _sampleFromPrior(param_names, priors) → Dict{String,Float64}

Draw one sample from the joint prior (independent marginals).
"""
function _sampleFromPrior(param_names::Vector{String}, priors::Vector{<:Distribution})
    return Dict(param_names[i] => rand(priors[i]) for i in eachindex(param_names))
end

"""
    _buildPerturbationKernel(particles, weights, param_names) → MvNormal

Build a multivariate normal perturbation kernel from the weighted previous generation.
Uses twice the weighted covariance (Beaumont et al. 2009).
"""
function _buildPerturbationKernel(particles::DataFrame, weights::Vector{Float64},
                                   param_names::Vector{String})
    d = length(param_names)
    X = Matrix{Float64}(particles[!, param_names])  # N × d
    N = size(X, 1)

    # Weighted mean
    mu = vec(sum(weights .* X, dims=1))

    # Weighted covariance (2× rule of thumb from Beaumont et al. 2009)
    X_centered = X .- mu'
    Sigma = 2.0 * (X_centered' * Diagonal(weights) * X_centered)

    # Regularize for numerical stability
    Sigma = Symmetric(Sigma) + 1e-10 * I

    return MvNormal(zeros(d), Sigma)
end

"""
    _perturbParticle(prev_params, kernel, param_names, priors) → Dict or nothing

Perturb a particle using the kernel. Returns `nothing` if the perturbed particle
falls outside the prior support (rejection step).
"""
function _perturbParticle(prev_params::Dict{String,Float64}, kernel::MvNormal,
                           param_names::Vector{String}, priors::Vector{<:Distribution})
    perturbation = rand(kernel)
    params = Dict{String,Float64}()
    for (i, name) in enumerate(param_names)
        val = prev_params[name] + perturbation[i]
        # Check prior support
        if !insupport(priors[i], val)
            return nothing
        end
        params[name] = val
    end
    return params
end

"""
    _weightedSample(weights) → Int

Draw one index from a categorical distribution defined by weights.
"""
function _weightedSample(weights::Vector{Float64})
    u = rand()
    cumsum = 0.0
    for (i, w) in enumerate(weights)
        cumsum += w
        if u <= cumsum
            return i
        end
    end
    return length(weights)  # numerical safety
end

################## Weight Computation ##################

"""
    _computeWeights(accepted, param_names, priors, prev, kernel) → Vector{Float64}

Compute and normalize importance weights for generation t > 1.

    w_i = π(θ_i) / Σ_j [ w_j^{t-1} · K(θ_i | θ_j^{t-1}) ]

where π is the prior density and K is the perturbation kernel density.
"""
function _computeWeights(accepted::Vector{_ParticleResult}, param_names::Vector{String},
                          priors::Vector{<:Distribution}, prev::GenerationResult,
                          kernel::MvNormal)
    N_prev = nrow(prev.particles)
    weights = Vector{Float64}(undef, length(accepted))

    for (i, particle) in enumerate(accepted)
        # Prior density (product of independent marginals)
        prior_density = prod(pdf(priors[k], particle.params[param_names[k]]) for k in eachindex(param_names))

        # Denominator: weighted sum of kernel densities from previous particles
        denom = 0.0
        theta_vec = [particle.params[name] for name in param_names]
        for j in 1:N_prev
            prev_vec = [prev.particles[j, name] for name in param_names]
            denom += prev.weights[j] * pdf(kernel, theta_vec .- prev_vec)
        end

        weights[i] = denom > 0 ? prior_density / denom : 0.0
    end

    # Normalize
    total = sum(weights)
    if total > 0
        weights ./= total
    else
        weights .= 1.0 / length(weights)
    end

    return weights
end

################## Epsilon Adaptation ##################

"""
    _adaptEpsilon(distances, quantile_val, minimum_epsilon) → Float64

Compute the next generation's epsilon as a quantile of the current distances,
clamped to `minimum_epsilon`.
"""
function _adaptEpsilon(distances::Vector{Float64}, quantile_val::Float64, minimum_epsilon::Float64)
    return max(minimum_epsilon, quantile(distances, quantile_val))
end

################## Result Construction ##################

"""
    _buildGenerationResult(t, accepted, weights, n_evaluations, param_names) → GenerationResult

Assemble a `GenerationResult` from accepted particles.
"""
function _buildGenerationResult(t::Int, accepted::Vector{_ParticleResult},
                                 weights::Vector{Float64}, n_evaluations::Int,
                                 param_names::Vector{String})
    N = length(accepted)
    particles = DataFrame(Dict(name => [p.params[name] for p in accepted] for name in param_names))
    distances = [p.distance for p in accepted]
    monad_ids = [p.metadata isa Integer ? Int(p.metadata) : 0 for p in accepted]
    epsilon = maximum(distances)

    return GenerationResult(t, particles, weights, distances, epsilon, n_evaluations, monad_ids)
end

################## Generation Persistence ##################

"""
    _saveGeneration(calibration::Calibration, gen::GenerationResult)

Save a generation result to CSV in the calibration output folder.
File: `data/outputs/calibrations/{id}/generations/generation_{t}.csv`
"""
function _saveGeneration(calibration::Calibration, gen::GenerationResult)
    dir = joinpath(calibrationFolder(calibration), "generations")
    mkpath(dir)
    path = joinpath(dir, "generation_$(gen.t).csv")

    df = copy(gen.particles)
    df[!, :weight] = gen.weights
    df[!, :distance] = gen.distances
    df[!, :monad_id] = gen.monad_ids

    CSV.write(path, df)
end

"""
    _saveMethod(calibration::Calibration, method::ABCSMC)

Save the ABCSMC settings to a file in the calibration output folder for resume support.
"""
function _saveMethod(calibration::Calibration, method::ABCSMC)
    path = joinpath(calibrationFolder(calibration), "method.toml")
    open(path, "w") do io
        println(io, "[ABCSMC]")
        println(io, "population_size = $(method.population_size)")
        println(io, "max_nr_populations = $(method.max_nr_populations)")
        println(io, "minimum_epsilon = $(method.minimum_epsilon)")
        println(io, "epsilon_quantile = $(method.epsilon_quantile)")
        println(io, "perturbation_kernel = \"$(method.perturbation_kernel)\"")
    end
end

"""
    _loadGenerations(calibration::Calibration, param_names::Vector{String}) → Vector{GenerationResult}

Load saved generation results from the calibration output folder.
"""
function _loadGenerations(calibration::Calibration, param_names::Vector{String})
    dir = joinpath(calibrationFolder(calibration), "generations")
    !isdir(dir) && return GenerationResult[]

    generations = GenerationResult[]
    t = 1
    while true
        path = joinpath(dir, "generation_$(t).csv")
        !isfile(path) && break

        df = CSV.read(path, DataFrame)
        weights = df[!, :weight]
        distances = df[!, :distance]
        monad_ids = df[!, :monad_id]
        particles = select(df, param_names)
        epsilon = maximum(distances)
        n_evaluations = nrow(df)  # lower bound — actual count not persisted

        push!(generations, GenerationResult(t, particles, weights, distances, epsilon, n_evaluations, monad_ids))
        t += 1
    end

    return generations
end
