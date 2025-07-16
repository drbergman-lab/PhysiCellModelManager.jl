using LightXML

export importProject

"""
    ImportSource

A struct to hold the information about a source file or folder to be imported into the pcvct structure.

Used internally in the [`importProject`](@ref) function to manage the import of files and folders from a user project into the pcvct structure.

# Fields
- `src_key::Symbol`: The key in the source dictionary.
- `input_folder_key::Symbol`: The key in the destination dictionary.
- `path_from_project::AbstractString`: The path to the source file or folder relative to the project.
- `pcvct_name::AbstractString`: The name of the file or folder in the pcvct structure.
- `type::AbstractString`: The type of the source (e.g., file or folder).
- `required::Bool`: Indicates if the source is required for the project.
- `found::Bool`: Indicates if the source was found during import.
"""
mutable struct ImportSource
    src_key::Symbol
    input_folder_key::Symbol
    path_from_project::AbstractString
    pcvct_name::AbstractString
    type::AbstractString
    required::Bool
    found::Bool

    function ImportSource(src::Dict, key::AbstractString, path_from_project_base::AbstractString, default::String, type::AbstractString, required::Bool; input_folder_key::Symbol=Symbol(key), pcvct_name::String=default)
        is_key = haskey(src, key)
        path_from_project = joinpath(path_from_project_base, is_key ? src[key] : default)
        required |= is_key
        found = false
        return new(Symbol(key), input_folder_key, path_from_project, pcvct_name, type, required, found)
    end
end


"""
    ImportSources

A struct to hold the information about the sources to be imported into the pcvct structure.

Used internally in the [`importProject`](@ref) function to manage the import of files and folders from a user project into the pcvct structure.

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
    prepareRulesetsCollectionImport(src::Dict, path_to_project::AbstractString)

Prepare the rulesets collection import source.
"""
function prepareRulesetsCollectionImport(src::Dict, path_to_project::AbstractString)
    rules_ext = ".csv" #! default to csv
    required = true #! default to requiring rules (just for fewer lines below)
    if haskey(src, "rulesets_collection")
        rules_ext = splitext(src["rulesets_collection"])[2]
    elseif isfile(joinpath(path_to_project, "config", "cell_rules.csv"))
        rules_ext = ".csv"
    elseif isfile(joinpath(path_to_project, "config", "cell_rules.xml"))
        rules_ext = ".xml"
    else
        required = false
    end
    return ImportSource(src, "rules", "config", "cell_rules$(rules_ext)", "file", required; pcvct_name="base_rulesets$(rules_ext)")
end

"""
    prepareIntracellularImport(src::Dict, config::ImportSource, path_to_project::AbstractString)

Prepare the intracellular import source.
"""
function prepareIntracellularImport(src::Dict, config::ImportSource, path_to_project::AbstractString)
    if haskey(src, "intracellular") || isfile(joinpath(path_to_project, "config", "intracellular.xml"))
        return ImportSource(src, "intracellular", "config", "intracellular.xml", "file", true)
    end
    #! now attempt to read the config file and assemble the intracellular file
    path_to_xml = joinpath(path_to_project, config.path_from_project)
    if !isfile(path_to_xml) #! if the config file is not found, then we cannot proceed with grabbing the intracellular data, just return the default
        return ImportSource(src, "intracellular", "config", "intracellular.xml", "file", false)
    end
    xml_doc = parse_file(path_to_xml)
    cell_definitions_element = retrieveElement(xml_doc, ["cell_definitions"])
    cell_type_to_components_dict = Dict{String,PhysiCellComponent}()
    for cell_definition_element in child_elements(cell_definitions_element)
        @assert name(cell_definition_element) == "cell_definition" "The child elements of <cell_definitions> should all be <cell_definition> elements."
        cell_type = attribute(cell_definition_element, "name")
        phenotype_element = find_element(cell_definition_element, "phenotype")
        intracellular_element = find_element(phenotype_element, "intracellular")
        if isnothing(intracellular_element)
            continue
        end
        type = attribute(intracellular_element, "type")
        @assert type ∈ ["roadrunner", "dfba"] "pcvct does not yet support intracellular type $type. It only supports roadrunner and dfba."
        path_to_file = find_element(intracellular_element, "sbml_filename") |> content
        temp_component = PhysiCellComponent(type, basename(path_to_file))
        #! now we have to rely on the path to the file is correct relative to the parent directory of the config file (that should usually be the case)
        path_to_src = joinpath(path_to_project, path_to_file)
        path_to_dest = createComponentDestFilename(path_to_src, temp_component)
        component = PhysiCellComponent(type, basename(path_to_dest))
        if !isfile(path_to_dest)
            cp(path_to_src, path_to_dest)
        end

        cell_type_to_components_dict[cell_type] = component
    end

    if isempty(cell_type_to_components_dict)
        return ImportSource(src, "intracellular", "config", "intracellular.xml", "file", false)
    end

    intracellular_folder = assembleIntracellular!(cell_type_to_components_dict; name="temp_assembled_from_$(splitpath(path_to_project)[end])", skip_db_insert=true)
    mv(joinpath(locationPath(:intracellular, intracellular_folder), "intracellular.xml"), joinpath(path_to_project, "config", "assembled_intracellular_for_import.xml"); force=true)
    rm(locationPath(:intracellular, intracellular_folder); force=true, recursive=true)

    free(xml_doc)
    return ImportSource(src, "intracellular", "config", "assembled_intracellular_for_import.xml", "file", true; pcvct_name="intracellular.xml")
end

"""
    createComponentDestFilename(src_lines::Vector{String}, component::PhysiCellComponent)

Create a file name for the component file to be copied to.
If a file exists with the same name and content, it will not be copied again.
If a file exists with the same name but different content, a new file name will be created by appending a number to the base name.
"""
function createComponentDestFilename(path_to_file::String, component::PhysiCellComponent)
    src_lines = readlines(path_to_file)
    base_path = joinpath(dataDir(), "components", pathFromComponents(component))
    folder = dirname(base_path)
    mkpath(folder)
    base_filename, file_ext = basename(base_path) |> splitext
    n = 0
    path_to_dest = joinpath(folder, base_filename * file_ext)
    while isfile(path_to_dest)
        if src_lines == readlines(path_to_dest)
            return path_to_dest
        end
        n += 1
        path_to_dest = joinpath(folder, base_filename * "_$(n)" * file_ext)
    end
    return path_to_dest
end

"""
    ImportDestFolder

A struct to hold the information about a destination folder to be created in the pcvct structure.

Used internally in the [`importProject`](@ref) function to manage the creation of folders in the pcvct structure.

# Fields
- `path_from_inputs::AbstractString`: The path to the destination folder relative to the inputs folder.
- `created::Bool`: Indicates if the folder was created during the import process.
- `description::AbstractString`: A description of the folder.
"""
mutable struct ImportDestFolder
    path_from_inputs::AbstractString
    created::Bool
    description::AbstractString
end

"""
    ImportDestFolders

A struct to hold the information about the destination folders to be created in the pcvct structure.

Used internally in the [`importProject`](@ref) function to manage the creation of folders in the pcvct structure.

# Fields
- `config::ImportDestFolder`: The config folder to be created.
- `custom_code::ImportDestFolder`: The custom code folder to be created.
- `rules::ImportDestFolder`: The rules folder to be created.
- `intracellular::ImportDestFolder`: The intracellular folder to be created.
- `ic_cell::ImportDestFolder`: The intracellular cell folder to be created.
- `ic_substrate::ImportDestFolder`: The intracellular substrate folder to be created.
- `ic_ecm::ImportDestFolder`: The intracellular ECM folder to be created.
- `ic_dc::ImportDestFolder`: The intracellular DC folder to be created.
"""
struct ImportDestFolders
    config::ImportDestFolder
    custom_code::ImportDestFolder
    rules::ImportDestFolder
    intracellular::ImportDestFolder
    ic_cell::ImportDestFolder
    ic_substrate::ImportDestFolder
    ic_ecm::ImportDestFolder
    ic_dc::ImportDestFolder

    function ImportDestFolders(path_to_project::AbstractString, dest::Dict)
        default_name = splitpath(path_to_project)[end]
        path_fn(k::String, p::String) = joinpath(p, haskey(dest, k) ? dest[k] : default_name)
        created = false
        description = "Imported from project at $(path_to_project)."
    
        #! required folders
        config = ImportDestFolder(path_fn("config", "configs"), created, description)
        custom_code = ImportDestFolder(path_fn("custom_code", "custom_codes"), created, description)
    
        #! optional folders
        rules = ImportDestFolder(path_fn("rules", "rulesets_collections"), created, description)
        intracellular = ImportDestFolder(path_fn("intracellular", "intracellulars"), created, description)
        ic_cell = ImportDestFolder(path_fn("ic_cell", joinpath("ics", "cells")), created, description)
        ic_substrate = ImportDestFolder(path_fn("ic_substrate", joinpath("ics", "substrates")), created, description)
        ic_ecm = ImportDestFolder(path_fn("ic_ecm", joinpath("ics", "ecms")), created, description)
        ic_dc = ImportDestFolder(path_fn("ic_dc", joinpath("ics", "dcs")), created, description)
        return new(config, custom_code, rules, intracellular, ic_cell, ic_substrate, ic_ecm, ic_dc)
    end
end


"""
    importProject(path_to_project::AbstractString[, src=Dict(), dest=Dict()])

Import a project from the structured in the format of PhysiCell sample projects and user projects into the pcvct structure.

# Arguments
- `path_to_project::AbstractString`: Path to the project to import. Relative paths are resolved from the current working directory where Julia was launched.
- `src::Dict`: Dictionary of the project sources to import. If absent, tries to use the default names.
The following keys are recognized: $(join(["`$fn`" for fn in fieldnames(ImportSources)], ", ", ", and ")).
- `dest::Dict`: Dictionary of the inputs folders to create in the pcvct structure. If absent, taken from the project name.
The following keys are recognized: $(join(["`$fn`" for fn in fieldnames(ImportDestFolders)], ", ", ", and ")).
"""
function importProject(path_to_project::AbstractString, src=Dict(), dest=Dict())
    project_sources = ImportSources(src, path_to_project)
    import_dest_folders = ImportDestFolders(path_to_project, dest)
    success = resolveProjectSources!(project_sources, path_to_project)
    if success
        success = createInputFolders!(import_dest_folders, project_sources)
        success = success && copyFilesToFolders(path_to_project, project_sources, import_dest_folders) #! only copy if successful so far
        success = success && adaptProject(import_dest_folders)
    end
    if success
        msg = """
        Imported project from $(path_to_project) into $(joinpath(dataDir(), "inputs")):
            - $(import_dest_folders.config.path_from_inputs)
            - $(import_dest_folders.custom_code.path_from_inputs)\
        """
        if import_dest_folders.rules.created
            msg *= "\n    - $(import_dest_folders.rules.path_from_inputs)"
        end
        if import_dest_folders.intracellular.created
            msg *= "\n    - $(import_dest_folders.intracellular.path_from_inputs)"
        end
        ics_started = false
        for ic in ["cell", "substrate", "ecm", "dc"]
            import_dest_folder = getfield(import_dest_folders, Symbol("ic_$(ic)"))::ImportDestFolder
            if import_dest_folder.created
                if !ics_started
                    msg *= "\n    - ICs:"
                    ics_started = true
                end
                msg *= "\n      - $(splitpath(import_dest_folder.path_from_inputs)[2:end] |> joinpath)"
            end
        end
        println(msg)
        println("Re-initializing the database to include these new entries...")
        reinitializeDatabase()
    else
        msg = """
        Failed to import user_project from $(path_to_project) into $(joinpath(dataDir(), "inputs")).
        See the error messages above for more information.
        Cleaning up what was created in $(joinpath(dataDir(), "inputs")).
        """
        println(msg)
        path_to_inputs = joinpath(dataDir(), "inputs")
        for fieldname in fieldnames(ImportDestFolders)
            import_dest_folder = getfield(import_dest_folders, fieldname)
            if import_dest_folder.created
                path_to_folder = joinpath(path_to_inputs, import_dest_folder.path_from_inputs)
                rm(path_to_folder; force=true, recursive=true)
            end
        end
    end
    return success
end

"""
    resolveProjectSources!(project_sources::ImportSources, path_to_project::AbstractString)

Resolve the project sources by checking if they exist in the project directory.
"""
function resolveProjectSources!(project_sources::ImportSources, path_to_project::AbstractString)
    success = true
    for fieldname in fieldnames(ImportSources)
        project_source = getfield(project_sources, fieldname)::ImportSource
        success &= resolveProjectSource!(project_source, path_to_project)
    end
    return success
end

"""
    resolveProjectSource!(project_source::ImportSource, path_to_project::AbstractString)

Resolve the project source by checking if it exists in the project directory.
"""
function resolveProjectSource!(project_source::ImportSource, path_to_project::AbstractString)
    exist_fn = project_source.type == "file" ? isfile : isdir
    project_source.found = exist_fn(joinpath(path_to_project, project_source.path_from_project))
    if project_source.found || !project_source.required
        return true
    end

    msg = """
    Source $(project_source.type) $(project_source.path_from_project) does not exist in $(path_to_project).
    Update the src dictionary to include the correct $(project_source.type) name.
    For example: `src=Dict("$(project_source.src_key)"=>"$(splitpath(project_source.path_from_project)[end])")`.
    Aborting import.
    """
    println(msg)
    return false
end

"""
    createInputFolders!(import_dest_folders::ImportDestFolders, project_sources::ImportSources)

Create input folders based on the provided project sources and destination folders.
"""
function createInputFolders!(import_dest_folders::ImportDestFolders, project_sources::ImportSources)
    #! required folders
    success = createInputFolder!(import_dest_folders.config)
    success &= createInputFolder!(import_dest_folders.custom_code)

    #! optional folders
    for fieldname in fieldnames(ImportSources)
        if fieldname in [:config, :main, :makefile, :custom_modules]
            continue
        end
        project_source = getfield(project_sources, fieldname)
        if project_source.found
            success &= createInputFolder!(getfield(import_dest_folders, project_source.src_key)::ImportDestFolder)
        end
    end
    return success
end

"""
    createInputFolder!(import_dest_folder::ImportDestFolder)

Create an input folder based on the provided destination folder.
"""
function createInputFolder!(import_dest_folder::ImportDestFolder)
    path_to_inputs = joinpath(dataDir(), "inputs")
    path_from_inputs_vec = splitpath(import_dest_folder.path_from_inputs)
    path_from_inputs_to_collection = joinpath(path_from_inputs_vec[1:end-1]...)
    folder_base = path_from_inputs_vec[end]
    collection_contents = joinpath(path_to_inputs, path_from_inputs_to_collection) |> readdir
    filter!(x->startswith(x, folder_base), collection_contents)
    folder_name = folder_base
    n = 0
    while folder_name in collection_contents
        n += 1
        folder_name = "$(folder_base)_$(n)"
    end
    import_dest_folder.path_from_inputs = joinpath(path_from_inputs_to_collection, folder_name)
    path_to_folder = joinpath(path_to_inputs, import_dest_folder.path_from_inputs)
    mkpath(path_to_folder)
    path_to_metadata = joinpath(path_to_folder, "metadata.xml")
    writeDescriptionToMetadata(path_to_metadata, import_dest_folder.description)
    import_dest_folder.created = true
    return true
end

"""
    writeDescriptionToMetadata(path_to_metadata::AbstractString, description::AbstractString)

Write the description to the metadata file.
"""
function writeDescriptionToMetadata(path_to_metadata::AbstractString, description::AbstractString)
    xml_doc = XMLDocument()
    xml_root = create_root(xml_doc, "metadata")
    description_element = new_child(xml_root, "description")
    set_content(description_element, description)
    save_file(xml_doc, path_to_metadata)
    free(xml_doc)
    return
end

"""
    copyFilesToFolders(path_to_project::AbstractString, project_sources::ImportSources, import_dest_folders::ImportDestFolders)

Copy files from the project directory to the destination folders in the pcvct structure.
"""
function copyFilesToFolders(path_to_project::AbstractString, project_sources::ImportSources, import_dest_folders::ImportDestFolders)
    success = true
    for fieldname in fieldnames(ImportSources)
        project_source = getfield(project_sources, fieldname)::ImportSource
        if !project_source.found
            continue
        end
        src = joinpath(path_to_project, project_source.path_from_project)
        import_dest_folder = getfield(import_dest_folders, project_source.input_folder_key)
        dest = joinpath(dataDir(), "inputs", import_dest_folder.path_from_inputs, project_source.pcvct_name)
        @assert (dest |> (project_source.type == "file" ? isfile : isdir)) == false "In copying $(src) to $(dest), found a $(project_source.type) with the same name. This should be avoided by pcvct. Please open an Issue on GitHub and document your setup and steps."
        cp(src, dest)
    end
    return success
end

"""
    adaptProject(import_dest_folders::ImportDestFolders)

Adapt the project to be used in the pcvct structure.
"""
function adaptProject(import_dest_folders::ImportDestFolders)
    success = adaptConfig(import_dest_folders.config)
    success &= adaptCustomCode(import_dest_folders.custom_code)
    return success
end

"""
    adaptConfig(config::ImportDestFolder)

Adapt the config file to be used in the pcvct structure.
"""
function adaptConfig(::ImportDestFolder)
    return true #! nothing to do for now
end

"""
    adaptCustomCode(custom_code::ImportDestFolder)

Adapt the custom code to be used in the pcvct structure.
"""
function adaptCustomCode(custom_code::ImportDestFolder)
    success = adaptMain(custom_code.path_from_inputs)
    success &= adaptMakefile(custom_code.path_from_inputs)
    success &= adaptCustomModules(joinpath(custom_code.path_from_inputs, "custom_modules"))
    return success
end

"""
    adaptMain(path_from_inputs::AbstractString)

Adapt the main.cpp file to be used in the pcvct structure.
"""
function adaptMain(path_from_inputs::AbstractString)
    path_to_main = joinpath(dataDir(), "inputs", path_from_inputs, "main.cpp")
    lines = readlines(path_to_main)

    filter!(x->!contains(x, "copy_command"), lines) #! remove any lines carrying out the copy command, which could be a little risky if the user uses for something other than copying over the config file

    if any(x->contains(x, "argument_parser.parse"), lines)
        #! already adapted the main.cpp
        return true
    end

    idx1 = findfirst(x->contains(x, "// load and parse settings file(s)"), lines)
    if isnothing(idx1)
        idx1 = findfirst(x->contains(x, "bool XML_status = false;"), lines)
        if isnothing(idx1)
            msg = """
            Could not find the line to insert the settings file parsing code.
            Also, could not find an argument_parser line.
            Aborting the import process.
            """
            println(msg)
            return false
        end
    end
    idx_not_xml_status = findfirst(x->contains(x, "!XML_status"), lines)
    idx2 = idx_not_xml_status + findfirst(x -> contains(x, "}"), lines[idx_not_xml_status:end]) - 1

    deleteat!(lines, idx1:idx2)

    parsing_block = """
        // read arguments
        argument_parser.parse(argc, argv);

        // load and parse settings file(s)
        load_PhysiCell_config_file();
    """
    insert!(lines, idx1, parsing_block)

    open(path_to_main, "w") do f
        for line in lines
            println(f, line)
        end
    end
    return true
end

"""
    adaptMakefile(path_from_inputs::AbstractString)

Adapt the Makefile to be used in the pcvct structure.
"""
function adaptMakefile(path_from_inputs::AbstractString)
    path_to_makefile = joinpath(dataDir(), "inputs", path_from_inputs, "Makefile")
    file_str = read(path_to_makefile, String)
    file_str = replace(file_str, "PhysiCell_rules." => "PhysiCell_rules_extended.")
    open(path_to_makefile, "w") do io
        write(io, file_str)
    end
    return true #! nothing to do for now
end

"""
    adaptCustomModules(path_from_inputs::AbstractString)

Adapt the custom modules to be used in the pcvct structure.
"""
function adaptCustomModules(path_from_inputs::AbstractString)
    success = adaptCustomHeader(path_from_inputs)
    success &= adaptCustomCPP(path_from_inputs)
    return success
end

"""
    adaptCustomHeader(path_from_inputs::AbstractString)

Adapt the custom header to be used in the pcvct structure.
"""
function adaptCustomHeader(::AbstractString)
    return true #! nothing to do for now
end

"""
    adaptCustomCPP(path_from_inputs::AbstractString)

Adapt the custom cpp file to be used in the pcvct structure.
"""
function adaptCustomCPP(path_from_inputs::AbstractString)
    path_to_custom_cpp = joinpath(dataDir(), "inputs", path_from_inputs, "custom.cpp")
    lines = readlines(path_to_custom_cpp)
    idx = findfirst(x->contains(x, "load_cells_from_pugixml"), lines)

    if isnothing(idx)
        if !any(x->contains(x, "load_initial_cells"), lines)
            msg = """
            Could not find the line to insert the initial cells loading code.
            Aborting the import process.
            """
            println(msg)
            return false
        end
        return true
    end

    lines[idx] = "\tload_initial_cells();"

    idx = findfirst(x -> contains(x, "setup_cell_rules"), lines)
    if !isnothing(idx)
        lines[idx] = "\tsetup_behavior_rules();"
    end

    open(path_to_custom_cpp, "w") do f
        for line in lines
            println(f, line)
        end
    end
    return true
end