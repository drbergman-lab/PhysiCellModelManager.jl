using CSV, DataFrames

export runStudio

"""
    runStudio(simulation_id::Int; python_path::Union{Missing,String}=pcmm_globals.path_to_python, studio_path::Union{Missing,String}=pcmm_globals.path_to_studio)

Launch PhysiCell Studio for a given simulation.

Creates temporary config and rules files to avoid overwriting the original files in the output folder.
The intent of this function is to allow users to visualize the results of a simulation with Studio, rather than to modify the simulation itself.

The path to the python executable and the Studio folder must be set.
When calling `using PhysiCellModelManager`, shell environment variables `PCMM_PYTHON_PATH` and `PCMM_STUDIO_PATH` will be used to set the path to the python executable and the Studio folder, respectively.
**Note**: these should match how you would run PhysiCell Studio from the command line, e.g.: `export PCMM_PYTHON_PATH=python`.

If the paths are not set in the environment, they can be passed as the keyword arguments `python_path` and `studio_path` to this function.
In this case, the paths will be set as global variables for the duration of the Julia session and do not need to be passed again.
"""
function runStudio(simulation_id::Int; python_path::Union{Missing,String}=pcmm_globals.path_to_python, studio_path::Union{Missing,String}=pcmm_globals.path_to_studio)
    resolveStudioGlobals(python_path, studio_path)
    path_to_temp_xml, path_to_input_rules = setUpStudioInputs(simulation_id)
    out = executeStudio(path_to_temp_xml)
    cleanUpStudioInputs(path_to_temp_xml, path_to_input_rules)
    if out isa Exception
        throw(out)
    end
end

"""
    resolveStudioGlobals(python_path::Union{Missing,String}, studio_path::Union{Missing,String})

Set the global variables `path_to_python` and `path_to_studio` to the given paths.

They are required to not be `missing` so that the function `runStudio` works.
"""
function resolveStudioGlobals(python_path::Union{Missing,String}, studio_path::Union{Missing,String})
    if ismissing(python_path)
        throw(ArgumentError("Path to python not set. Please set the PCMM_PYTHON_PATH environment variable or pass the path as an argument."))
    else
        pcmm_globals.path_to_python = python_path
    end
    if ismissing(studio_path)
        throw(ArgumentError("Path to studio not set. Please set the PCMM_STUDIO_PATH environment variable or pass the path as an argument."))
    else
        pcmm_globals.path_to_studio = studio_path
    end
end

"""
    setUpStudioInputs(simulation_id::Int)

Set up the inputs for PhysiCell Studio.
Creates a temporary XML file and a temporary rules file (if applicable) in the output folder of the simulation.
"""
function setUpStudioInputs(simulation_id::Int)
    path_to_output = pathToOutputFolder(simulation_id)

    physicell_version = physicellVersion(Simulation(simulation_id))
    upstream_version = split(physicell_version, "-")[1] |> VersionNumber

    rules_header = ["cell_type", "signal", "response", "behavior", "base_response", "max_response", "half_max", "hill_power", "applies_to_dead"]
    if upstream_version < v"1.14.0"
        output_rules_file = "cell_rules.csv"
    else #! starting in PhysiCell v1.14.1, export the v3 rules to cell_rules_parsed.csv
        output_rules_file = "cell_rules_parsed.csv"
        filter!(h -> h != "base_response", rules_header)
    end

    path_to_xml = joinpath(path_to_output, "PhysiCell_settings.xml")
    @assert isfile(path_to_xml) "The file $path_to_xml does not exist. Please check the simulation ID and try again."
    xml_doc = parse_file(path_to_xml)
    save_folder_element = makeXMLPath(xml_doc, ["save", "folder"])
    set_content(save_folder_element, path_to_output)
    if isfile(joinpath(path_to_output, output_rules_file))
        rules_df = CSV.read(joinpath(path_to_output, output_rules_file), DataFrame; header=rules_header)
        if "base_response" in rules_header
            select!(rules_df, Not(:base_response))
        end

        input_rules_file = "cell_rules_temp.csv"
        path_to_input_rules = joinpath(path_to_output, input_rules_file)
        CSV.write(path_to_input_rules, rules_df, writeheader=false)

        enabled_ruleset_element = makeXMLPath(xml_doc, ["cell_rules", "rulesets", "ruleset:enabled:true"])
        folder_element = makeXMLPath(enabled_ruleset_element, "folder")
        filename_element = makeXMLPath(enabled_ruleset_element, "filename")

        set_content(folder_element, path_to_output)
        set_content(filename_element, input_rules_file)
    else
        path_to_input_rules = nothing
    end

    path_to_temp_xml = joinpath(path_to_output, "PhysiCell_settings_temp.xml")
    save_file(xml_doc, path_to_temp_xml)
    free(xml_doc)

    return path_to_temp_xml, path_to_input_rules
end

"""
    executeStudio(path_to_temp_xml::String)

Run PhysiCell Studio with the given temporary XML file.
"""
function executeStudio(path_to_temp_xml::String)
    cmd = `$(pcmm_globals.path_to_python) $(joinpath(pcmm_globals.path_to_studio, "bin", "studio.py")) -c $(path_to_temp_xml)`
    try
        run(pipeline(cmd; stdout=devnull, stderr=devnull))
    catch e
        msg = """
        Error running PhysiCell Studio. Please check the paths and ensure that PhysiCell Studio is installed correctly.
        The command that was run was:
            $(cmd)

        The error message was:
            $(sprint(showerror, e))
        """

        return Base.IOError(msg, e.code)
    end
end

"""
    cleanUpStudioInputs(path_to_temp_xml::String, path_to_input_rules::Union{Nothing,String})

Clean up the temporary files created for PhysiCell Studio.
"""
function cleanUpStudioInputs(path_to_temp_xml::String, path_to_input_rules::Union{Nothing,String})
    rm(path_to_temp_xml, force=true)
    if !isnothing(path_to_input_rules)
        rm(path_to_input_rules, force=true)
    end
end