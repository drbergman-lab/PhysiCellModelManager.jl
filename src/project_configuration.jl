using TOML

"""
    ProjectLocations

A struct that contains information about the locations of input files in the project.

The global instance of this struct is `project_locations` in `pcmm_globals` (the sole instance of [`PCMMGlobals`](@ref)) and is created by reading the `inputs.toml` file in the data directory.
It is instantiated with the [`parseProjectInputsConfigurationFile`](@ref) function.

# Fields
- `all::NTuple{L,Symbol}`: A tuple of all locations in the project.
- `required::NTuple{M,Symbol}`: A tuple of required locations in the project.
- `varied::NTuple{N,Symbol}`: A tuple of varied locations in the project.
"""
struct ProjectLocations{L,M,N}
    all::NTuple{L,Symbol}
    required::NTuple{M,Symbol}
    varied::NTuple{N,Symbol}

    function ProjectLocations(d::Dict{Symbol,Any})
        all_locations = (location for location in keys(d)) |> collect |> sort |> Tuple
        required = (location for (location, location_dict) in pairs(d) if location_dict["required"]) |> collect |> sort |> Tuple
        varied_locations = (location for (location, location_dict) in pairs(d) if any(location_dict["varied"])) |> collect |> sort |> Tuple
        return new{length(all_locations),length(required),length(varied_locations)}(all_locations, required, varied_locations)
    end

    ProjectLocations() = ProjectLocations(pcmm_globals.inputs_dict)
end

"""
    sanitizePathElement(path_elements::String)

Disallow certain path elements to prevent security issues.
"""
function sanitizePathElement(path_element::String)
    #! Disallow `..` to prevent directory traversal
    if path_element == ".."
        throw(ArgumentError("Path element '..' is not allowed"))
    end

    #! Disallow absolute paths
    if isabspath(path_element)
        throw(ArgumentError("Absolute paths are not allowed"))
    end

    #! Disallow special characters or sequences (e.g., `~`, `*`, etc.)
    if contains(path_element, r"[~*?<>|:]")
        throw(ArgumentError("Path element contains invalid characters"))
    end
    return path_element
end

"""
    parseProjectInputsConfigurationFile()

Parse the `inputs.toml` file in the data directory and create a global [`ProjectLocations`](@ref) object.
"""
function parseProjectInputsConfigurationFile()
    inputs_dict_temp = Dict{String,Any}()
    try
        inputs_dict_temp = pathToInputsConfig() |> TOML.parsefile
    catch e
        println("Error parsing project configuration file: ", e)
        return false
    end
    for (location, location_dict) in pairs(inputs_dict_temp)
        @assert haskey(location_dict, "required") "inputs.toml: $(location): required must be defined."
        @assert haskey(location_dict, "varied") "inputs.toml: $(location): varied must be defined."
        if !("path_from_inputs" in keys(location_dict))
            location_dict["path_from_inputs"] = locationFolder(location)
        else
            location_dict["path_from_inputs"] = location_dict["path_from_inputs"] .|> sanitizePathElement |> joinpath
        end
        if !("basename" in keys(location_dict))
            @assert location_dict["varied"] isa Bool && (!location_dict["varied"]) "inputs.toml: $(location): basename must be defined if varied is true."
            location_dict["basename"] = missing
        elseif location_dict["varied"] isa Vector
            @assert location_dict["basename"] isa Vector && length(location_dict["varied"]) == length(location_dict["basename"]) "inputs.toml: $(location): varied must be a Bool or a Vector of the same length as basename."
        end
    end
    pcmm_globals.inputs_dict = [Symbol(location) => location_dict for (location, location_dict) in pairs(inputs_dict_temp)] |> Dict{Symbol,Any}
    pcmm_globals.project_locations = ProjectLocations()
    createSimpleInputFoldersFunction()
    return true
end

"""
    locationIDName(location)

Return the name of the ID column for the location (as either a String or Symbol).

# Examples
```jldoctest
julia> PhysiCellModelManager.locationIDName(:config)
"config_id"
```
"""
locationIDName(location::Union{String,Symbol}) = tableIDName(String(location); strip_s=false)

"""
    locationVariationIDName(location)

Return the name of the variation ID column for the location (as either a String or Symbol).

# Examples
```jldoctest
julia> PhysiCellModelManager.locationVariationIDName(:config)
"config_variation_id"
```
"""
locationVariationIDName(location::Union{String,Symbol}) = "$(location)_variation_id"

"""
    locationIDNames()

Return the names of the ID columns for all locations.
"""
locationIDNames() = (locationIDName(loc) for loc in projectLocations().all)

"""
    locationVariationIDNames()

Return the names of the variation ID columns for all varied locations.
"""
locationVariationIDNames() = (locationVariationIDName(loc) for loc in projectLocations().varied)

"""
    locationTableName(location)

Return the name of the table for the location (as either a String or Symbol).
This table stores the folder names and their IDs for the location.

# Examples
```jldoctest
julia> PhysiCellModelManager.locationTableName(:config)
"configs"
```
"""
locationTableName(location::Union{String,Symbol}) = "$(location)s"

"""
    locationFolder(location::Union{String,Symbol})

Return the name of the folder for the location (as either a String or Symbol).
This is the folder where the directories with the input files for the location are stored.
"""
locationFolder(location::Union{String,Symbol}) = locationTableName(location)

"""
    locationVariationsTableName(location)

Return the name of the variations table for the location (as either a String or Symbol).
This table stores the variations of the folder it is located in.
"""
locationVariationsTableName(location::Union{String,Symbol}) = "$(location)_variations"

"""
    locationVariationsFolder(location)

Return the name of the variations folder for the location (as either a String or Symbol).
"""
locationVariationsFolder(location::Union{String,Symbol}) = locationVariationsTableName(location)

"""
    locationVariationsDBName(location::Union{String,Symbol})

Return the name of the variations database for the location (as either a String or Symbol).
"""
locationVariationsDBName(location::Union{String,Symbol}) = "$(locationVariationsTableName(location)).db"

"""
    locationPath(location::Symbol, folder=missing)

Return the path to the location folder in the `inputs` directory.

If `folder` is not specified, the path to the location folder is returned.
"""
function locationPath(location::Symbol, folder=missing)
    location_dict = inputsDict()[Symbol(location)]
    path_to_locations = joinpath(dataDir(), "inputs", location_dict["path_from_inputs"])
    return ismissing(folder) ? path_to_locations : joinpath(path_to_locations, folder)
end

"""
    locationPath(input_folder::InputFolder)

Return the path to the location folder in the `inputs` directory for the [`InputFolder`](@ref) object.
"""
function locationPath(input_folder::InputFolder)
    return locationPath(input_folder.location, input_folder.folder)
end

"""
    locationPath(location::Symbol, S::AbstractSampling)

Return the path to the location folder in the `inputs` directory for the [`AbstractSampling`](@ref) object.
"""
function locationPath(location::Symbol, S::AbstractSampling)
    return locationPath(location, S.inputs[location].folder)
end

"""
    folderIsVaried(location::Symbol, folder::String)

Return `true` if the location folder allows for varying the input files, `false` otherwise.
"""
function folderIsVaried(location::Symbol, folder::String)
    location_dict = inputsDict()[location]
    varieds = location_dict["varied"]
    if !any(varieds)
        return false #! if none of the basenames are declared to be varied, then the folder is not varied
    end
    basenames = location_dict["basename"]
    basenames = basenames isa Vector ? basenames : [basenames]
    @assert varieds isa Bool || length(varieds) == length(basenames) "varied must be a Bool or a Vector of the same length as basename"
    varieds = varieds isa Vector ? varieds : fill(varieds, length(basenames))

    #! look for the first basename in the folder. if that one is varied, then this is a potential target for varying
    path_to_folder = locationPath(location, folder)
    for (basename, varied) in zip(basenames, varieds)
        path_to_file = joinpath(path_to_folder, basename)
        if isfile(path_to_file)
            return varied
        end
    end
    throw(ErrorException("No basename files found in folder $(path_to_folder). Must be one of $(basenames)"))
end

"""
    pathToInputsConfig()

Return the path to the `inputs.toml` file in the `inputs` directory.
"""
pathToInputsConfig() = joinpath(dataDir(), "inputs", "inputs.toml")

"""
    createInputsTOMLTemplate(path_to_toml::String)

Create a template TOML file for the inputs configuration at the specified path.

This is something users should not be changing.
It is something in the codebase to hopefully facilitate extending this framework to other ABM frameworks.
"""
function createInputsTOMLTemplate(path_to_toml::String)
    s = """
    [config]
    required = true
    varied = true
    basename = "PhysiCell_settings.xml"

    [custom_code]
    required = true
    varied = false

    [rulesets_collection]
    required = false
    varied = true
    basename = ["base_rulesets.csv", "base_rulesets.xml"]

    [intracellular]
    required = false
    varied = true
    basename = "intracellular.xml"

    [ic_cell]
    path_from_inputs = ["ics", "cells"]
    required = false
    varied = [false, true]
    basename = ["cells.csv", "cells.xml"]

    [ic_substrate]
    path_from_inputs = ["ics", "substrates"]
    required = false
    varied = false
    basename = "substrates.csv"

    [ic_ecm]
    path_from_inputs = ["ics", "ecms"]
    required = false
    varied = [false, true]
    basename = ["ecm.csv", "ecm.xml"]

    [ic_dc]
    path_from_inputs = ["ics", "dcs"]
    required = false
    varied = false
    basename = "dcs.csv"
    """
    open(path_to_toml, "w") do f
        write(f, s)
    end
    return
end
