using LightXML, PhysiCellXMLRules

export exportSimulation

"""
    exportSimulation(simulation_id::Integer[, export_folder::AbstractString])

Create a `user_project` folder from a simulation that can be loaded into PhysiCell.

Warning: not all features in drbergman/PhysiCell/latest/release are not supported in MathCancer/PhysiCell.

# Arguments
- `simulation_id::Integer`: the id of the simulation to export. Can also be a `Simulation` object.
- `export_folder::AbstractString`: the folder to export the simulation to. Default is the simulation output folder.

# Returns
- `export_folder::AbstractString`: the folder where the simulation was exported to
"""
function exportSimulation(simulation_id::Integer, export_folder::AbstractString="$(joinpath(trialFolder(Simulation, simulation_id), "UserProjectExport"))")
    simulation = Simulation(simulation_id)
    return exportSimulation(simulation, export_folder)
end

function exportSimulation(simulation::Simulation, export_folder::AbstractString="$(joinpath(trialFolder(simulation), "UserProjectExport"))")
    success, physicell_version = createExportFolder(simulation, export_folder)
    if success
        msg = """
        Exported simulation $(simulation.id) successfully to $(export_folder).
        Copy this folder into `PhysiCell/user_projects` for a PhysiCell folder with version $(physicell_version).
        Load it with
            make load PROJ=UserProjectExport # or however you renamed the folder
        Then run it with
            make && $(baseToExecutable("project")) # or however you renamed the executable
        """
        println(msg)
    else
        msg = """
        Exporting simulation $(simulation.id) failed.
        See the error messages above for more information.
        Cleaning up what was created in $(export_folder).
        """
        println(msg)
        rm(export_folder; force=true, recursive=true)
    end
    return export_folder
end

"""
    createExportFolder(simulation::Simulation, export_folder::AbstractString)

Create and populate the export folder for a simulation.
"""
function createExportFolder(simulation::Simulation, export_folder::AbstractString)
    export_config_folder = joinpath(export_folder, "config")
    mkpath(export_config_folder)

    query = constructSelectQuery("simulations", "WHERE simulation_id = $(simulation.id)")
    row = queryToDataFrame(query; is_row=true)

    #! config file
    path_to_xml = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(row.config_variation_id[1]).xml")
    cp(path_to_xml, joinpath(export_config_folder, "PhysiCell_settings.xml"))

    #! custom code
    path_to_custom_codes_folder = locationPath(:custom_code, simulation)
    for filename in ["main.cpp", "Makefile"]
        cp(joinpath(path_to_custom_codes_folder, filename), joinpath(export_folder, filename))
    end
    cp(joinpath(path_to_custom_codes_folder, "custom_modules"), joinpath(export_folder, "custom_modules"))

    #! rulesets
    if row.rulesets_collection_id[1] != -1
        path_to_xml = joinpath(locationPath(:rulesets_collection, simulation), "rulesets_collection_variations", "rulesets_collection_variation_$(row.rulesets_collection_variation_id[1]).xml")
        path_to_csv = joinpath(export_folder, "config", "cell_rules.csv")
        exportCSVRules(path_to_csv, path_to_xml)
    end

    #! intracellulars
    if row.intracellular_id[1] != -1
        exportIntracellular(simulation, export_folder)
    end

    #! ic cells
    if row.ic_cell_id[1] != -1
        path_to_ic_cells_folder = locationPath(:ic_cell, simulation)
        ic_cell_file_name = readdir(path_to_ic_cells_folder)
        filter!(x -> x in ["cells.csv", "cells.xml"], ic_cell_file_name)
        ic_cell_file_name = ic_cell_file_name[1]
        if endswith(ic_cell_file_name, ".xml")
            #! rel path from ic_cells_folder
            ic_cell_file_name = joinpath("ic_cell_variations", "ic_cell_variation_$(row.ic_cell_variation_id[1])_s$(simulation.id).csv")
        end
        cp(joinpath(path_to_ic_cells_folder, ic_cell_file_name), joinpath(export_folder, "config", "cells.csv"))
    end

    #! ic substrates
    if row.ic_substrate_id[1] != -1
        path_to_file = joinpath(locationPath(:ic_substrate, simulation), "substrates.csv")
        cp(path_to_file, joinpath(export_folder, "config", "substrates.csv"))
    end

    #! ic ecm
    if row.ic_ecm_id[1] != -1
        path_to_ic_ecm_folder = locationPath(:ic_ecm, simulation)
        ic_ecm_file_name = readdir(path_to_ic_ecm_folder)
        filter!(x -> x in ["ecm.csv", "ecm.xml"], ic_ecm_file_name)
        ic_ecm_file_name = ic_ecm_file_name[1]
        if endswith(ic_ecm_file_name, ".xml")
            #! rel path from ic_ecm_folder
            ic_ecm_file_name = joinpath("ic_ecm_variations", "ic_ecm_variation_$(row.ic_ecm_variation_id[1])_s$(simulation.id).csv")
        end
        cp(joinpath(path_to_ic_ecm_folder, ic_ecm_file_name), joinpath(export_folder, "config", "ecm.csv"))
    end

    #! ic dcs
    if row.ic_dc_id[1] != -1
        path_to_file = joinpath(locationPath(:ic_dc, simulation), "dcs.csv")
        cp(path_to_file, joinpath(export_folder, "config", "dcs.csv"))
    end

    #! get physicell version
    physicell_version_id = row.physicell_version_id[1]
    query = constructSelectQuery("physicell_versions", "WHERE physicell_version_id = $physicell_version_id")
    row = queryToDataFrame(query; is_row=true)
    physicell_version = row.tag[1]
    if ismissing(physicell_version)
        physicell_version = row.commit_hash[1]
    end
    physicell_version = split(physicell_version, "-")[1]
    return revertSimulationFolderToCurrentPhysiCell(export_folder, physicell_version), physicell_version
end

"""
    exportIntracellular(simulation::Simulation, export_folder::AbstractString)

Export the intracellular model for a simulation to the export folder.
"""
function exportIntracellular(simulation::Simulation, export_folder::AbstractString)
    path_to_intracellular = joinpath(locationPath(:intracellular, simulation), "intracellular.xml")
    xml_doc = parse_file(path_to_intracellular)
    intracellulars_element = retrieveElement(xml_doc, ["intracellulars"])
    intracellular_mapping = Dict{String,Tuple{String,String}}()
    for intracellular_element in child_elements(intracellulars_element)
        intracellular_id = attribute(intracellular_element, "ID")
        intracellular_type = attribute(intracellular_element, "type")
        new_root = child_elements(intracellular_element) |> first
        new_xml_doc = XMLDocument()
        set_root(new_xml_doc, new_root)
        path_end = joinpath("config", "intracellular_$(intracellular_type)_$(intracellular_id).xml")
        new_path = joinpath(export_folder, path_end)
        save_file(new_xml_doc, new_path)
        free(new_xml_doc)
        intracellular_mapping[intracellular_id] = (intracellular_type, path_end)
    end

    path_to_exported_config = joinpath(export_folder, "config", "PhysiCell_settings.xml")
    config_xml = parse_file(path_to_exported_config)

    cell_definitions_element = retrieveElement(xml_doc, ["cell_definitions"])
    for cell_definition_element in child_elements(cell_definitions_element)
        if name(cell_definition_element) != "cell_definition"
            continue
        end
        cell_type = attribute(cell_definition_element, "name")
        intracellular_ids_element = find_element(cell_definition_element, "intracellular_ids")
        ID_elements = get_elements_by_tagname(intracellular_ids_element, "ID")
        @assert length(ID_elements) <= 1 "Do not (yet?) support multiple intracellular models for a single cell type."
        intracellular_id = ID_elements |> first |> content
        config_cell_def_intracellular_element = retrieveElement(config_xml, ["cell_definitions", "cell_definition:name:$(cell_type)", "phenotype", "intracellular"])
        set_attribute(config_cell_def_intracellular_element, "type", intracellular_mapping[intracellular_id][1])

        #! get (or create) the sbml_filename element
        sbml_filename_element = makeXMLPath(config_cell_def_intracellular_element, "sbml_filename")
        set_content(sbml_filename_element, intracellular_mapping[intracellular_id][2])
    end

    save_file(config_xml, path_to_exported_config)
    free(config_xml)
    free(xml_doc)
    return
end


"""
    revertSimulationFolderToCurrentPhysiCell(export_folder::AbstractString, physicell_version::AbstractString)

Revert the simulation folder to the given PhysiCell version.
"""
function revertSimulationFolderToCurrentPhysiCell(export_folder::AbstractString, physicell_version::AbstractString)
    success = revertMain(export_folder, physicell_version)
    success &= revertMakefile(export_folder, physicell_version)
    success &= revertConfig(export_folder, physicell_version)
    success &= revertCustomModules(export_folder, physicell_version)
    return success
end

"""
    revertMain(export_folder::AbstractString, physicell_version::AbstractString)

Revert the main.cpp file in the export folder to the given PhysiCell version.
"""
function revertMain(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_main = joinpath(export_folder, "main.cpp")
    lines = readlines(path_to_main)
    idx = findfirst(x -> contains(x, "<getopt.h>"), lines)
    if !isnothing(idx)
        popat!(lines, idx)
    end

    idx1 = findfirst(x -> contains(x, "// read arguments"), lines)
    if isnothing(idx1)
        idx1 = findfirst(x -> contains(x, "argument_parser"), lines)
        if isnothing(idx1)
            msg = """
            Could not identify where the argument_parser ends in the main.cpp file.
            Aborting the export process.
            """
            println(msg)
            return false
        end
    end
    idx2 = findfirst(x -> contains(x, "// OpenMP setup"), lines)
    if isnothing(idx2)
        idx2 = findfirst(x -> contains(x, "omp_set_num_threads(") && contains(x, "PhysiCell_settings.omp_num_threads"), lines)
        if isnothing(idx2)
            msg = """
            Could not identify where the omp_set_num_threads is in the main.cpp file.
            Aborting the export process.
            """
            println(msg)
            return false
        end
    end
    deleteat!(lines, idx1:(idx2-1)) #! delete up to but not including the omp_set_num_threads line

    parsing_block = """
        // load and parse settings file(s)

        bool XML_status = false;
        char copy_command [1024];
        if( argc > 1 )
        {
            XML_status = load_PhysiCell_config_file( argv[1] );
            sprintf( copy_command , "cp %s %s" , argv[1] , PhysiCell_settings.folder.c_str() );
        }
        else
        {
            XML_status = load_PhysiCell_config_file( "./config/PhysiCell_settings.xml" );
            sprintf( copy_command , "cp ./config/PhysiCell_settings.xml %s" , PhysiCell_settings.folder.c_str() );
        }
        if( !XML_status )
        { exit(-1); }

        // copy config file to output directory
        system( copy_command );
    """
    lines = [lines[1:(idx1-1)]; parsing_block; lines[idx1:end]]

    open(path_to_main, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return true
end

"""
    revertMakefile(export_folder::AbstractString, physicell_version::AbstractString)

Revert the Makefile in the export folder to the given PhysiCell version.
"""
function revertMakefile(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_makefile = joinpath(export_folder, "Makefile")
    file_str = read(path_to_makefile, String)
    file_str = replace(file_str, "PhysiCell_rules_extended" => "PhysiCell_rules")
    open(path_to_makefile, "w") do io
        write(io, file_str)
    end
    return true #! nothing to do as of yet for the Makefile
end

"""
    revertConfig(export_folder::AbstractString, physicell_version::AbstractString)

Revert the config folder in the export folder to the given PhysiCell version.
"""
function revertConfig(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_config_folder = joinpath(export_folder, "config")
    path_to_config = joinpath(path_to_config_folder, "PhysiCell_settings.xml")
    xml_doc = parse_file(path_to_config)

    #! output folder
    folder_element = makeXMLPath(xml_doc, ["save", "folder"])
    set_content(folder_element, "output")

    #! ic substrate
    substrate_ic_element = makeXMLPath(xml_doc, ["microenvironment_setup", "options", "initial_condition"])
    using_substrate_ics = isfile(joinpath(path_to_config_folder, "substrates.csv"))
    set_attributes(substrate_ic_element; type="csv", enabled=string(using_substrate_ics))
    filename_element = makeXMLPath(substrate_ic_element, "filename")
    set_content(filename_element, joinpath(".", "config", "substrates.csv"))

    #! ic cells
    cell_ic_element = makeXMLPath(xml_doc, ["initial_conditions", "cell_positions"])
    using_cell_ics = isfile(joinpath(path_to_config_folder, "cells.csv"))
    set_attributes(cell_ic_element; type="csv", enabled=string(using_cell_ics))
    folder_element = makeXMLPath(cell_ic_element, "folder")
    set_content(folder_element, joinpath(".", "config"))
    filename_element = makeXMLPath(cell_ic_element, "filename")
    set_content(filename_element, "cells.csv")

    #! ic ecm
    using_ecm_ics = isfile(joinpath(path_to_config_folder, "ecm.csv"))
    if using_ecm_ics
        setECMSetupElement(xml_doc)
    end

    #! ic dcs
    dc_ic_element = makeXMLPath(xml_doc, ["microenvironment_setup", "options", "dirichlet_nodes"])
    using_dc_ics = isfile(joinpath(path_to_config_folder, "dcs.csv"))
    set_attributes(dc_ic_element; type="csv", enabled=string(using_dc_ics))
    filename_element = makeXMLPath(dc_ic_element, "filename")
    set_content(filename_element, joinpath("config", "dcs.csv"))

    #! rulesets
    rules_element = makeXMLPath(xml_doc, ["cell_rules", "rulesets", "ruleset"])
    using_rules = isfile(joinpath(path_to_config_folder, "cell_rules.csv"))
    set_attributes(rules_element; protocol="CBHG", version="3.0", format="csv", enabled=string(using_rules))
    folder_element = makeXMLPath(rules_element, "folder")
    set_content(folder_element, joinpath(".", "config"))
    filename_element = makeXMLPath(rules_element, "filename")
    set_content(filename_element, "cell_rules.csv")

    #! intracellulars
    #! handled in exportIntracellular

    save_file(xml_doc, path_to_config)
    free(xml_doc)
    return true
end

"""
    setECMSetupElement(xml_doc::XMLDocument)

Set up the ECM element in the XML document to support the ECM module.
"""
function setECMSetupElement(xml_doc::XMLDocument)
    ecm_setup_element = makeXMLPath(xml_doc, ["microenvironment_setup", "ecm_setup"])
    set_attributes(ecm_setup_element; enabled="true", format="csv")
    folder_element = makeXMLPath(ecm_setup_element, "folder")
    set_content(folder_element, joinpath(".", "config"))
    filename_element = makeXMLPath(ecm_setup_element, "filename")
    set_content(filename_element, "ecm.csv")
    return
end

"""
    revertCustomModules(export_folder::AbstractString, physicell_version::AbstractString)

Revert the custom modules in the export folder to the given PhysiCell version.
"""
function revertCustomModules(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_custom_modules = joinpath(export_folder, "custom_modules")
    success = revertCustomHeader(path_to_custom_modules, physicell_version)
    success &= revertCustomCPP(path_to_custom_modules, physicell_version)
    return success
end

"""
    revertCustomHeader(path_to_custom_modules::AbstractString, physicell_version::AbstractString)

Revert the custom header file in the export folder to the given PhysiCell version.
"""
function revertCustomHeader(::AbstractString, ::AbstractString)
    return true #! nothing to do as of yet for the custom header
end

"""
    revertCustomCPP(path_to_custom_modules::AbstractString, physicell_version::AbstractString)

Revert the custom cpp file in the export folder to the given PhysiCell version.
"""
function revertCustomCPP(path_to_custom_modules::AbstractString, ::AbstractString)
    path_to_custom_cpp = joinpath(path_to_custom_modules, "custom.cpp")
    lines = readlines(path_to_custom_cpp)
    idx = findfirst(x -> contains(x, "load_initial_cells();"), lines)

    lines[idx] = "    load_cells_from_pugixml();"

    idx = findfirst(x -> contains(x, "setup_behavior_rules()"), lines)
    if !isnothing(idx)
        lines[idx] = "    setup_cell_rules();"
    end

    open(path_to_custom_cpp, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return true
end