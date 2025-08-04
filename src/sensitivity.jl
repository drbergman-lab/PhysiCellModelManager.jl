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
    method = split(method, ".")[end] #! remove module name that comes with the type, e.g. main.vctmodule.moatsampling -> moatsampling
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

function Base.show(io::IO, ::MIME"text/plain", moat_sampling::MOATSampling)
    println(io, "MOAT sampling")
    println(io, "-------------")
    show(io, MIME"text/plain"(), moat_sampling.sampling)
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
- `ignore_indices::AbstractVector{<:Integer}=[]`: indices into `pv.variations` to ignore when perturbing the parameters. Only used for [Sobolʼ](@ref).
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
    variation_ids = add_variations_result.all_variation_ids
    base_variation_ids = Dict{Symbol, Vector{Int}}()
    perturbed_variation_ids = Dict{Symbol, Matrix{Int}}()

    proj_locs = projectLocations()
    for location in proj_locs.varied
        base_variation_ids[location] = [variation_id[location] for variation_id in variation_ids]
        perturbed_variation_ids[location] = repeat(base_variation_ids[location], 1, length(pv.sz))
    end
    for (base_point_ind, variation_id) in enumerate(variation_ids) #! for each base point in the LHS
        for d in eachindex(pv.sz) #! perturb each feature one time
            for location in proj_locs.varied
                perturbed_variation_ids[location][base_point_ind, d] = perturbVariation(location, pv, inputs[location].folder, variation_id[location], d)
            end
        end
    end
    all_variation_ids = Dict{Symbol, Matrix{Int}}()
    for location in proj_locs.varied
        all_variation_ids[location] = hcat(base_variation_ids[location], perturbed_variation_ids[location])
    end
    location_variation_dict = (loc => all_variation_ids[loc] for loc in proj_locs.varied) |> Dict
    monad_dict, monad_ids = variationsToMonads(inputs, location_variation_dict)
    header_line = ["base"; columnName.(pv.variations)]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(monad_dict |> values |> collect; n_replicates=n_replicates, use_previous=use_previous)
    run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return MOATSampling(sampling, monad_ids_df)
end

"""
    perturbVariation(location::Symbol, pv::ParsedVariations, folder::String, reference_variation_id::Int, d::Int)

Perturb the variation at the given location and dimension for [`MOAT`](@ref) global sensitivity analysis.
"""
function perturbVariation(location::Symbol, pv::ParsedVariations, folder::String, reference_variation_id::Int, d::Int)
    matching_dims = pv[location].indices .== d
    evs = pv[location].variations[matching_dims] #! all the variations associated with the dth feature
    if isempty(evs)
        return reference_variation_id
    end
    base_values = variationValue.(evs, reference_variation_id, folder)

    cdfs_at_base = [cdf(ev, bv) for (ev, bv) in zip(evs, base_values)]
    @assert maximum(cdfs_at_base) - minimum(cdfs_at_base) < 1e-10 "All base values must have the same CDF (within tolerance).\nInstead, got $cdfs_at_base."
    dcdf = cdfs_at_base[1] < 0.5 ? 0.5 : -0.5
    new_values = variationValues.(evs, cdfs_at_base[1] + dcdf) #! note, this is a vector of values

    discrete_variations = [DiscreteVariation(variationTarget(ev), new_value) for (ev, new_value) in zip(evs, new_values)]

    new_variation_id = gridToDB(discrete_variations, inputFolderID(location, folder), reference_variation_id)
    @assert length(new_variation_id) == 1 "Only doing one perturbation at a time."
    return new_variation_id[1]
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

function Base.show(io::IO, ::MIME"text/plain", sobol_sampling::SobolSampling)
    println(io, "Sobol sampling")
    println(io, "--------------")
    show(io, MIME"text/plain"(), sobol_sampling.sampling)
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
    all_variation_ids = add_variations_result.all_variation_ids
    cdfs = add_variations_result.cdfs
    d = length(pv.sz)
    focus_indices = [i for i in 1:d if !(i in ignore_indices)]

    proj_locs = projectLocations()
    location_variation_ids_A = [loc => [variation_id[loc] for variation_id in all_variation_ids[:,1]] for loc in proj_locs.varied] |> Dict
    A = cdfs[:,1,:] #! cdfs is of size (d, 2, n), i.e., d = # parameters, 2 design matrices, and n = # samples
    location_variation_ids_B = [loc => [variation_id[loc] for variation_id in all_variation_ids[:,2]] for loc in proj_locs.varied] |> Dict
    B = cdfs[:,2,:]
    Aᵦ = [i => copy(A) for i in focus_indices] |> Dict
    location_variation_ids_Aᵦ = [loc => [i => copy(location_variation_ids_A[loc]) for i in focus_indices] |> Dict for loc in proj_locs.varied] |> Dict
    for i in focus_indices
        Aᵦ[i][i,:] .= B[i,:]
        for loc in proj_locs.varied
            if i in pv[loc].indices
                location_variation_ids_Aᵦ[loc][i][:] .= cdfsToVariations(loc, pv, inputs[loc].id, reference_variation_id[loc], Aᵦ[i]')
            end
        end
    end
    location_variation_ids_dict = [loc => hcat(location_variation_ids_A[loc], location_variation_ids_B[loc], [location_variation_ids_Aᵦ[loc][i] for i in focus_indices]...) for loc in proj_locs.varied] |> Dict{Symbol,Matrix{Int}}
    monad_dict, monad_ids = variationsToMonads(inputs, location_variation_ids_dict)
    monads = monad_dict |> values |> collect
    header_line = ["A"; "B"; columnName.(pv.variations[focus_indices])]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(monads; n_replicates=n_replicates, use_previous=use_previous)
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

function Base.show(io::IO, ::MIME"text/plain", rbd_sampling::RBDSampling)
    println(io, "RBD sampling")
    println(io, "------------")
    show(io, MIME"text/plain"(), rbd_sampling.sampling)
    println(io, "Number of harmonics: $(rbd_sampling.num_harmonics)")
    println(io, "Number of cycles (1/2 or 1): $(rbd_sampling.num_cycles)")
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
    location_variation_ids_dict = add_variations_result.location_variation_ids_dict
    monad_dict, monad_ids = variationsToMonads(inputs, location_variation_ids_dict)
    monads = monad_dict |> values |> collect
    header_line = columnName.(pv.variations)
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(monads; n_replicates=n_replicates, use_previous=use_previous)
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
            simulation_ids = readConstituentIDs(Monad, monad_id)
            sim_values = [f(simulation_id) for simulation_id in simulation_ids]
            value = sim_values |> mean
            value_dict[monad_id] = value
        end
        vals[ind] = value_dict[monad_id]
    end
    return vals
end

"""
    variationsToMonads(inputs::InputFolders, variation_ids::Dict{Symbol,Matrix{Int}}, use_previous::Bool)

Return a dictionary of monads and a matrix of monad IDs based on the given variation IDs.

The five matrix inputs together define a single matrix of variation IDs.
This information, together with the `inputs`, identifies the monads to be used.
The `use_previous` flag determines whether to use previous simulations, if they exist.

# Returns
- `monad_dict::Dict{VariationID, Monad}`: a dictionary of the monads to be used without duplicates.
- `monad_ids::Matrix{Int}`: a matrix of the monad IDs to be used. Matches the shape of the input IDs matrices.
"""
function variationsToMonads(inputs::InputFolders, location_variation_ids_dict::Dict{Symbol,Matrix{Int}})
    monad_dict = Dict{VariationID, Monad}()
    monad_ids = zeros(Int, size(location_variation_ids_dict |> values |> first))
    for i in eachindex(monad_ids)
        monad_variation_id = [loc => location_variation_ids_dict[loc][i] for loc in projectLocations().varied] |> VariationID
        if haskey(monad_dict, monad_variation_id)
            monad_ids[i] = monad_dict[monad_variation_id].id
            continue
        end
        monad = Monad(inputs, monad_variation_id)
        monad_dict[monad_variation_id] = monad
        monad_ids[i] = monad.id
    end
    return monad_dict, monad_ids
end