using Dates

export Simulation, Monad, Sampling, Trial, InputFolders

"""
    AbstractTrial

Abstract type for the [`Simulation`](@ref), [`Monad`](@ref), [`Sampling`](@ref), and [`Trial`](@ref) types.

There are no restrictions on inputs or variations for this type.
"""
abstract type AbstractTrial end

"""
    AbstractSampling <: AbstractTrial

Abstract type for the [`Simulation`](@ref), [`Monad`](@ref), and [`Sampling`](@ref) types.

All the inputs must be the same for all associated simulations. Variations can differ.
"""
abstract type AbstractSampling <: AbstractTrial end

"""
    trialType(T::AbstractTrial)

Returns the type of the trial, which can be `Simulation`, `Monad`, `Sampling`, or `Trial`.
"""
trialType(T::AbstractTrial) = typeof(T)

"""
    trialID(T::AbstractTrial)

Returns the ID of the [`AbstractTrial`](@ref) object, which is the ID of the simulation, monad, sampling, or trial.
"""
trialID(T::AbstractTrial) = T.id

"""
    AbstractMonad <: AbstractSampling

Abstract type for the [`Simulation`](@ref) and [`Monad`](@ref) types.

All the inputs and variations must be the same for all associated simulations.
"""
abstract type AbstractMonad <: AbstractSampling end

Base.length(T::AbstractTrial) = simulationIDs(T) |> length

##########################################
############   InputFolders   ############
##########################################

"""
    InputFolder

Hold the information for a single input folder.

Users should use the `InputFolders` to create and access individual `InputFolder` objects.

# Fields
- `location::Symbol`: The location of the input folder, e.g. `:config`, `:custom_code`, etc. Options are defined in `data/inputs/inputs.toml`.
- `id::Int`: The ID of the input folder in the database.
- `folder::String`: The name of the input folder. It will be in `data/inputs/<path_from_inputs>`.
- `basename::Union{String,Missing}`: The basename of the input file. This can be used to determine if the input file is varied.
- `required::Bool`: Whether the input folder is required. This is defined in `data/inputs/inputs.toml`.
- `varied::Bool`: Whether the input folder is varied. This is determined by the presence of a varied basename in the input folder.
- `path_from_inputs::String`: The path from the `data/inputs` directory to the input folder. This is defined in `data/inputs/inputs.toml`.
"""
struct InputFolder
    location::Symbol
    id::Int
    folder::String
    basename::Union{String,Missing}
    required::Bool
    varied::Bool
    path_from_inputs::String

    function InputFolder(location::Symbol, id::Int, folder::String)
        location_dict = inputsDict()[location]
        required = location_dict["required"]
        if isempty(folder)
            if required
                error("Folder for $location must be provided")
            end
            return new(location, id, folder, missing, required, false, "")
        end
        path_from_inputs = joinpath(location_dict["path_from_inputs"], folder)
        basename = location_dict["basename"]
        varied = folderIsVaried(location, folder)
        if basename isa Vector
            possible_files = [joinpath(locationPath(location, folder), x) for x in basename]
            basename_index = possible_files .|> isfile |> findfirst
            if isnothing(basename_index)
                error("Neither of $possible_files exist")
            end
            basename = basename[basename_index]
        end
        return new(location, id, folder, basename, required, varied, path_from_inputs)
    end

    function InputFolder(location::Symbol, id::Int)
        folder = inputFolderName(location, id)
        return InputFolder(location, id, folder)
    end

    function InputFolder(location::Symbol, folder::String)
        id = inputFolderID(location, folder)
        return InputFolder(location, id, folder)
    end
end

function Base.show(io::IO, ::MIME"text/plain", input_folder::InputFolder)
    println(io, "InputFolder:")
    println(io, "  Location: $(input_folder.location)")
    println(io, "  ID: $(input_folder.id)")
    println(io, "  Folder: $(input_folder.folder)")
    println(io, "  Basename: $(input_folder.basename)")
    println(io, "  Required: $(input_folder.required)")
    println(io, "  Varied: $(input_folder.varied)")
end

"""
    InputFolders

Consolidate the folder information for a simulation/monad/sampling.

Pass the folder names within the `inputs/<path_from_inputs>` directory to create an `InputFolders` object.
The `path_from_inputs` is defined in the `data/inputs/inputs.toml` file for each.
It is possible to acces the [`InputFolder`](@ref) values using index notation, e.g. `input_folders[:config]`.

Several constructors exist:
1. All folders passed as keyword arguments. Omitted folders are assumed to be \"\", i.e. those inputs are unused.
```julia
InputFolders(; config="default", custom_codes="default", rulesets_collection="default")
```
2. Pass in the required inputs as arguments and the optional inputs as keyword arguments. The required folders must be passed in alphabetical order.
Refer to the names defined in `data/inputs/inputs.toml` to see this order. Omitted optional folders are assumed to be \"\", i.e. those inputs are unused.
```julia
config_folder = "default"
custom_code_folder = "default"
ic_cell_folder = "cells_in_disc"
InputFolders(config_folder, custom_code_folder; ic_cell=ic_cell_folder)
```

# Fields
- `input_folders::NamedTuple`: The input locations defined in `data/inputs/inputs.toml` define the keys. The values are [`InputFolder`](@ref)s.
"""
struct InputFolders
    input_folders::NamedTuple

    function InputFolders(location_pairs::Vector{<:Pair{Symbol,<:Union{String,Int}}})
        locs_already_here = first.(location_pairs)
        invalid_locations = setdiff(locs_already_here, projectLocations().all)
        @assert isempty(invalid_locations) "Invalid locations: $invalid_locations.\nPossible locations are: $(projectLocations()).all)"
        for loc in setdiff(projectLocations().all, locs_already_here)
            push!(location_pairs, loc => "")
        end
        return new([loc => InputFolder(loc, val) for (loc, val) in location_pairs] |> NamedTuple)
    end

    function InputFolders(; kwargs...)
        return InputFolders([loc => val for (loc, val) in kwargs])
    end
end

#! let the linter know that there will be a function like this after initialization
#! this is the function that takes in the required inputs as positional arguments and the optional inputs as keyword arguments
function InputFolders(args...; kwargs...) end

"""
    createSimpleInputFolders()

Creates a simple method for creating `InputFolders` objects at module initialization based on `data/inputs/inputs.toml`.

The required inputs are sorted alphabetically and used as the positional arguments.
The optional inputs are used as keyword arguments with a default value of `\"\"`, indicating they are unused.
"""
function createSimpleInputFolders()
    fn_args = join(["$(location)::String" for location in projectLocations().required], ", ")
    fn_kwargs = join(["$(location)::String=\"\"" for location in setdiff(projectLocations().all, projectLocations().required)], ", ")
    ret_val = "[$(join([":$(location) => $(location)" for location in projectLocations().all], ", "))] |> InputFolders"
    """
    function InputFolders($(fn_args); $(fn_kwargs))
        return $(ret_val)
    end
    """ |> Meta.parse |> eval
    return
end

Base.getindex(input_folders::InputFolders, loc::Symbol) = input_folders.input_folders[loc]

function Base.show(io::IO, ::MIME"text/plain", input_folders::InputFolders)
    println(io, "InputFolders:")
    printInputFolders(io, input_folders)
end

"""
    printInputFolders(io::IO, input_folders::InputFolders, n_indent::Int=1)

Prints the folder information for each input folder in the InputFolders object.
"""
function printInputFolders(io::IO, input_folders::InputFolders, n_indent::Int=1)
    for (loc, input_folder) in pairs(input_folders.input_folders)
        if isempty(input_folder.folder)
            continue
        end
        println(io, "  "^n_indent, "$loc: $(input_folder.folder)")
    end
end

##########################################
############   Variation IDs  ############
##########################################

"""
    VariationID

The variation IDs for any of the possibly varying inputs.

For each input type that can be varied, a record of the current variation ID for that input type.
By convention, a values of `-1` indicates that the input is not being used (hence this is disallowed for a `required` input type).
A value of `0` indicates that the base file is being used, unvaried.
Hence, if the input type is sometimes varied (such as `ic_cell` with a `cells.csv` file), this value must be `0` in such conditions.
"""
struct VariationID
    ids::NamedTuple

    function VariationID(inputs::InputFolders)
        return new((loc => inputs[loc].id == -1 ? -1 : 0 for loc in projectLocations().varied) |> NamedTuple)
    end

    function VariationID(x::Vector{Pair{Symbol,Int}})
        #! this is slightly dangerous since no checks are made that the locations are valid.
        #! but it is called often enough internally that it is worth it to have this constructor without checks
        #! if this is added to the public API, then checks should be added
        return new(x |> NamedTuple)
    end
end

Base.getindex(variation_id::VariationID, loc::Symbol) = variation_id.ids[loc]

function Base.show(io::IO, ::MIME"text/plain", variation_id::VariationID)
    println(io, "VariationID:")
    printVariationID(io, variation_id)
end

"""
    printVariationID(io::IO, variation_id::VariationID, n_indent::Int=1)

Prints the variation ID information for each varied input in the VariationID object.
"""
function printVariationID(io::IO, variation_id::VariationID, n_indent::Int=1)
    for (loc, id) in pairs(variation_id.ids)
        if id == -1
            continue
        end
        println(io, "  "^n_indent, "$loc: $id")
    end
end

##########################################
#############   Simulation   #############
##########################################

"""
    Simulation

A simulation that represents a single run of the model.

To create a new simulation, best practice is to use `createTrial` and supply it with the `InputFolders` and any number of single-valued DiscreteVariations:
```julia
inputs = InputFolders(config_folder, custom_code_folder)
simulation = createTrial(inputs) # uses the default config file as-is

ev = DiscreteVariation(configPath("max_time"), 1440)
simulation = createTrial(inputs, ev) # uses the config file with the specified variation
```

If there is a previously created simulation that you wish to access, you can use its ID to create a `Simulation` object:
```julia
simulation = Simulation(simulation_id)
```

Finally, a new `Simulation` object can be created from an existing `Monad` object.
This will not use a simulation already in the database, but will create a new one with the same inputs and variations:
```julia
simulation = Simulation(monad)
```

# Fields
- `id::Int`: integer uniquely identifying this simulation. Matches with the folder in `data/outputs/simulations/`
- `inputs::InputFolders`: contains the folder info for this simulation.
- `variation_id::VariationID`: contains the variation IDs for this simulation.
"""
struct Simulation <: AbstractMonad
    id::Int #! integer uniquely identifying this simulation
    inputs::InputFolders
    variation_id::VariationID

    function Simulation(id::Int, inputs::InputFolders, variation_id::VariationID)
        @assert id > 0 "Simulation id must be positive. Got $id."
        for location in projectLocations().varied
            if inputs[location].required
                @assert variation_id[location] >= 0 "$(location) variation id must be non-negative. Got $(variation_id[location])."
            elseif inputs[location].id == -1
                @assert variation_id[location] == -1 "$(location) variation id must be -1 because there is no associated folder indicating $(location) is not in use. Got $(variation_id[location])."
            #! now we know this location is not required and it is in use
            elseif !inputs[location].varied
                #! this particular folder is not varying it, so make sure its variation id is 0, i.e. the base file in this folder
                @assert variation_id[location] == 0 "$(inputs[location].folder) in $(location) is not varying but the variation id is not 0. Got $(variation_id[location])."
            #! now we know that the folder is being varied, so just make sure the variation id is >=0
            else
                @assert variation_id[location] >= 0 "$(location) variation id must be non-negative as the folder $(inputs[location].folder) is varying. Got $(variation_id[location])."
            end
        end
        return new(id, inputs, variation_id)
    end
end

function Simulation(inputs::InputFolders, variation_id::VariationID=VariationID(inputs))
    simulation_id = DBInterface.execute(centralDB(),
    """
    INSERT INTO simulations (\
    physicell_version_id,\
    $(join(locationIDNames(), ",")),\
    $(join(locationVariationIDNames(), ",")),\
    status_code_id\
    ) \
    VALUES(\
    $(currentPhysiCellVersionID()),\
    $(join([inputs[loc].id for loc in projectLocations().all], ",")),\
    $(join([variation_id[loc] for loc in projectLocations().varied],",")),\
    $(statusCodeID("Not Started"))
    )
    RETURNING simulation_id;
    """
    ) |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, inputs, variation_id)
end

function Simulation(simulation_id::Int)
    df = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id);") |> queryToDataFrame
    if isempty(df)
        error("Simulation $(simulation_id) not in the database.")
    end
    inputs = [loc => df[1, locationIDName(loc)] for loc in projectLocations().all] |> InputFolders
    variation_id = [loc => df[1, locationVariationIDName(loc)] for loc in projectLocations().varied] |> VariationID

    return Simulation(simulation_id, inputs, variation_id)
end

Base.length(simulation::Simulation) = 1

function Base.show(io::IO, ::MIME"text/plain", simulation::Simulation)
    println(io, "Simulation (ID=$(simulation.id)):")
    println(io, "  Inputs:")
    printInputFolders(io, simulation.inputs, 2)
    println(io, "  Variation ID:")
    printVariationID(io, simulation.variation_id, 2)
end

##########################################
###############   Monad   ################
##########################################

"""
    Monad

A group of simulations that are identical up to randomness.

To create a new monad, best practice is to use `createTrial` and supply it with the `InputFolders` and any number of single-valued DiscreteVariations.
Set `n_replicates=0` to avoid adding new simulations to the database. This is useful for creating references for later use.
Otherwise, set `n_replicates` > 1 to create the simulations to go with this monad.
If `n_replicates` = 1, it will return a `Simulation` object.
```julia
inputs = InputFolders(config_folder, custom_code_folder)
monad = createTrial(inputs; n_replicates=0) # uses the default config file as-is

ev = DiscreteVariation(configPath("max_time"), 1440)
monad = createTrial(inputs, ev; n_replicates=10) # uses the config file with the specified variation

monad = createTrial(inputs, ev; n_replicates=10, use_previous=false) # changes the default behavior and creates 10 new simulations for this monad
```

If there is a previously created monad that you wish to access, you can use its ID to create a `Monad` object:
```julia
monad = Monad(monad_id)
monad = Monad(monad_id; n_replicates=5) # ensures at least 5 simulations in the monad (using previous sims)
```

# Fields
- `id::Int`: integer uniquely identifying this monad. Matches with the folder in `data/outputs/monads/`
- `inputs::InputFolders`: contains the folder info for this monad.
- `variation_id::VariationID`: contains the variation IDs for this monad.
"""
struct Monad <: AbstractMonad
    #! a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int #! integer uniquely identifying this monad
    inputs::InputFolders #! contains the folder names for the simulations in this monad
    variation_id::VariationID #! contains the variation IDs for the simulations in this monad

    function Monad(inputs::InputFolders, variation_id::VariationID=VariationID(inputs); n_replicates::Integer=0, use_previous::Bool=true)
        feature_str = """
        (\
        physicell_version_id,\
        $(join(locationIDNames(), ",")),\
        $(join(locationVariationIDNames(), ","))\
        ) \
        """
        value_str = """
        (\
        $(currentPhysiCellVersionID()),\
        $(join([inputs[loc].id for loc in projectLocations().all], ",")),\
        $(join([variation_id[loc] for loc in projectLocations().varied],","))\
        ) \
        """
        monad_id = DBInterface.execute(centralDB(),
            """
            INSERT OR IGNORE INTO monads $feature_str VALUES $value_str RETURNING monad_id;
            """
        ) |> DataFrame |> x -> x.monad_id
        if isempty(monad_id)
            monad_id = constructSelectQuery(
                "monads",
                """
                WHERE $feature_str=$value_str
                """;
                selection="monad_id"
            ) |> queryToDataFrame |> x -> x.monad_id[1] #! get the monad_id
        else
            monad_id = monad_id[1] #! get the monad_id
        end
        return Monad(monad_id, inputs, variation_id, n_replicates, use_previous)
    end

    function Monad(id::Int, inputs::InputFolders, variation_id::VariationID, n_replicates::Int, use_previous::Bool)
        @assert id > 0 "Monad id must be positive. Got $id."
        @assert n_replicates >= 0 "Monad n_replicates must be non-negative. Got $n_replicates."

        previous_simulation_ids = readConstituentIDs(Monad, id)
        new_simulation_ids = Int[]
        num_sims_to_add = n_replicates - (use_previous ? length(previous_simulation_ids) : 0)
        if num_sims_to_add > 0
            for _ = 1:num_sims_to_add
                simulation = Simulation(inputs, variation_id) #! create a new simulation
                push!(new_simulation_ids, simulation.id)
            end
            recordConstituentIDs(Monad, id, [previous_simulation_ids; new_simulation_ids]) #! record the simulation ids in a .csv file
        end

        return new(id, inputs, variation_id)
    end

end

function Monad(monad_id::Integer; n_replicates::Integer=0, use_previous::Bool=true)
    df = constructSelectQuery("monads", "WHERE monad_id=$(monad_id);") |> queryToDataFrame
    if isempty(df)
        error("Monad $(monad_id) not in the database.")
    end
    inputs = [loc => df[1, locationIDName(loc)] for loc in projectLocations().all] |> InputFolders
    variation_id = [loc => df[1, locationVariationIDName(loc)] for loc in projectLocations().varied] |> VariationID
    return Monad(monad_id, inputs, variation_id, n_replicates, use_previous)
end

function Monad(simulation::Simulation; n_replicates::Integer=0, use_previous::Bool=true)
    monad = Monad(simulation.inputs, simulation.variation_id; n_replicates=n_replicates, use_previous=use_previous)
    addSimulationID(monad, simulation.id)
    return monad
end

function Monad(monad::Monad; n_replicates::Integer=0, use_previous::Bool=true)
    return Monad(monad.id, monad.inputs, monad.variation_id, n_replicates, use_previous)
end

"""
    addSimulationID(monad::Monad, simulation_id::Int)

Adds a simulation ID to the monad's list of simulation IDs.
"""
function addSimulationID(monad::Monad, simulation_id::Int)
    simulation_ids = simulationIDs(monad)
    if simulation_id in simulation_ids
        return
    end
    push!(simulation_ids, simulation_id)
    recordConstituentIDs(monad, simulation_ids)
    return
end

function Simulation(monad::Monad)
    return Simulation(monad.inputs, monad.variation_id)
end

function Base.show(io::IO, ::MIME"text/plain", monad::Monad)
    println(io, "Monad (ID=$(monad.id)):")
    println(io, "  Inputs:")
    printInputFolders(io, monad.inputs, 2)
    println(io, "  Variation ID:")
    printVariationID(io, monad.variation_id, 2)
    printSimulationIDs(io, monad)
end

function printSimulationIDs(io::IO, T::AbstractTrial, n_indent::Int=1)
    simulation_ids = simulationIDs(T) |> compressIDs
    simulation_ids = join(simulation_ids[1], ", ")
    simulation_ids = replace(simulation_ids, ":" => "-")
    println(io, "  "^n_indent, "Simulations: $simulation_ids")
end

##########################################
##############   Sampling   ##############
##########################################

"""
    Sampling

A group of monads that have the same input folders, but differ in parameter values.

To create a new sampling, best practice is to use `createTrial` and supply it with the `InputFolders` and any number of DiscreteVariations.
At least one should have multiple values to create a sampling.
```julia
inputs = InputFolders(config_folder, custom_code_folder)
ev = DiscreteVariation(configPath("max_time"), [1440, 2880]))
sampling = createTrial(inputs, ev; n_replicates=3, use_previous=true)
```

If there is a previously created sampling that you wish to access, you can use its ID to create a `Sampling` object:
```julia
sampling = Sampling(sampling_id)
sampling = Sampling(sampling_id; n_replicates=5) # ensures at least 5 simulations in each monad (using previous sims)
sampling = Sampling(sampling_id; n_replicates=5, use_previous=false) # creates 5 new simulations in each monad
```

If you have a vector of `Monad` objects that you wish to group into a sampling, you can use the constructor:
```julia
sampling = Sampling(monads; n_replicates=0, use_previous=true)
```
which will create a new `Sampling` object with the provided monads, ensuring each has at least `n_replicates` simulations per monad, using previous simulations if requested and available.

# Fields
- `id::Int`: integer uniquely identifying this sampling. Matches with the folder in `data/outputs/samplings/`
- `inputs::InputFolders`: contains the folder info for this sampling.
- `monads::Vector{Monad}`: array of monads belonging to this sampling.
"""
struct Sampling <: AbstractSampling
    #! sampling is a group of monads with parameters varied
    id::Int #! integer uniquely identifying this sampling
    inputs::InputFolders #! contains the folder names for this sampling
    monads::Vector{Monad} #! contains the monads belonging to this sampling

    function Sampling(monads::AbstractVector{Monad}, inputs::InputFolders)
        id = -1
        sampling_ids = constructSelectQuery(
            "samplings",
            """
            WHERE (\
            physicell_version_id,\
            $(join(locationIDNames(), ","))\
            )=\
            (\
            $(currentPhysiCellVersionID()),\
            $(join([inputs[loc].id for loc in projectLocations().all], ","))\
            );\
            """;
            selection="sampling_id"
        ) |> queryToDataFrame |> x -> x.sampling_id

        monad_ids = [monad.id for monad in monads]
        if !isempty(sampling_ids) #! if there are previous samplings with the same parameters
            for sampling_id in sampling_ids #! check if the monad_ids are the same with any previous monad_ids
                monad_ids_in_sampling = readConstituentIDs(Sampling, sampling_id) #! get the monad_ids belonging to this sampling
                if symdiff(monad_ids_in_sampling, monad_ids) |> isempty #! if the monad_ids are the same
                    id = sampling_id #! use the existing sampling_id
                    break
                end
            end
        end

        if id==-1 #! if no previous sampling was found matching these parameters
            id = DBInterface.execute(centralDB(),
                """
                INSERT INTO samplings \
                (\
                physicell_version_id,\
                $(join(locationIDNames(), ","))\
                ) \
                VALUES(\
                $(currentPhysiCellVersionID()),\
                $(join([inputs[loc].id for loc in projectLocations().all], ","))\
                ) RETURNING sampling_id;
                """
            ) |> DataFrame |> x -> x.sampling_id[1] #! get the sampling_id
            recordConstituentIDs(Sampling, id, monad_ids) #! record the monad ids in a .csv file
        end
        return Sampling(id, inputs, monads)
    end

    function Sampling(id::Int, inputs::InputFolders, monads::Vector{Monad})
        @assert id > 0 "Sampling id must be positive. Got $id."
        @assert !isempty(monads) "At least one monad must be provided"
        for monad in monads
            @assert monad.inputs == inputs "All monads must have the same inputs. You can instead make these into a Trial. Got $(monad.inputs) and $(inputs)."
        end
        @assert Set(readConstituentIDs(Sampling, id)) == Set([monad.id for monad in monads]) "Monad ids do not match those in the database for Sampling $(id):\n$(Set(readConstituentIDs(Sampling, id)))\nvs\n$(Set([monad.id for monad in monads]))"
        return new(id, inputs, monads)
    end
end

function Sampling(inputs::InputFolders, variation_ids::AbstractArray{VariationID}; n_replicates::Integer=0, use_previous::Bool=true)
    monads = [Monad(inputs, variation_id; n_replicates=n_replicates, use_previous=use_previous) for variation_id in variation_ids]
    return Sampling(monads, inputs)
end

function Sampling(inputs::InputFolders,
                  location_variation_ids::Dict{Symbol,<:Union{Integer,AbstractArray{<:Integer}}};
                  n_replicates::Integer=0,
                  use_previous::Bool=true)
    #! allow for passing in a single config_variation_id and/or rulesets_collection_variation_id
    #! later, can support passing in (for example) a 3x6 config_variation_ids and a 3x1 rulesets_collection_variation_ids and expanding the rulesets_collection_variation_ids to 3x6, but that can get tricky fast
    if all(x->x isa Integer, values(location_variation_ids))
        for (loc, loc_var_ids) in pairs(location_variation_ids)
            location_variation_ids[loc] = [loc_var_ids]
        end
    else
        ns = [length(x) for x in values(location_variation_ids) if !(x isa Integer)]
        @assert all(x->x==ns[1], ns) "location variation ids must have the same length if they are not integers. Got $(ns)."
        for (loc, loc_var_ids) in pairs(location_variation_ids)
            if loc_var_ids isa Integer
                location_variation_ids[loc] = fill(loc_var_ids, ns[1])
            end
        end
    end
    n = location_variation_ids |> values |> first |> length
    for loc in setdiff(projectLocations().varied, keys(location_variation_ids))
        location_variation_ids[loc] = fill(inputs[loc].id==-1 ? -1 : 0, n)
    end
    variation_ids = [([loc => loc_var_ids[i] for (loc, loc_var_ids) in pairs(location_variation_ids)] |> VariationID) for i in 1:n]
    return Sampling(inputs, variation_ids; n_replicates=n_replicates, use_previous=use_previous)
end

function Sampling(Ms::AbstractArray{<:AbstractMonad}; n_replicates::Integer=0, use_previous::Bool=true)
    @assert !isempty(Ms) "At least one monad must be provided"
    inputs = Ms[1].inputs
    for M in Ms
        @assert M.inputs == inputs "All Ms must have the same inputs. You can instead make these into a Trial. Got $(M.inputs) and $(inputs)."
    end
    monads = [Monad(M; n_replicates=n_replicates, use_previous=use_previous) for M in Ms] #! this step ensures that the monads all have the min number of replicates ready
    return Sampling(monads, inputs)
end

Sampling(M::AbstractMonad; kwargs...) = Sampling([M]; kwargs...)

function Sampling(sampling_id::Int; n_replicates::Integer=0, use_previous::Bool=true)
    df = constructSelectQuery("samplings", "WHERE sampling_id=$(sampling_id);") |> queryToDataFrame
    if isempty(df)
        error("Sampling $(sampling_id) not in the database.")
    end
    monad_ids = readConstituentIDs(Sampling, sampling_id)
    monads = Monad.(monad_ids; n_replicates=n_replicates, use_previous=use_previous)
    inputs = monads[1].inputs #! readConstituentIDs() should be returning monads already associated with a Sampling and thus having the same inputs
    return Sampling(sampling_id, inputs, monads)
end

Sampling(sampling::Sampling; kwargs...) = Sampling(sampling.id; kwargs...)

function Base.show(io::IO, ::MIME"text/plain", sampling::Sampling)
    println(io, "Sampling (ID=$(sampling.id)):")
    printMonadIDs(io, sampling)
    println(io, "  Inputs:")
    printInputFolders(io, sampling.inputs, 2)
end

function printMonadIDs(io::IO, sampling::Sampling, n_indent::Int=1)
    monad_ids = readConstituentIDs(sampling) |> compressIDs
    monad_ids = join(monad_ids[1], ", ")
    monad_ids = replace(monad_ids, ":" => "-")
    println(io, "  "^n_indent, "Monads: $(monad_ids)")
end

##########################################
###############   Trial   ################
##########################################

"""
    Trial

A group of samplings that can have different input folders.

To create a new trial, best practice currently is to create a vector of `Sampling` objects and passing them to `Trial`.
```julia
inputs_1 = InputFolders(config_folder_1, custom_code_folder_1)
inputs_2 = InputFolders(config_folder_2, custom_code_folder_2)
ev = DiscreteVariation(configPath("max_time"), [1440, 2880]))
sampling_1 = createTrial(inputs_1, ev; n_replicates=3, use_previous=true)
sampling_2 = createTrial(inputs_2, ev; n_replicates=3, use_previous=true)
trial = Trial([sampling_1, sampling_2])
```

If there is a previous trial that you wish to access, you can use its ID to create a `Trial` object:
```julia
trial = Trial(trial_id)
trial = Trial(trial_id; n_replicates=5) # ensures at least 5 simulations in each monad (using previous sims)
trial = Trial(trial_id; n_replicates=5, use_previous=false) # creates 5 new simulations in each monad
```

# Fields
- `id::Int`: integer uniquely identifying this trial. Matches with the folder in `data/outputs/trials/`
- `inputs::Vector{InputFolders}`: contains the folder info for each sampling in this trial.
- `variation_ids::Vector{Vector{VariationID}}`: contains the variation IDs for each monad in each sampling in this trial.
"""
struct Trial <: AbstractTrial
    #! trial is a group of samplings with different ICs, custom codes, rulesets, and/or intracellulars
    id::Int #! integer uniquely identifying this trial
    samplings::Vector{Sampling} #! contains the samplings belonging to this trial

    function Trial(id::Integer, samplings::Vector{Sampling})
        @assert id > 0 "Trial id must be positive. Got $id."
        @assert Set(readConstituentIDs(Trial, id)) == Set([sampling.id for sampling in samplings]) "Samplings do not match the samplings in the database."
        return new(id, samplings)
    end
end

function Trial(Ss::AbstractArray{<:AbstractSampling}; n_replicates::Integer=0, use_previous::Bool=true)
    samplings = Sampling.(Ss; n_replicates=n_replicates, use_previous=use_previous)
    id = trialID(samplings)
    return Trial(id, samplings)
end

function Trial(trial_id::Int; n_replicates::Integer=0, use_previous::Bool=true)
    df = constructSelectQuery("trials", "WHERE trial_id=$(trial_id);") |> queryToDataFrame
    @assert !isempty(df) "Trial $(trial_id) not in the database."
    samplings = Sampling.(readConstituentIDs(Trial, trial_id); n_replicates=n_replicates, use_previous=use_previous)
    @assert !isempty(samplings) "No samplings found for trial_id=$trial_id. This trial has not been created."
    samplings = Sampling.(readConstituentIDs(Trial, trial_id); n_replicates=n_replicates, use_previous=use_previous)
    return Trial(trial_id, samplings)
end

"""
    trialID(samplings::Vector{Sampling})

Get the trial ID for a vector of samplings or create a new trial if one does not exist.
"""
function trialID(samplings::Vector{Sampling})
    sampling_ids = [sampling.id for sampling in samplings]
    id = -1
    trial_ids = constructSelectQuery("trials"; selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
    if !isempty(trial_ids) #! if there are previous trials
        for trial_id in trial_ids #! check if the sampling_ids are the same with any previous sampling_ids
            sampling_ids_in_db = readConstituentIDs(Trial, trial_id) #! get the sampling_ids belonging to this trial
            if symdiff(sampling_ids_in_db, sampling_ids) |> isempty #! if the sampling_ids are the same
                id = trial_id #! use the existing trial_id
                break
            end
        end
    end

    if id==-1 #! if no previous trial was found matching these parameters
        id = DBInterface.execute(centralDB(), "INSERT INTO trials (datetime) VALUES($(Dates.format(now(),"yymmddHHMM"))) RETURNING trial_id;") |> DataFrame |> x -> x.trial_id[1] #! get the trial_id
        recordConstituentIDs(Trial, id, sampling_ids) #! record the sampling ids in a .csv file
    end

    return id
end

function Base.show(io::IO, ::MIME"text/plain", trial::Trial)
    println(io, "Trial (ID=$(trial.id)):")
    for sampling in trial.samplings
        println(io, "  Sampling (ID=$(sampling.id)):")
        printMonadIDs(io, sampling, 2)
    end
end