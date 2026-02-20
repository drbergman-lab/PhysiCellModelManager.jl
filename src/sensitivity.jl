using Distributions, DataFrames, CSV, Sobol, FFTW
import GlobalSensitivity #! do not bring in their definition of Sobol as it conflicts with the Sobol module

export MOAT, Sobolʼ, SobolPCMM, RBD

"""
    GSAMethod

Abstract type for global sensitivity analysis methods.

# Subtypes
- [`MOAT`](@ref)
- [`Sobolʼ`](@ref)
- [`RBD`](@ref)

# Methods
[`run`](@ref)
"""
abstract type GSAMethod end

"""
    GSASampling

Store the information that comes out of a global sensitivity analysis method.

# Subtypes
- [`MOATSampling`](@ref)
- [`SobolSampling`](@ref)
- [`RBDSampling`](@ref)

# Methods
[`calculateGSA!`](@ref), [`evaluateFunctionOnSampling`](@ref),
[`getMonadIDDataFrame`](@ref), [`simulationIDs`](@ref), [`methodString`](@ref),
[`sensitivityResults!`](@ref), [`recordSensitivityScheme`](@ref)
"""
abstract type GSASampling end

"""
    getMonadIDDataFrame(gsa_sampling::GSASampling)

Get the DataFrame of monad IDs that define the scheme of the sensitivity analysis.
"""
getMonadIDDataFrame(gsa_sampling::GSASampling) = gsa_sampling.monad_ids_df

"""
    simulationIDs(gsa_sampling::GSASampling)

Get the simulation IDs that were run in the sensitivity analysis.
"""
simulationIDs(gsa_sampling::GSASampling) = simulationIDs(gsa_sampling.sampling)

"""
    methodString(gsa_sampling::GSASampling)

Get the string representation of the method used in the sensitivity analysis.
"""
function methodString(gsa_sampling::GSASampling)
    method = typeof(gsa_sampling) |> string |> lowercase
    method = split(method, ".")[end] #! remove module name that comes with the type, e.g. Main.PhysiCellModelManager.MOATSampling -> MOATSampling
    return endswith(method, "sampling") ? method[1:end-8] : method
end

"""
    run(method::GSAMethod, args...; functions::AbstractVector{<:Function}=Function[], kwargs...)

Run a global sensitivity analysis method on the given arguments.

# Arguments
- `method::GSAMethod`: the method to run. Options are [`MOAT`](@ref), [`Sobolʼ`](@ref), and [`RBD`](@ref).
- `inputs::InputFolders`: the input folders shared across all simuations to run.
- `avs::AbstractVector{<:AbstractVariation}`: the elementary variations to sample. These can be either [`DiscreteVariation`](@ref)'s or [`DistributedVariation`](@ref)'s.

Alternatively, the third argument, `inputs`, can be replaced with a `reference::AbstractMonad`, i.e., a simulation or monad to be the reference.
This should be preferred to setting reference variation IDs manually, i.e., if not using the base files in the input folders.

# Keyword Arguments
The `reference_variation_id` keyword argument is only compatible when the third argument is of type `InputFolders`.
Otherwise, the `reference` simulation/monad will set the reference variation values.
- `reference_variation_id::VariationID`: the reference variation IDs as a `VariationID`
- `ignore_indices::AbstractVector{<:Integer}=[]`: indices into `avs` to ignore when perturbing the parameters. Only used for Sobolʼ. See [`Sobolʼ`](@ref) for a use case.
- `force_recompile::Bool=false`: whether to force recompilation of the simulation code
- `prune_options::PruneOptions=PruneOptions()`: the options for pruning the simulation results
- `n_replicates::Integer=1`: the number of replicates to run for each monad, i.e., at each sampled parameter vector.
- `use_previous::Bool=true`: whether to use previous simulation results if they exist
- `functions::AbstractVector{<:Function}=Function[]`: the functions to calculate the sensitivity indices for. Each function must take a simulation ID as the singular input and return a real number.
"""
function run(method::GSAMethod, inputs::InputFolders, avs::AbstractVector{<:AbstractVariation}; functions::AbstractVector{<:Function}=Function[], kwargs...)
    pv = ParsedVariations(avs)
    gsa_sampling = runSensitivitySampling(method, inputs, pv; kwargs...)
    sensitivityResults!(gsa_sampling, functions)
    return gsa_sampling
end

function run(method::GSAMethod, reference::AbstractMonad, avs::Vector{<:AbstractVariation}; functions::AbstractVector{<:Function}=Function[], kwargs...)
    return run(method, reference.inputs, avs; reference_variation_id=reference.variation_id, functions, kwargs...)
end

function run(method::GSAMethod, inputs_or_ref::Union{InputFolders, AbstractMonad}, av1::AbstractVariation, avs::Vararg{AbstractVariation}; kwargs...)
    return run(method, inputs_or_ref, [av1; avs...]; kwargs...)
end

"""
    sensitivityResults!(gsa_sampling::GSASampling, functions::AbstractVector{<:Function})

Calculate the global sensitivity analysis for the given functions and record the sampling scheme.
"""
function sensitivityResults!(gsa_sampling::GSASampling, functions::AbstractVector{<:Function})
    calculateGSA!(gsa_sampling, functions)
    recordSensitivityScheme(gsa_sampling)
end

"""
    calculateGSA!(gsa_sampling::GSASampling, functions::AbstractVector{<:Function})

Calculate the sensitivity indices for the given functions.

This function is also used to compute the sensitivity indices for a single function:
```julia
calculateGSA!(gsa_sampling, f)
```

# Arguments
- `gsa_sampling::GSASampling`: the sensitivity analysis to calculate the indices for.
- `functions::AbstractVector{<:Function}`: the functions to calculate the sensitivity indices for. Each function must take a simulation ID as the singular input and return a real number.
"""
function calculateGSA!(gsa_sampling::GSASampling, functions::AbstractVector{<:Function})
    for f in functions
        calculateGSA!(gsa_sampling, f)
    end
    return
end

############# Morris One-At-A-Time (MOAT) #############

"""
    MOAT

Store the information necessary to run a Morris One-At-A-Time (MOAT) global sensitivity analysis.

# Fields
- `lhs_variation::LHSVariation`: the Latin Hypercube Sampling (LHS) variation to use for the MOAT. See [`LHSVariation`](@ref).

# Examples
Note: any keyword arguments in the `MOAT` constructor are passed to [`LHSVariation`](@ref).
```
MOAT() # default to 15 base points
MOAT(10) # 10 base points
MOAT(10; add_noise=true) # do not restrict the base points to the center of their cells
```
"""
struct MOAT <: GSAMethod
    lhs_variation::LHSVariation
end

MOAT() = MOAT(LHSVariation(15)) #! default to 15 points
MOAT(n::Int; kwargs...) = MOAT(LHSVariation(n; kwargs...))

"""
    MOATSampling

Store the information that comes out of a Morris One-At-A-Time (MOAT) global sensitivity analysis.

# Fields
- `sampling::Sampling`: the sampling used in the sensitivity analysis.
- `monad_ids_df::DataFrame`: the DataFrame of monad IDs that define the scheme of the sensitivity analysis.
- `results::Dict{Function, GlobalSensitivity.MorrisResult}`: the results of the sensitivity analysis for each function.
"""
struct MOATSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, GlobalSensitivity.MorrisResult}
end

MOATSampling(sampling::Sampling, monad_ids_df::DataFrame) = MOATSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.MorrisResult}())

function Base.show(io::IO, moat_sampling::MOATSampling)
    println(io, "MOAT sampling")
    println(io, "-------------")
    println(io, moat_sampling.sampling)
    println(io, "Sensitivity functions calculated:")
    for f in keys(moat_sampling.results)
        println(io, "  $f")
    end
end

"""
    runSensitivitySampling(method::GSAMethod, args...; kwargs...)

Run a global sensitivity analysis method on the given arguments.

# Arguments
- `method::GSAMethod`: the method to run. Options are [`MOAT`](@ref), [`Sobolʼ`](@ref), and [`RBD`](@ref).
- `inputs::InputFolders`: the input folders shared across all simuations to run.
- `pv::ParsedVariations`: the [`ParsedVariations`](@ref) object that contains the variations to sample.

# Keyword Arguments
- `reference_variation_id::VariationID`: the reference variation IDs as a `VariationID`
- `ignore_indices::AbstractVector{<:Integer}=[]`: indices into dimensions of `pv.latent_variations` to ignore when perturbing the parameters. Only used for [Sobolʼ](@ref). These count the latent parameters, i.e. possibly >1 per latent variation!
- `force_recompile::Bool=false`: whether to force recompilation of the simulation code
- `prune_options::PruneOptions=PruneOptions()`: the options for pruning the simulation results
- `n_replicates::Int=1`: the number of replicates to run for each monad, i.e., at each sampled parameter vector.
- `use_previous::Bool=true`: whether to use previous simulation results if they exist
"""
function runSensitivitySampling end

function runSensitivitySampling(method::MOAT, inputs::InputFolders, pv::ParsedVariations; reference_variation_id::VariationID=VariationID(inputs),
    ignore_indices::AbstractVector{<:Integer}=Int[], force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), n_replicates::Int=1, use_previous::Bool=true)

    if !isempty(ignore_indices)
        error("MOAT does not support ignoring indices...yet? Only Sobolʼ does for now.")
    end
    add_variations_result = addVariations(method.lhs_variation, inputs, pv, reference_variation_id)
    base_variation_ids = add_variations_result.variation_ids
    
    perturbed_variation_ids = stack(zip(base_variation_ids, eachcol(add_variations_result.cdfs)); dims=1) do (variation_id, cdf_col)
        perturbVariation(pv, inputs, variation_id, cdf_col) #! each base point produces a row of perturbations (one per latent dimension perturbed)
    end

    variation_ids = hcat(base_variation_ids, perturbed_variation_ids)
    monads = variationsToMonads(inputs, variation_ids)
    monad_ids = [monad.id for monad in monads]
    perturb_headers = mapreduce(lv -> lv.latent_parameter_names, vcat, pv.latent_variations)
    header_line = ["base"; perturb_headers]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(unique(monads); n_replicates=n_replicates, use_previous=use_previous)
    run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return MOATSampling(sampling, monad_ids_df)
end

"""
    perturbVariation(pv::ParsedVariations, inputs::InputFolders, reference_variation_id::VariationID, cdf_col::AbstractVector{<:Real})

Perturb the variation at the given location and dimension for [`MOAT`](@ref) global sensitivity analysis.
"""
function perturbVariation(pv::ParsedVariations, inputs::InputFolders, reference_variation_id::VariationID, cdf_col::AbstractVector{<:Real})
    perturbed_cdfs = repeat(cdf_col, 1, length(cdf_col))
    for (d, col) in enumerate(eachcol(perturbed_cdfs))
        dcdf = cdf_col[d] < 0.5 ? 0.5 : -0.5
        col[d] += dcdf
    end
    
    perturbed_variation_ids = addCDFVariations(inputs, pv, reference_variation_id, perturbed_cdfs)
    @assert length(perturbed_variation_ids) == length(cdf_col) "Expected one perturbation per latent dimension, but got $(length(perturbed_variation_ids)) perturbations for $(length(cdf_col)) latent dimensions."
    return perturbed_variation_ids
end

"""
    variationValue(ev::ElementaryVariation, variation_id::Int, folder::String)

Get the value of the variation at the given variation ID for [`MOAT`](@ref) global sensitivity analysis.
"""
function variationValue(ev::ElementaryVariation, variation_id::Int, folder::String)
    location = variationLocation(ev)
    query = constructSelectQuery(locationVariationsTableName(location), "WHERE $(locationVariationIDName(location))=$variation_id"; selection="\"$(columnName(ev))\"")
    variation_value_df = queryToDataFrame(query; db=locationVariationsDatabase(location, folder), is_row=true)
    return variation_value_df[1,1]

end

function calculateGSA!(moat_sampling::MOATSampling, f::Function)
    if f in keys(moat_sampling.results)
        return
    end
    vals = evaluateFunctionOnSampling(moat_sampling, f)
    effects = 2 * (vals[:,2:end] .- vals[:,1]) #! all diffs in the design matrix are 0.5
    means = mean(effects, dims=1)
    means_star = mean(abs.(effects), dims=1)
    variances = var(effects, dims=1)
    moat_sampling.results[f] = GlobalSensitivity.MorrisResult(means, means_star, variances, effects)
    return
end

############# Sobolʼ sequences and sobol indices #############

"""
    Sobolʼ

Store the information necessary to run a Sobol' global sensitivity analysis as well as how to extract the first and total order indices.

The rasp symbol is used to avoid conflict with the Sobol module. To type it in VS Code, use `\\rasp` and then press `tab`.
Alternatively, the constructor [`SobolPCMM`](@ref) is provided as an alias for convenience.

The methods available for the first order indices are `:Sobol1993`, `:Jansen1999`, and `:Saltelli2010`. Default is `:Jansen1999`.
The methods available for the total order indices are `:Homma1996`, `:Jansen1999`, and `:Sobol2007`. Default is `:Jansen1999`.

# Fields
- `sobol_variation::SobolVariation`: the Sobol' variation to use for the Sobol' analysis. See [`SobolVariation`](@ref).
- `sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}`: the methods to use for calculating the first and total order indices.

# Examples
Note: any keyword arguments in the `Sobolʼ` constructor are passed to [`SobolVariation`](@ref), except for the `sobol_index_methods` keyword argument.
Do not use the `n_matrices` keyword argument in the `SobolVariation` constructor as it is set to 2 as required for Sobol' analysis.
```
Sobolʼ(15) # 15 points from the Sobol' sequence
Sobolʼ(15; sobol_index_methods=(first_order=:Jansen1999, total_order=:Jansen1999)) # use Jansen, 1999 for both first and total order indices
Sobolʼ(15; randomization=NoRand())` # use the default Sobol' sequence with no randomization. See GlobalSensitivity.jl for more options.
Sobolʼ(15; skip_start=true) # force the Sobol' sequence to skip to the lowest denominator in the sequence that can hold 15 points, i.e., choose from [1/32, 3/32, 5/32, ..., 31/32]
Sobolʼ(15; skip_start=false) # force the Sobol' sequence to start at the beginning, i.e. [0, 0.5, 0.25, 0.75, ...]
Sobolʼ(15; include_one=true) # force the Sobol' sequence to include 1 in the sequence
```
"""
struct Sobolʼ <: GSAMethod #! the prime symbol is used to avoid conflict with the Sobol module
    sobol_variation::SobolVariation
    sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}
end

Sobolʼ(n::Int; sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}=(first_order=:Jansen1999, total_order=:Jansen1999), kwargs...) =
    Sobolʼ(SobolVariation(n; n_matrices=2, kwargs...), sobol_index_methods)

"""
    SobolPCMM

Alias for [`Sobolʼ`](@ref) for convenience.
"""
SobolPCMM = Sobolʼ #! alias for convenience

"""
    SobolSampling

Store the information that comes out of a Sobol' global sensitivity analysis.

# Fields
- `sampling::Sampling`: the sampling used in the sensitivity analysis.
- `monad_ids_df::DataFrame`: the DataFrame of monad IDs that define the scheme of the sensitivity analysis.
- `results::Dict{Function, GlobalSensitivity.SobolResult}`: the results of the sensitivity analysis for each function.
- `sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}`: the methods used for calculating the first and total order indices.
"""
struct SobolSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, GlobalSensitivity.SobolResult}
    sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}
end

SobolSampling(sampling::Sampling, monad_ids_df::DataFrame; sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}=(first_order=:Jansen1999, total_order=:Jansen1999)) = SobolSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.SobolResult}(), sobol_index_methods)

function Base.show(io::IO, sobol_sampling::SobolSampling)
    println(io, "Sobol sampling")
    println(io, "--------------")
    println(io, sobol_sampling.sampling)
    println(io, "Sobol index methods:")
    println(io, "  First order: $(sobol_sampling.sobol_index_methods.first_order)")
    println(io, "  Total order: $(sobol_sampling.sobol_index_methods.total_order)")
    println(io, "Sensitivity functions calculated:")
    for f in keys(sobol_sampling.results)
        println(io, "  $f")
    end
end

function runSensitivitySampling(method::Sobolʼ, inputs::InputFolders, pv::ParsedVariations; reference_variation_id::VariationID=VariationID(inputs),
    ignore_indices::AbstractVector{<:Integer}=Int[], force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), n_replicates::Int=1, use_previous::Bool=true)

    add_variations_result = addVariations(method.sobol_variation, inputs, pv, reference_variation_id)
    variation_ids = add_variations_result.variation_ids
    cdfs = add_variations_result.cdfs
    d = nLatentDims(pv)
    focus_indices = [i for i in 1:d if !(i in ignore_indices)]

    A = cdfs[:,1,:] #! cdfs is of size (d, 2, n), i.e., d = # parameters, 2 design matrices, and n = # samples
    B = cdfs[:,2,:]
    Aᵦ = [i => copy(A) for i in focus_indices] |> Dict
    variation_ids_Aᵦ = stack(focus_indices) do i
        Aᵦ[i][i,:] .= B[i,:]
        addCDFVariations(inputs, pv, reference_variation_id, Aᵦ[i])
    end
    monads = variationsToMonads(inputs, hcat(variation_ids, variation_ids_Aᵦ))
    monad_ids = [monad.id for monad in monads]
    perturb_headers = mapreduce(lv -> lv.latent_parameter_names, vcat, pv.latent_variations[focus_indices])
    header_line = ["A"; "B"; perturb_headers]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(unique(monads); n_replicates=n_replicates, use_previous=use_previous)
    run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return SobolSampling(sampling, monad_ids_df; sobol_index_methods=method.sobol_index_methods)
end

function calculateGSA!(sobol_sampling::SobolSampling, f::Function)
    if f in keys(sobol_sampling.results)
        return
    end
    vals = evaluateFunctionOnSampling(sobol_sampling, f)
    d = size(vals, 2) - 2
    A_values = @view vals[:, 1]
    B_values = @view vals[:, 2]
    Aᵦ_values = [vals[:, 2+i] for i in 1:d]
    expected_value² = mean(A_values .* B_values) #! see Saltelli, 2002 Eq 21
    total_variance = var([A_values; B_values])
    first_order_variances = zeros(Float64, d)
    total_order_variances = zeros(Float64, d)
    si_method = sobol_sampling.sobol_index_methods.first_order
    st_method = sobol_sampling.sobol_index_methods.total_order
    for (i, Aᵦ) in enumerate(Aᵦ_values)
        #! I found Jansen, 1999 to do best for first order variances on a simple test of f(x,y) = x.^2 + y.^2 + c with a uniform distribution on [0,1] x [0,1] including with noise added
        if si_method == :Sobol1993
            first_order_variances[i] = mean(B_values .* Aᵦ) .- expected_value² #! Sobol, 1993
        elseif si_method == :Jansen1999
            first_order_variances[i] = total_variance - 0.5 * mean((B_values .- Aᵦ) .^ 2) #! Jansen, 1999
        elseif si_method == :Saltelli2010
            first_order_variances[i] = mean(B_values .* (Aᵦ .- A_values)) #! Saltelli, 2010
        end

        #! I found Jansen, 1999 to do best for total order variances on a simple test of f(x,y) = x.^2 + y.^2 + c with a uniform distribution on [0,1] x [0,1] including with noise added
        if st_method == :Homma1996
            total_order_variances[i] = total_variance - mean(A_values .* Aᵦ) + expected_value² #! Homma, 1996
        elseif st_method == :Jansen1999
            total_order_variances[i] = 0.5 * mean((Aᵦ .- A_values) .^ 2) #! Jansen, 1999
        elseif st_method == :Sobol2007
            total_order_variances[i] = mean(A_values .* (A_values .- Aᵦ)) #! Sobol, 2007
        end
    end

    first_order_indices = first_order_variances ./ total_variance
    total_order_indices = total_order_variances ./ total_variance

    sobol_sampling.results[f] = GlobalSensitivity.SobolResult(first_order_indices, nothing, nothing, nothing, total_order_indices, nothing) #! do not yet support (S1 CIs, second order indices (S2), S2 CIs, or ST CIs)
    return
end

############# Random Balance Design (RBD) #############

"""
    RBD

Store the information necessary to run a Random Balance Design (RBD) global sensitivity analysis.

By default, `RBD` will use the Sobol' sequence to sample the parameter space.
See below for how to turn this off.
Currently, users cannot control the Sobolʼ sequence used in RBD to the same degree it can be controlled in Sobolʼ.
Open an [Issue](https://github.com/drbergman-lab/PhysiCellModelManager.jl/issues) if you would like this feature.

# Fields
- `rbd_variation::RBDVariation`: the RBD variation to use for the RBD analysis. See [`RBDVariation`](@ref).
- `num_harmonics::Int`: the number of harmonics to use from the Fourier transform for the RBD analysis.

# Examples
Note: any keyword arguments in the `RBD` constructor are passed to [`RBDVariation`](@ref), except for the `num_harmonics` keyword argument.
If `num_harmonics` is not specified, it defaults to 6.
```
RBD(15) # 15 points from the Sobol' sequence
RBD(15; num_harmonics=10) # use 10 harmonics
RBD(15; use_sobol=false) # opt out of using the Sobol' sequence, instead using a random sequence in each dimension
```
"""
struct RBD <: GSAMethod #! the prime symbol is used to avoid conflict with the Sobol module
    rbd_variation::RBDVariation
    num_harmonics::Int
end

RBD(n::Integer; num_harmonics::Integer=6, kwargs...) = RBD(RBDVariation(n; kwargs...), num_harmonics)

"""
    RBDSampling

Store the information that comes out of a Random Balance Design (RBD) global sensitivity analysis.

# Fields
- `sampling::Sampling`: the sampling used in the sensitivity analysis.
- `monad_ids_df::DataFrame`: the DataFrame of monad IDs that define the scheme of the sensitivity analysis.
- `results::Dict{Function, GlobalSensitivity.SobolResult}`: the results of the sensitivity analysis for each function.
- `num_harmonics::Int`: the number of harmonics used in the Fourier transform.
- `num_cycles::Union{Int, Rational}`: the number of cycles used for each parameter.
"""
struct RBDSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, Vector{<:Real}}
    num_harmonics::Int
    num_cycles::Union{Int, Rational}
end

RBDSampling(sampling::Sampling, monad_ids_df::DataFrame, num_cycles; num_harmonics::Int=6) = RBDSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.SobolResult}(), num_harmonics, num_cycles)

function Base.show(io::IO, rbd_sampling::RBDSampling)
    println(io, "RBD sampling")
    println(io, "------------")
    println(io, rbd_sampling.sampling)
    println(io, "Number of harmonics: $(rbd_sampling.num_harmonics)")
    println(io, "Number of cycles (1/2 or 1): $(rbd_sampling.num_cycles)")
    println(io, "GSA functions:")
    for f in keys(rbd_sampling.results)
        println(io, "  $f")
    end
end

function runSensitivitySampling(method::RBD, inputs::InputFolders, pv::ParsedVariations; reference_variation_id::VariationID=VariationID(inputs),
    ignore_indices::AbstractVector{<:Integer}=Int[], force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), n_replicates::Int=1, use_previous::Bool=true)
    if !isempty(ignore_indices)
        error("RBD does not support ignoring indices...yet? Only Sobolʼ does for now.")
    end
    add_variations_result = addVariations(method.rbd_variation, inputs, pv, reference_variation_id)
    variation_matrix = add_variations_result.variation_matrix
    monads = variationsToMonads(inputs, variation_matrix)
    monad_ids = [monad.id for monad in monads]
    header_line = mapreduce(lv -> lv.latent_parameter_names, vcat, pv.latent_variations)
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(unique(monads); n_replicates=n_replicates, use_previous=use_previous)
    run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return RBDSampling(sampling, monad_ids_df, method.rbd_variation.num_cycles; num_harmonics=method.num_harmonics)
end

function calculateGSA!(rbd_sampling::RBDSampling, f::Function)
    if f in keys(rbd_sampling.results)
        return
    end
    vals = evaluateFunctionOnSampling(rbd_sampling, f)
    if rbd_sampling.num_cycles == 1 // 2
        vals = vcat(vals, vals[end-1:-1:2, :])
    end
    ys = fft(vals, 1) .|> abs2
    ys ./= size(vals, 1)
    V = sum(ys[2:end, :], dims=1)
    Vi = 2 * sum(ys[2:(min(size(ys, 1), rbd_sampling.num_harmonics + 1)), :], dims=1)
    rbd_sampling.results[f] = (Vi ./ V) |> vec
    return
end

############# Generic Helper Functions #############

"""
    recordSensitivityScheme(gsa_sampling::GSASampling)

Record the sampling scheme of the global sensitivity analysis to a CSV file.
"""
function recordSensitivityScheme(gsa_sampling::GSASampling)
    method = methodString(gsa_sampling)
    path_to_csv = joinpath(trialFolder(gsa_sampling.sampling), "$(method)_scheme.csv")
    return CSV.write(path_to_csv, getMonadIDDataFrame(gsa_sampling); header=true)
end

"""
    evaluateFunctionOnSampling(gsa_sampling::GSASampling, f::Function)

Evaluate the given function on the sampling scheme of the global sensitivity analysis, avoiding duplicate evaluations.
"""
function evaluateFunctionOnSampling(gsa_sampling::GSASampling, f::Function)
    monad_id_df = getMonadIDDataFrame(gsa_sampling)
    value_dict = Dict{Int, Float64}()
    vals = zeros(Float64, size(monad_id_df))
    for (ind, monad_id) in enumerate(monad_id_df |> Matrix)
        if !haskey(value_dict, monad_id)
            simulation_ids = constituentIDs(Monad, monad_id)
            sim_values = [f(simulation_id) for simulation_id in simulation_ids]
            value = sim_values |> mean
            value_dict[monad_id] = value
        end
        vals[ind] = value_dict[monad_id]
    end
    return vals
end

"""
    variationsToMonads(inputs::InputFolders, variation_ids::AbstractArray{VariationID})

Return a matrix of Monads based on the given variation IDs.

For each varied location, a matrix of variation IDs is provided.
This information, together with the `inputs`, identifies the monads to be used.

# Returns
- `monad_ids::Array{Monad}`: an array of the monads to be used. Matches the shape of the variations array.
"""
function variationsToMonads(inputs::InputFolders, variation_ids::AbstractArray{VariationID})
    monad_dict = Dict{VariationID, Monad}() #! cache to avoid recreating monads (not necessary, but requires fewer DB queries and so feels cleaner and faster)
    return [get!(monad_dict, variation_id, Monad(inputs, variation_id)) for variation_id in variation_ids]
end