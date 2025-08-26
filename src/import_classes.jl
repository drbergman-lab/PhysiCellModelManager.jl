"""
    CopyOrMove

An enum to indicate whether a source file or folder should be copied or moved during the import process.
Possible values are `_copy_` and `_move_`.
"""
@enum CopyOrMove _copy_ _move_

"""
    ImportSource

A struct to hold the information about a source file or folder to be imported into the PhysiCellModelManager.jl structure.

Used internally in the [`importProject`](@ref) function to manage the import of files and folders from a user project into the PhysiCellModelManager.jl structure.

# Fields
- `src_key::Symbol`: The key in the source dictionary.
- `input_folder_key::Symbol`: The key in the destination dictionary.
- `path_from_project::AbstractString`: The path to the source file or folder relative to the project.
- `pcmm_name::AbstractString`: The name of the file or folder in the PhysiCellModelManager.jl structure.
- `type::AbstractString`: The type of the source (e.g., file or folder).
- `required::Bool`: Indicates if the source is required for the project.
- `found::Bool`: Indicates if the source was found during import.
- `copy_or_move::CopyOrMove`: Indicates if the source should be copied or moved to the destination folder. See [`CopyOrMove`](@ref).
"""
mutable struct ImportSource
    src_key::Symbol
    input_folder_key::Symbol
    path_from_project::AbstractString
    pcmm_name::AbstractString
    type::AbstractString
    required::Bool
    found::Bool
    copy_or_move::CopyOrMove

    function ImportSource(src::Dict, key::AbstractString, path_from_project_base::AbstractString, default::String, type::AbstractString, required::Bool; input_folder_key::Symbol=Symbol(key), pcmm_name::String=default, copy_or_move::CopyOrMove=_copy_)
        is_key = haskey(src, key)
        path_from_project = joinpath(path_from_project_base, is_key ? src[key] : default)
        required |= is_key
        found = false
        return new(Symbol(key), input_folder_key, path_from_project, pcmm_name, type, required, found, copy_or_move)
    end
end

"""
    ImportSources

A struct to hold the information about the sources to be imported into the PhysiCellModelManager.jl structure.

Used internally in the [`importProject`](@ref) function to manage the import of files and folders from a user project into the PhysiCellModelManager.jl structure.

# Fields
- `config::ImportSource`: The config file to be imported.
- `main::ImportSource`: The main.cpp file to be imported.
- `makefile::ImportSource`: The Makefile to be imported.
- `custom_modules::ImportSource`: The custom modules folder to be imported.
- `rulesets_collection::ImportSource`: The rulesets collection to be imported.
- `intracellular::ImportSource`: The intracellular components to be imported.
- `ic_cell::ImportSource`: The cell definitions to be imported.
- `ic_substrate::ImportSource`: The substrate definitions to be imported.
- `ic_ecm::ImportSource`: The extracellular matrix definitions to be imported.
- `ic_dc::ImportSource`: The DC definitions to be imported.
"""
struct ImportSources
    config::ImportSource
    main::ImportSource
    makefile::ImportSource
    custom_modules::ImportSource
    rulesets_collection::ImportSource
    intracellular::ImportSource
    ic_cell::ImportSource
    ic_substrate::ImportSource
    ic_ecm::ImportSource
    ic_dc::ImportSource

    function ImportSources(src::Dict, path_to_project::AbstractString)
        if haskey(src, "rules")
            src["rulesets_collection"] = src["rules"]
        end

        required = true
        config = ImportSource(src, "config", "config", "PhysiCell_settings.xml", "file", required)
        main = ImportSource(src, "main", "", "main.cpp", "file", required; input_folder_key = :custom_code)
        makefile = ImportSource(src, "makefile", "", "Makefile", "file", required; input_folder_key = :custom_code)
        custom_modules = ImportSource(src, "custom_modules", "", "custom_modules", "folder", required; input_folder_key = :custom_code)

        required = false
        rules = prepareRulesetsCollectionImport(src, path_to_project)
        intracellular = prepareIntracellularImport(src, config, path_to_project) #! config here could contain the <intracellular> element which would inform this import
        ic_cell = ImportSource(src, "ic_cell", "config", "cells.csv", "file", required)
        ic_substrate = ImportSource(src, "ic_substrate", "config", "substrates.csv", "file", required)
        ic_ecm = ImportSource(src, "ic_ecm", "config", "ecm.csv", "file", required)
        ic_dc = ImportSource(src, "ic_dc", "config", "dcs.csv", "file", required)
        return new(config, main, makefile, custom_modules, rules, intracellular, ic_cell, ic_substrate, ic_ecm, ic_dc)
    end
end

"""
    ImportDestFolder

A struct to hold the information about a destination folder to be created in the PhysiCellModelManager.jl structure.

Used internally in the [`importProject`](@ref) function to manage the creation of folders in the PhysiCellModelManager.jl structure.

# Fields
- `path_from_inputs::AbstractString`: The path to the destination folder relative to the inputs folder.
- `created::Bool`: Indicates if the folder was created during the import process.
- `description::AbstractString`: A description of the folder.
"""
mutable struct ImportDestFolder
    path_from_inputs::AbstractString
    created::Bool
    description::AbstractString

    function ImportDestFolder(location::Symbol, folder::AbstractString, description::AbstractString)
        location_dict = inputsDict()[location]
        path_from_inputs = joinpath(location_dict["path_from_inputs"], folder)
        created = false
        return new(path_from_inputs, created, description)
    end
end

"""
    ImportDestFolders

A struct to hold the information about the destination folders to be created in the PhysiCellModelManager.jl structure.

Used internally in the [`importProject`](@ref) function to manage the creation of folders in the PhysiCellModelManager.jl structure.

# Fields
- `import_dest_folders::NamedTuple`: A named tuple containing the destination folders. The keys are the project locations and the values are [`ImportDestFolder`](@ref) instances.
"""
struct ImportDestFolders
    import_dest_folders::NamedTuple

    function ImportDestFolders(path_to_project::AbstractString, dest::Union{AbstractString,Dict})
        default_name = splitpath(path_to_project)[end]

        if dest isa Dict && haskey(dest, "rules")
            dest["rulesets_collection"] = dest["rules"]
        end

        locs = projectLocations().all

        loc_name_pairs = dest isa AbstractString ?
                            [loc => dest for loc in locs] :
                            [loc => haskey(dest, String(loc)) ? dest[String(loc)] : default_name for loc in locs]

        description = "Imported from project at $(path_to_project)."

        loc_folder_pairs = [loc => ImportDestFolder(loc, name, description) for (loc, name) in loc_name_pairs]

        return new(NamedTuple(loc_folder_pairs))
    end
end

Base.getindex(import_dest_folders::ImportDestFolders, loc::Symbol)::ImportDestFolder = import_dest_folders.import_dest_folders[loc]
