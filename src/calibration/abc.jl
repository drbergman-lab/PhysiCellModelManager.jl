export runABC, resumeABC

################## PhysiCell-specific adapter ##################
#
# This file contains the PhysiCell-specific wiring: how a proposed parameter vector
# becomes a Monad, and how that Monad is executed to produce a distance. The core
# ABC-SMC algorithm in abc_smc.jl is framework-agnostic.
#
# When this code is generalized to ModelManager.jl, the algorithm core moves to the
# base package and this file provides the PhysiCell adapter.
#

"""
    _createMonadForParams(problem, params) → Monad

Create a Monad at the given parameter values. Uses `use_previous=true` so that
exact-match reuse of existing simulations happens transparently.
"""
function _createMonadForParams(problem::CalibrationProblem, params::Dict{String,Float64})
    avs = AbstractVariation[
        DiscreteVariation(p.xml_path, [params[p.name]]) for p in problem.parameters
    ]
    add_result = addVariations(GridVariation(), problem.inputs, avs, problem.reference_variation_id)
    variation_id = add_result.variation_ids[1]
    return Monad(problem.inputs, variation_id; n_replicates=problem.n_replicates, use_previous=true)
end

"""
    _buildEvaluateParticle(problem, monads_csv) → Function

Build the `evaluate_particle` callback expected by `_runABCSMC`. The returned function
creates a Monad, runs it quietly (no per-sim console output), records the monad ID,
and computes the distance via `problem.summary_statistic` and `problem.distance`.
"""
function _buildEvaluateParticle(problem::CalibrationProblem, monads_csv::String)
    function evaluate_particle(params::Dict{String,Float64})
        monad = _createMonadForParams(problem, params)
        run(monad; quiet=true)

        open(monads_csv, "a") do io
            println(io, monad.id)
        end

        simulated = problem.summary_statistic(monad.id)
        simulated_dict = Dict{String,Any}(String(k) => v for (k, v) in simulated)
        distance = problem.distance(simulated_dict, problem.observed_data)

        return Float64(distance), monad.id
    end
    return evaluate_particle
end

################## Public API ##################

"""
    runCalibration(problem::CalibrationProblem, method::ABCSMC; description="") → ABCResult

Run ABC-SMC calibration. See [`ABCSMC`](@ref) for method settings.

Each particle evaluation:
1. Creates a `Monad` at the proposed parameter values.
2. Runs the Monad's simulations (reusing any pre-existing matching simulations via `use_previous=true`).
3. Computes `problem.summary_statistic(monad_id)` and compares to `problem.observed_data` via `problem.distance`.

The calibration is tracked in the PCMM database (`calibrations` table) and all monads
created during the run appear in `data/outputs/monads/` as normal. Per-generation
results are saved to `data/outputs/calibrations/{id}/generations/generation_{t}.csv`
and the method settings to `data/outputs/calibrations/{id}/method.toml` for
[`resumeABC`](@ref) support.

# Examples
```julia
method = ABCSMC(population_size=200, max_nr_populations=5)
result = runCalibration(problem, method)
df, weights = posterior(result)
```
"""
function runCalibration(problem::CalibrationProblem, method::ABCSMC; description::String="")
    calibration = createCalibration("ABC-SMC"; description=description)
    monads_csv = calibrationMonadsCSV(calibration)
    _saveMethod(calibration, method)

    param_names = [p.name for p in problem.parameters]
    priors = [p.prior for p in problem.parameters]
    evaluate_particle = _buildEvaluateParticle(problem, monads_csv)
    on_generation = gen -> _saveGeneration(calibration, gen)

    generations = _runABCSMC(method, param_names, priors, evaluate_particle, on_generation)

    return ABCResult(calibration, generations, problem.parameters, method)
end

"""
    runABC(problem::CalibrationProblem; kwargs...) → ABCResult

Run ABC-SMC parameter calibration. Convenience wrapper that constructs an [`ABCSMC`](@ref)
method from the keyword arguments and delegates to [`runCalibration`](@ref).

# Keyword Arguments
- `population_size::Int=100`: Number of accepted particles per generation.
- `max_nr_populations::Int=10`: Maximum number of SMC generations.
- `minimum_epsilon::Float64=0.01`: Stop when acceptance threshold drops below this.
- `epsilon_quantile::Float64=0.5`: Quantile of distances for adaptive epsilon.
- `perturbation_kernel::Symbol=:gaussian`: Kernel for perturbing resampled particles.
- `description::String=""`: Optional description stored in the `calibrations` DB row.

# Examples
```julia
result = runABC(problem; population_size=200, max_nr_populations=5)
df, weights = posterior(result)
println("Posterior mean: ", sum(df.death_rate .* weights))
```
"""
function runABC(problem::CalibrationProblem;
                population_size::Int=100, max_nr_populations::Int=10,
                minimum_epsilon::Float64=0.01, epsilon_quantile::Float64=0.5,
                perturbation_kernel::Symbol=:gaussian, description::String="")
    method = ABCSMC(; population_size=population_size,
                      max_nr_populations=max_nr_populations,
                      minimum_epsilon=minimum_epsilon,
                      epsilon_quantile=epsilon_quantile,
                      perturbation_kernel=perturbation_kernel)
    return runCalibration(problem, method; description=description)
end

################## Resume ##################

"""
    resumeABC(calibration::Calibration, problem::CalibrationProblem;
              method::Union{Nothing,ABCSMC}=nothing) → ABCResult

Resume a stopped or crashed ABC-SMC calibration from saved generation files.

Loads previously-completed generations from `data/outputs/calibrations/{id}/generations/`
and continues the SMC loop from the next generation. If `method` is not supplied, it is
loaded from the saved `method.toml` in the calibration folder.

The `problem` argument must match the one used for the original run — there is no way to
verify this automatically, so the caller is responsible for consistency.

# Examples
```julia
# Original run interrupted at generation 3 of 10
calibration = Calibration(42)
result = resumeABC(calibration, problem)
```
"""
function resumeABC(calibration::Calibration, problem::CalibrationProblem;
                   method::Union{Nothing,ABCSMC}=nothing)
    m = isnothing(method) ? _loadMethod(calibration) : method
    param_names = [p.name for p in problem.parameters]
    priors = [p.prior for p in problem.parameters]

    start_generations = _loadGenerations(calibration, param_names)

    monads_csv = calibrationMonadsCSV(calibration)
    evaluate_particle = _buildEvaluateParticle(problem, monads_csv)
    on_generation = gen -> _saveGeneration(calibration, gen)

    generations = _runABCSMC(m, param_names, priors, evaluate_particle, on_generation;
                              start_generations=start_generations)

    return ABCResult(calibration, generations, problem.parameters, m)
end

"""
    _loadMethod(calibration::Calibration) → ABCSMC

Load the saved ABCSMC settings from `method.toml` in the calibration output folder.
"""
function _loadMethod(calibration::Calibration)
    path = joinpath(calibrationFolder(calibration), "method.toml")
    isfile(path) || error("Cannot resume: $path not found. Pass `method=ABCSMC(...)` explicitly.")
    settings = Dict{String,Any}()
    open(path, "r") do io
        for line in eachline(io)
            line = strip(line)
            (isempty(line) || startswith(line, "#") || startswith(line, "[")) && continue
            parts = split(line, "=")
            length(parts) == 2 || continue
            key = strip(parts[1])
            value = strip(parts[2])
            settings[key] = value
        end
    end
    return ABCSMC(
        population_size=parse(Int, settings["population_size"]),
        max_nr_populations=parse(Int, settings["max_nr_populations"]),
        minimum_epsilon=parse(Float64, settings["minimum_epsilon"]),
        epsilon_quantile=parse(Float64, settings["epsilon_quantile"]),
        perturbation_kernel=Symbol(strip(settings["perturbation_kernel"], '"'))
    )
end
