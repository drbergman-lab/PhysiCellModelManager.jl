using LightXML

export importProject

include("import_classes.jl")

"""
    importProject(path_to_project::AbstractString[; src=Dict(), dest=Dict()])

Import a project from the structured in the format of PhysiCell sample projects and user projects into the PhysiCellModelManager.jl structure.

This function will create new directories every time it is called, even if the project was already imported.
Copy the console output to your scripts to prepare inputs for running the imported project rather than repeatedly running this function.

# Arguments
- `path_to_project::AbstractString`: Path to the project to import. Relative paths are resolved from the current working directory where Julia was launched.

# Keyword Arguments
- `src::Dict`: Dictionary of the project sources to import. If absent, tries to use the default names.
The following keys are recognized: $(join(["`\"$fn\"`" for fn in fieldnames(ImportSources)], ", ", ", and ")).
- `dest::Dict`: Dictionary of the inputs folders to create in the PhysiCellModelManager.jl structure. If absent, taken from the project name.
Any valid project location can be used as a key. For example, `"config"`, `"custom_code"`, `"ic_cell"`, etc.
- `dest::AbstractString`: If a single string is provided, it is used as the name of the folder to create in the `inputs` folder for all locations.

For both `src` and `dest` (as `Dict`), the key `\"rules\"` is an alias for `\"rulesets_collection\"`.

# Returns
An `InputFolders` instance with the paths to the imported project files.
This can immediately be used to run simulations.
However, do not use this function in a script as it will repeatedly create new folders each call.

# Deprecated method
The following method is deprecated and will be removed in the future.
Note that the arguments are optional, positional arguments, not keyword arguments.
```julia
importProject(path_to_project::AbstractString, src::Dict, dest::Dict)
```
"""
function importProject(path_to_project::AbstractString; src=Dict(), dest=Dict())
    assertInitialized()
    project_sources = ImportSources(src, path_to_project)
    import_dest_folders = ImportDestFolders(path_to_project, dest)
    success = resolveProjectSources!(project_sources, path_to_project)
    if success
        success = createInputFolders!(import_dest_folders, project_sources)
        success = success && copyFilesToFolders(path_to_project, project_sources, import_dest_folders) #! only copy if successful so far
        success = success && adaptProject(import_dest_folders)
    end
    if success
        return processSuccessfulImport(path_to_project, import_dest_folders)
    else
        msg = """
        Failed to import user_project from $(path_to_project) into $(joinpath(dataDir(), "inputs")).
        See the error messages above for more information.
        Cleaning up what was created in $(joinpath(dataDir(), "inputs")).
        """
        println(msg)
        path_to_inputs = joinpath(dataDir(), "inputs")
        for loc in projectLocations().all
            import_dest_folder = import_dest_folders[loc]
            if import_dest_folder.created
                path_to_folder = joinpath(path_to_inputs, import_dest_folder.path_from_inputs)
                rm(path_to_folder; force=true, recursive=true)
            end
        end
        return
    end
end

function importProject(path_to_project::AbstractString, src, dest=Dict())
    Base.depwarn("`importProject` with more than one positional argument is deprecated. Use the method `importProject(path_to_project; src=Dict(), dest=Dict())` instead.", :importProject; force=true)
    return importProject(path_to_project; src=src, dest=dest)
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
    return ImportSource(src, "rulesets_collection", "config", "cell_rules$(rules_ext)", "file", required; pcmm_name="base_rulesets$(rules_ext)")
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
        @assert type ∈ ["roadrunner"] "PhysiCellModelManager.jl does not yet support intracellular type $type. It only supports roadrunner."
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
    return ImportSource(src, "intracellular", "config", "assembled_intracellular_for_import.xml", "file", true; pcmm_name="intracellular.xml", copy_or_move=_move_)
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
    success = true
    for loc in projectLocations().all
        import_dest_folder = import_dest_folders[loc]
        if loc in projectLocations().required || getfield(project_sources, loc).found
            success &= createInputFolder!(import_dest_folder)
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
    folder_name = folder_base
    path_base = joinpath(path_to_inputs, path_from_inputs_to_collection)
    n = 0
    while isdir(joinpath(path_base, folder_name))
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

Copy files from the project directory to the destination folders in the PhysiCellModelManager.jl structure.
"""
function copyFilesToFolders(path_to_project::AbstractString, project_sources::ImportSources, import_dest_folders::ImportDestFolders)
    success = true
    for fieldname in fieldnames(ImportSources)
        project_source = getfield(project_sources, fieldname)::ImportSource
        if !project_source.found
            continue
        end
        src = joinpath(path_to_project, project_source.path_from_project)
        import_dest_folder = import_dest_folders[project_source.input_folder_key]
        dest = joinpath(dataDir(), "inputs", import_dest_folder.path_from_inputs, project_source.pcmm_name)
        @assert (dest |> (project_source.type == "file" ? isfile : isdir)) == false "In copying $(src) to $(dest), found a $(project_source.type) with the same name. This should be avoided by PhysiCellModelManager. Please open an Issue on GitHub and document your setup and steps."
        project_source.copy_or_move == _copy_ ? cp(src, dest) : mv(src, dest)
    end
    return success
end

"""
    adaptProject(import_dest_folders::ImportDestFolders)

Adapt the project to be used in the PhysiCellModelManager.jl structure.
"""
function adaptProject(import_dest_folders::ImportDestFolders)
    success = adaptConfig(import_dest_folders[:config])
    success &= adaptCustomCode(import_dest_folders[:custom_code])
    return success
end

"""
    adaptConfig(config::ImportDestFolder)

Adapt the config file to be used in the PhysiCellModelManager.jl structure.
"""
function adaptConfig(::ImportDestFolder)
    return true #! nothing to do for now
end

"""
    adaptCustomCode(custom_code::ImportDestFolder)

Adapt the custom code to be used in the PhysiCellModelManager.jl structure.
"""
function adaptCustomCode(custom_code::ImportDestFolder)
    success = adaptMain(custom_code.path_from_inputs)
    success &= adaptMakefile(custom_code.path_from_inputs)
    success &= adaptCustomModules(joinpath(custom_code.path_from_inputs, "custom_modules"))
    return success
end

"""
    adaptMain(path_from_inputs::AbstractString)

Adapt the main.cpp file to be used in the PhysiCellModelManager.jl structure.
"""
function adaptMain(path_from_inputs::AbstractString)
    path_to_main = joinpath(dataDir(), "inputs", path_from_inputs, "main.cpp")
    lines = readlines(path_to_main)

    filter!(!contains("copy_command"), lines) #! remove any lines carrying out the copy command, which could be a little risky if the user uses for something other than copying over the config file

    if any(contains("argument_parser.parse"), lines)
        #! already adapted the main.cpp
        return true
    end

    idx1 = findfirst(contains("// load and parse settings file(s)"), lines)
    if isnothing(idx1)
        idx1 = findfirst(contains("bool XML_status = false;"), lines)
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
    idx_not_xml_status = findfirst(contains("!XML_status"), lines)
    idx2 = idx_not_xml_status + findfirst(contains("}"), lines[idx_not_xml_status:end]) - 1

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

Adapt the Makefile to be used in the PhysiCellModelManager.jl structure.
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

Adapt the custom modules to be used in the PhysiCellModelManager.jl structure.
"""
function adaptCustomModules(path_from_inputs::AbstractString)
    success = adaptCustomHeader(path_from_inputs)
    success &= adaptCustomCPP(path_from_inputs)
    return success
end

"""
    adaptCustomHeader(path_from_inputs::AbstractString)

Adapt the custom header to be used in the PhysiCellModelManager.jl structure.
"""
function adaptCustomHeader(::AbstractString)
    return true #! nothing to do for now
end

"""
    adaptCustomCPP(path_from_inputs::AbstractString)

Adapt the custom cpp file to be used in the PhysiCellModelManager.jl structure.
"""
function adaptCustomCPP(path_from_inputs::AbstractString)
    path_to_custom_cpp = joinpath(dataDir(), "inputs", path_from_inputs, "custom.cpp")
    lines = readlines(path_to_custom_cpp)
    idx = findfirst(contains("load_cells_from_pugixml"), lines)

    if isnothing(idx)
        if !any(contains("load_initial_cells"), lines)
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

    idx = findfirst(contains("setup_cell_rules"), lines)
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

"""
    processSuccessfulImport(path_to_project::AbstractString, import_dest_folders::ImportDestFolders)

Process the successful import by printing the new folders created, re-initializing the database, printing Julia code to prepare inputs, and returning the `InputFolders` instance.

[`importProject`](@ref) will create new input folders each time it is called, even if calling a project that was already imported.
So, the printed Julia code should be used to add to scripts that prepare inputs for running the imported project.
"""
function processSuccessfulImport(path_to_project::AbstractString, import_dest_folders::ImportDestFolders)
    printNewFolders!(path_to_project, import_dest_folders)
    println("Re-initializing the database to include these new entries...\n")
    reinitializeDatabase()

    kwargs = Dict{Symbol, String}()
    for (loc, folder) in pairs(import_dest_folders.import_dest_folders)
        kwargs[loc] = folder.created ? splitpath(folder.path_from_inputs)[end] : ""
    end

    unique_folder_names = kwargs |> values |> unique
    naming_str = ""
    for unique_folder_name in unique_folder_names
        if unique_folder_name == ""
            continue
        end
        these_locs = filter(loc -> kwargs[loc] == unique_folder_name, keys(kwargs))
        s = join(these_locs, " = ")
        s *= " = " * "\"$unique_folder_name\""
        naming_str *= s * "\n"
    end

    indent = 4
    inputs_str = "inputs = InputFolders(\n" * " "^(indent)
    inputs_str *= join([String(loc) for loc in projectLocations().required], ",\n" * " "^indent)

    kwargs_str = join([String(loc) * " = " * String(loc) for loc in setdiff(projectLocations().all, projectLocations().required) if kwargs[loc] != ""], ",\n" * " "^indent)

    if !isempty(kwargs_str)
        inputs_str *= ";\n" * " "^(indent)
        inputs_str *= kwargs_str
    end
    inputs_str *= "\n)"

    first_line = "Copy the following into a Julia script to prepare the inputs for running this imported project:"
    max_len = mapreduce(x -> split(x, "\n"), vcat, [naming_str, first_line, inputs_str]) .|> length |> maximum
    padding = 4

    println("#"^(max_len + padding))
    println("$first_line\n" * "-"^length(first_line))
    println(naming_str)
    println(inputs_str)
    println("#"^(max_len + padding))
    println()

    return InputFolders(; kwargs...)
end

"""
    printNewFolders!(path_to_project::AbstractString, import_dest_folders::ImportDestFolders)

Internal function to print the new folders created during the import process.
"""
function printNewFolders!(path_to_project::AbstractString, import_dest_folders::ImportDestFolders)
    print("Imported project from $(path_to_project) into $(joinpath(dataDir(), "inputs")):")
    paths_created = [splitpath(folder.path_from_inputs) for folder in import_dest_folders.import_dest_folders if folder.created]

    while !isempty(paths_created)
        printTogether!(paths_created)
    end
    println("\n")
end

"""
    printTogether!(paths_created::Vector{Vector{String}}, indent::Int=1)

Internal helper function to print the paths created during the import process in a structured way.
"""
function printTogether!(paths_created::Vector{Vector{String}}, indent::Int=1)
    path = popfirst!(paths_created)

    paths_with_shared_first = filter(p -> p[1] == path[1], paths_created)

    if isempty(paths_with_shared_first)
        print("\n" * " "^(4 * indent) * "- $(joinpath(path...))")
        return
    end

    print("\n" * " "^(4 * indent) * "- $(path[1])/")

    next_level_paths = [path, paths_with_shared_first...] .|> copy
    popfirst!.(next_level_paths) #! remove the common folder from each path

    while !isempty(next_level_paths)
        printTogether!(next_level_paths, indent + 1)
    end

    filter!(p -> p[1] != path[1], paths_created)
end
