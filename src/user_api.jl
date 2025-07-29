import Base.run

export createTrial, run

"""
    createTrial([method=GridVariation()], inputs::InputFolders, avs::Vector{<:AbstractVariation}=AbstractVariation[];
                n_replicates::Integer=1, use_previous::Bool=true)

Return an object of type `<:AbstractTrial` (simulation, monad, sampling, trial) with the given input folders and elementary variations.

Uses the `avs` and `n_replicates` to determine whether to create a simulation, monad, or sampling.
Despite its name, trials cannot yet be created by this function.
If `n_replicates` is 0, and each variation has a single value, a simulation will be created.

By default, the `method` is `GridVariation()`, which creates a grid of variations from the vector `avs`.
Other methods are: [`LHSVariation`](@ref), [`SobolVariation`](@ref), and [`RBDVariation`](@ref).

Alternate forms (all work with the optional `method` argument in the first position):
Only supplying a single `AbstractVariation`:
```
createTrial(inputs::InputFolders, av::AbstractVariation; n_replicates::Integer=1, use_previous::Bool=true)
```
Using a reference simulation or monad:
```
createTrial(reference::AbstractMonad, avs::Vector{<:AbstractVariation}=AbstractVariation[]; n_replicates::Integer=1,
            use_previous::Bool=true)
```
```
createTrial(reference::AbstractMonad, av::AbstractVariation; n_replicates::Integer=1, use_previous::Bool=true)
```

# Examples
```
inputs = InputFolders(config_folder, custom_code_folder)
dv_max_time = DiscreteVariation([\"overall\", \"max_time\"], 1440)
dv_apoptosis = DiscreteVariation(PhysiCellModelManager.apoptosisPath(cell_type, "rate"), [1e-6, 1e-5])
simulation = createTrial(inputs, dv_max_time)
monad = createTrial(inputs, dv_max_time; n_replicates=2)
sampling = createTrial(monad, dv_apoptosis; n_replicates=2) # uses the max time defined for monad
```
"""
function createTrial(method::AddVariationMethod, inputs::InputFolders, avs::Vector{<:AbstractVariation}=AbstractVariation[];
    n_replicates::Integer=1, use_previous::Bool=true)
    return _createTrial(method, inputs, VariationID(inputs), avs, n_replicates, use_previous)
end

function createTrial(method::AddVariationMethod, inputs::InputFolders, avs::Vararg{AbstractVariation}; kwargs...)
    return createTrial(method, inputs, [avs...]; kwargs...)
end

function createTrial(method::AddVariationMethod, inputs::InputFolders, avs::Vector; kwargs...)
    avs = convertToAbstractVariationVector(avs)
    return createTrial(method, inputs, avs; kwargs...)
end

createTrial(method::AddVariationMethod, inputs::InputFolders, avs::Vararg; kwargs...) = createTrial(method, inputs, [avs...]; kwargs...)

createTrial(inputs::InputFolders, args...; kwargs...) = createTrial(GridVariation(), inputs, args...; kwargs...)

function createTrial(method::AddVariationMethod, reference::AbstractMonad, avs::Vector{<:AbstractVariation}=AbstractVariation[];
                     n_replicates::Integer=1, use_previous::Bool=true)
    return _createTrial(method, reference.inputs, reference.variation_id, avs, n_replicates, use_previous)
end

function createTrial(method::AddVariationMethod, reference::AbstractMonad, avs::Vararg{AbstractVariation}; kwargs...)
    return createTrial(method, reference, [avs...]; kwargs...)
end

function createTrial(method::AddVariationMethod, reference::AbstractMonad, avs::Vector; kwargs...)
    avs = convertToAbstractVariationVector(avs)
    return createTrial(method, reference, avs; kwargs...)
end

createTrial(method::AddVariationMethod, reference::AbstractMonad, avs::Vararg; kwargs...) = createTrial(method, reference, [avs...]; kwargs...)

createTrial(reference::AbstractMonad, args...; kwargs...) = createTrial(GridVariation(), reference, args...; kwargs...)


function convertToAbstractVariationVector(avs::Vector)
    try
        return Vector{AbstractVariation}(avs)
    catch _
        msg = """
        Variations must be a subtype AbstractVariation.
        The following indices of the provided variations are not:
        """
        for (i, av) in enumerate(avs)
            if av isa AbstractVariation
                continue
            end
            msg *= "\n  - Index $i: $(typeof(av))"
        end
        throw(ArgumentError(msg))
    end
end

"""
    _createTrial(args...; kwargs...)

Internal function to create a trial with the given input folders and elementary variations.
Users should use [`createTrial`](@ref) instead.

# Arguments
- `method::AddVariationMethod`: The method to use for creating the trial. Default is `GridVariation()`.
- `inputs::InputFolders`: The input folders for the simulation.
- `reference_variation_id::VariationID`: The variation ID of the reference simulation or monad.
- `avs::Vector{<:AbstractVariation}`: A vector of variations to add to the reference simulation or monad.
- `n_replicates::Integer`: The number of replicates to create. Default is 1.
- `use_previous::Bool`: Whether to use previous simulations.
"""
function _createTrial(method::AddVariationMethod, inputs::InputFolders, reference_variation_id::VariationID,
                      avs::Vector{<:AbstractVariation}, n_replicates::Integer, use_previous::Bool)

    add_variations_result = addVariations(method, inputs, avs, reference_variation_id)
    all_variation_ids = add_variations_result.all_variation_ids
    if length(all_variation_ids) == 1
        variation_ids = all_variation_ids[1]
        monad = Monad(inputs, variation_ids; n_replicates=n_replicates, use_previous=use_previous)
        if n_replicates != 1
            return monad
        end
        return Simulation(simulationIDs(monad)[end])
    else
        location_variation_ids = [loc => [variation_id[loc] for variation_id in all_variation_ids] for loc in projectLocations().varied] |>
            Dict{Symbol,Union{Integer,AbstractArray{<:Integer}}}

        return Sampling(inputs, location_variation_ids;
            n_replicates=n_replicates,
            use_previous=use_previous
        )
    end
end

"""
    run(args...; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), kwargs...)

Run a simulation, monad, sampling, or trial with the same signatures available to [`createTrial`](@ref).
"""
function run(method::AddVariationMethod, args...; force_recompile::Bool=false,
             prune_options::PruneOptions=PruneOptions(), kwargs...)
    trial = createTrial(method, args...; kwargs...)
    return run(trial; force_recompile=force_recompile, prune_options=prune_options)
end

run(inputs::InputFolders, args...; kwargs...) = run(GridVariation(), inputs, args...; kwargs...)

run(reference::AbstractMonad, arg1, args...; kwargs...) = run(GridVariation(), reference, arg1, args...; kwargs...)
