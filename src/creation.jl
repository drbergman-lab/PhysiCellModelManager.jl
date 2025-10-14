using Downloads, JSON3, CSV, PhysiCellCellCreator

export createProject

"""
    createProject(project_dir::String="."; clone_physicell::Bool=true, template_as_default::Bool=true, terse::Bool=false)

Create a new PhysiCellModelManager.jl project structure.

Creates a new project directory at `project_dir` with the following structure:
```
project_dir
├── data
├── PhysiCell # The latest release from https://github.com/drbergman/PhysiCell
└── scripts
```
`data` is populated with the standard structure. `PhysiCell` is a copy of PhysiCell. `scripts` contains a generated `GenerateData.jl` file.

# Arguments
- `project_dir::String="."`: The directory in which to create the project. Relative paths are resolved from the current working directory where Julia was launched.
- `clone_physicell::Bool=true`: Whether to clone the PhysiCell repository. If `false`, the latest release will be downloaded. Recommended to set to `true` so PhysiCellModelManager.jl will be able to track changes to the PhysiCell repository.
- `template_as_default::Bool=true`: Whether to set up the project with the template files as the default. If `false`, the project will be set up with an empty structure.
- `terse::Bool=false`: Whether to generate a terse `GenerateData.jl` file. If `true`, the file will be generated without comments and explanations.

# Note
The names of the `data` and `PhysiCell` directories are fixed and cannot be changed. Their relative locations should not be changed without updating the `GenerateData.jl` file and other scripts accordingly.
The name of the `scripts` folder and the `GenerateData.jl` are just by convention and can be changed.
"""
function createProject(project_dir::String="."; clone_physicell::Bool=true, template_as_default::Bool=true, terse::Bool=false)
    global pcmm_globals
    pcmm_globals.initialized = false #! in case the user is creating a project in an already-initialized directory
    mkpath(project_dir)
    physicell_dir = setUpPhysiCell(project_dir, clone_physicell)
    data_dir = joinpath(project_dir, "data")

    setUpInputs(data_dir, physicell_dir, template_as_default)
    setUpComponents(data_dir, physicell_dir)
    setUpScripts(project_dir, physicell_dir, data_dir, template_as_default, terse)
    createDefaultGitIgnore(project_dir)
    initializeModelManager(physicell_dir, data_dir)
    project_dir_norm = normpath(abspath(project_dir))
    msg = """

    PhysiCellModelManager.jl project created at $(project_dir_norm)! A couple notes:
    1. We got you started this time (see output above). Next time, just do:

            shell> cd $project_dir_norm
            julia> using PhysiCellModelManager

    2. Check out the sample script in `$(joinpath(project_dir_norm, "scripts"))` to get started with running simulations.
    3. A .gitignore file has been created in the data directory.
    4. If you want to track changes to this project, you can initialize a git repository:

            cd $project_dir_norm
            git init
            git submodule add https://github.com/drbergman/PhysiCell

    5. Take a look at the best practices for PCMM: https://drbergman-lab.github.io/PhysiCellModelManager.jl/stable/man/best_practices/

    Happy modeling!
    """
    println(msg)
end

"""
    latestReleaseTag(repo_url::String)

Get the latest release tag from a GitHub repository.
"""
function latestReleaseTag(repo_url::String)
    api_url = replace(repo_url, "github.com" => "api.github.com/repos") * "/releases/latest"
    #! include this header for CI testing to not exceed request limit (I think?): macos for some reason raised a `RequestError: HTTP/2 403`; users should not need to set this ENV variable
    headers = haskey(ENV, "PCMM_PUBLIC_REPO_AUTH") ? Dict("Authorization" => "token $(ENV["PCMM_PUBLIC_REPO_AUTH"])") : Pair{String,String}[]
    response = Downloads.download(api_url; headers=headers)
    release_info = JSON3.read(response, Dict{String, Any})
    return release_info["tag_name"]
end

"""
    setUpPhysiCell(project_dir::String, clone_physicell::Bool)

Set up the PhysiCell directory in the project directory.

If the directory already exists, it will not be created again.
If `clone_physicell` is `true`, the latest release of the PhysiCell repository will be cloned.
"""
function setUpPhysiCell(project_dir::String, clone_physicell::Bool)
    physicell_dir = joinpath(project_dir, "PhysiCell")
    if isdir(physicell_dir)
        println("PhysiCell directory already exists ($(physicell_dir)). Hopefully it's the PhysiCellModelManager.jl-compatible version!")
        return physicell_dir
    end
    is_git_repo = isdir(joinpath(project_dir, ".git"))
    if clone_physicell
        latest_tag = latestReleaseTag("https://github.com/drbergman/PhysiCell")
        if is_git_repo
            println("Cloning PhysiCell repository as submodule")
            quietRun(`git submodule add https://github.com/drbergman/PhysiCell $(physicell_dir)`)
            quietRun(`git submodule update --init --recursive --depth 1`)
            quietRun(`git -C $physicell_dir checkout $latest_tag`)
        else
            println("Cloning PhysiCell repository")
            quietRun(`git clone --branch $latest_tag --depth 1 https://github.com/drbergman/PhysiCell $(physicell_dir)`)
        end
    else
        #! download drbergman/PhysiCell main branch
        println("Downloading PhysiCell repository")
        url = "https://api.github.com/repos/drbergman/PhysiCell/releases/latest"
        headers = haskey(ENV, "PCMM_PUBLIC_REPO_AUTH") ? Dict("Authorization" => "token $(ENV["PCMM_PUBLIC_REPO_AUTH"])") : Pair{String,String}[]
        response = Downloads.download(url; headers=headers)
        release_data = JSON3.read(response)
        zipball_url = release_data["zipball_url"]
        zip_path = joinpath(project_dir, "PhysiCell.zip")
        Downloads.download(zipball_url, zip_path)
        extract_path = joinpath(project_dir, "PhysiCell_extract")
        quietRun(`unzip $zip_path -d $extract_path`)
        rm(zip_path)
        @assert (readdir(extract_path) |> length) == 1
        path_to_extracted_physicell = readdir(extract_path; join=true)[1]
        mv(path_to_extracted_physicell, physicell_dir)
        rm(extract_path; recursive=false)
    end
    return physicell_dir
end

"""
    setUpComponents(data_dir::String, physicell_dir::String)

Set up the components directory in the data directory and populate it with the `\"Toy_Metabolic_Model.xml\"` file.
"""
function setUpComponents(data_dir::String, physicell_dir::String)
    components_dir = joinpath(data_dir, "components")
    mkpath(components_dir)

    #! make sbml roadrunner components and populate with an example sbml for a roadrunner model
    roadrunner_components_dir = joinpath(components_dir, "roadrunner")
    mkpath(roadrunner_components_dir)
    cp(joinpath(physicell_dir, "sample_projects_intracellular", "ode", "ode_energy", "config", "Toy_Metabolic_Model.xml"), joinpath(roadrunner_components_dir, "Toy_Metabolic_Model.xml"); force=true)
end

"""
    setUpInputs(data_dir::String, physicell_dir::String, template_as_default::Bool)

Set up the inputs directory in the data directory, if the data directory does not already exist.
"""
function setUpInputs(data_dir::String, physicell_dir::String, template_as_default::Bool)
    if isdir(data_dir)
        println("Data directory already exists ($(data_dir)). Skipping setup of data directory.")
        return
    end

    inputs_dir = joinpath(data_dir, "inputs")
    mkpath(inputs_dir)
    createInputsTOMLTemplate(joinpath(inputs_dir, "inputs.toml"))

    mkpath(joinpath(inputs_dir, "configs"))
    mkpath(joinpath(inputs_dir, "custom_codes"))
    for ic in ["cells", "substrates", "ecms", "dcs"]
        mkpath(joinpath(inputs_dir, "ics", ic))
    end
    mkpath(joinpath(inputs_dir, "rulesets_collections"))
    mkpath(joinpath(inputs_dir, "intracellulars"))

    if template_as_default
        setUpTemplate(physicell_dir, inputs_dir)
    end
end

"""
    setUpRequiredFolders(path_to_template::String, inputs_dir::String, folder::String)

Set up the required folders in the inputs directory.
"""
function setUpRequiredFolders(path_to_template::String, inputs_dir::String, folder::String)
    config_folder = joinpath(inputs_dir, "configs", folder)
    mkpath(config_folder)
    cp(joinpath(path_to_template, "config", "PhysiCell_settings.xml"), joinpath(config_folder, "PhysiCell_settings.xml"))

    custom_codes_folder = joinpath(inputs_dir, "custom_codes", folder)
    mkpath(custom_codes_folder)
    cp(joinpath(path_to_template, "custom_modules"), joinpath(custom_codes_folder, "custom_modules"))
    cp(joinpath(path_to_template, "main.cpp"), joinpath(custom_codes_folder, "main.cpp"))
    cp(joinpath(path_to_template, "Makefile"), joinpath(custom_codes_folder, "Makefile"))
end

"""
    icFilename(table_name::String)

Get the filename for the given IC type for setting up the IC folder.
"""
function icFilename(table_name::String)
    if table_name == "cells"
        return "cells.csv"
    elseif table_name == "substrates"
        return "substrates.csv"
    elseif table_name == "ecms"
        return "ecm.csv"
    elseif table_name == "dcs"
        return "dcs.csv"
    else
        throw(ArgumentError("table_name must be 'cells', 'substrates', 'ecms', or `dcs`."))
    end
end

"""
    setUpICFolder(path_to_template::String, inputs_dir::String, ic_name::String, folder::String)

Set up the IC folder in the inputs directory for the given IC type.
"""
function setUpICFolder(path_to_template::String, inputs_dir::String, ic_name::String, folder::String)
    ic_folder = joinpath(inputs_dir, "ics", ic_name, folder)
    mkpath(ic_folder)
    filename = icFilename(ic_name)
    cp(joinpath(path_to_template, "config", filename), joinpath(ic_folder, filename))
end

"""
    setUpTemplate(physicell_dir::String, inputs_dir::String)

Set up the template project in the inputs directory.
"""
function setUpTemplate(physicell_dir::String, inputs_dir::String)
    path_to_template = joinpath(physicell_dir, "sample_projects", "template")

    setUpRequiredFolders(path_to_template, inputs_dir, "0_template")

    rulesets_collection_folder = joinpath(inputs_dir, "rulesets_collections", "0_template")
    mkpath(rulesets_collection_folder)
    open(joinpath(rulesets_collection_folder, "base_rulesets.csv"), "w") do f
        write(f, "default,pressure,decreases,cycle entry,0.0,0.5,4,0") #! actually add a rule for example's sake
    end

    setUpICFolder(path_to_template, inputs_dir, "cells", "0_template")
    setUpICFolder(path_to_template, inputs_dir, "substrates", "0_template")

    #! also set up a ic cell folder using the xml-based version
    PhysiCellModelManager.createICCellXMLTemplate(joinpath(inputs_dir, "ics", "cells", "1_xml"))
end

"""
    setUpScripts(project_dir::String, physicell_dir::String, data_dir::String, template_as_default::Bool, terse::Bool)

Set up the scripts directory in the project directory.
"""
function setUpScripts(project_dir::String, physicell_dir::String, data_dir::String, template_as_default::Bool, terse::Bool)
    path_to_scripts = joinpath(project_dir, "scripts")
    mkpath(path_to_scripts)

    path_to_generate_data = joinpath(path_to_scripts, "GenerateData.jl")
    if isfile(path_to_generate_data)
        println("GenerateData.jl already exists ($(joinpath(path_to_scripts,"GenerateData.jl"))). Skipping creation of this starter file.")
        return
    end
    path_to_configs = joinpath(data_dir, "inputs", "configs")
    config_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_configs)" : "\"default\" # add this folder with config file to $(path_to_configs)"

    path_to_rulesets_collections = joinpath(data_dir, "inputs", "rulesets_collections")
    rulesets_collection_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_rulesets_collections); a rule has been added for the sake of the example" : "\"\" # optionally add this folder with base_rulesets.csv to $(path_to_rulesets_collections)"

    path_to_custom_codes = joinpath(data_dir, "inputs", "custom_codes")
    custom_code_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_custom_codes)" : "\"default\" # add this folder with main.cpp, Makefile, and custom_modules to $(path_to_custom_codes)"

    path_to_ics = joinpath(data_dir, "inputs", "ics")
    path_to_ic_cells = joinpath(path_to_ics, "cells")
    ic_cell_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_ic_cells)" : "\"\" # optionally add this folder with cells.csv to $(path_to_ic_cells)"

    tersify(s::String) = (terse ? "" : s)
    generate_data_lines = """
    using PhysiCellModelManager

    # if you launch the script from the project directory, you don't need this next line explicitly calling initializeModelManager
    # initializeModelManager(\"$(normpath(abspath(project_dir)))\") 

    ############ set up ############

    config_folder = $(config_folder)
    custom_code_folder = $(custom_code_folder)
    rulesets_collection_folder = $(rulesets_collection_folder)
    intracellular_folder = \"\" # optionally add this folder with intracellular.xml to $(joinpath(path_to_ics, "intracellulars"))

    ic_cell_folder = $(ic_cell_folder)
    ic_substrate_folder = \"\" # optionally add this folder with substrates.csv to $(joinpath(path_to_ics, "substrates"))
    ic_ecm_folder = \"\" # optionally add this folder with ecms.csv to $(joinpath(path_to_ics, "ecms"))
    ic_dc_folder = \"\" # optionally add this folder with dcs.csv to $(joinpath(path_to_ics, "dcs"))

    $(tersify("""
    # package them all together into a single object
    """))\
    inputs = InputFolders(config_folder, custom_code_folder;
                            rulesets_collection=rulesets_collection_folder,
                            intracellular=intracellular_folder,
                            ic_cell=ic_cell_folder,
                            ic_substrate=ic_substrate_folder,
                            ic_ecm=ic_ecm_folder,
                            ic_dc=ic_dc_folder)

    ############ make the simulations short ############

    $(tersify("""
    # We will set the default simulations to have a lower max time.
    # This will serve as a reference for the following simulations.
    """))\
    xml_path = [\"overall\"; \"max_time\"]
    value = 60.0
    dv_max_time = DiscreteVariation(xml_path, value)
    reference = createTrial(inputs, dv_max_time; n_replicates=0) # since we don't want to run this, set the n_replicates to 0

    ############ set up variables to control running simulations ############

    $(tersify("""
    # you can force the recompilation, but it is usually only necesary if you change core code
    # if you change custom code, it is recommended you make a new custom codes folder in $(path_to_custom_codes)...
    # ...especially if the database already has simulations run with that custom code
    """))\
    force_recompile = false

    $(tersify("""
    # PhysiCellModelManager.jl records which simulations all use the same parameter vector...
    # ...to reuse them (unless the user opts out)
    """))\
    use_previous = true # if true, will attempt to reuse simulations with the same parameters; otherwise run new simulations

    $(tersify("""
    # a monad refers to a single collection of identical simulations...
    # except for randomness (could be do to the initial seed or stochasticity introduced by omp threading)
    # n_replicates is the number of replicates to run for each parameter vector...
    # ...PhysiCellModelManager.jl records which simulations all use the same parameter vector...
    # ...and will attempt to reuse these (unless the user opts out)...
    # ...so this parameter is the _min_ because there may already be many sims with the same parameters
    """))\
    n_replicates = 1

    ############ set up parameter variations ############

    $(tersify("""
    # assume you have the template project with \"default\" as a cell type...
    # ...let's vary their cycle durations and apoptosis rates

    # get the xml path to duration of phase 0 of the default cell type
    # this is a list of strings in which each string is either...
    # \t1) the name of a tag in the xml file OR
    # \t2) the name of a tag along with the value of one attribute (name:attribute_name:attribute_value)
    """))\
    xml_path = PhysiCellModelManager.cyclePath(\"default\", \"phase_durations\", \"duration:index:0\")
    vals = [200.0, 300.0, 400.0] # choose 3 discrete values to vary the duration of phase 0
    dv_phase_0_duration = DiscreteVariation(xml_path, vals)

    $(tersify("""
    # now do the same, but for the apoptosis rate
    """))\
    xml_path = PhysiCellModelManager.apoptosisPath(\"default\", \"death_rate\")
    vals = [4.31667e-05, 5.31667e-05, 6.31667e-05] # choose 3 discrete values to vary the apoptosis rate
    dv_apoptosis_rate = DiscreteVariation(xml_path, vals)

    $(tersify("""
    # now combine them into a list:
    """))\
    discrete_variations = [dv_phase_0_duration, dv_apoptosis_rate]

    ############ run the sampling ############

    $(tersify("""
    # now create the sampling (varied parameter values) with these parameters
    # we will give it a reference to the monad with the short max time
    """))\
    sampling = createTrial(reference, discrete_variations; n_replicates=n_replicates, use_previous=use_previous)

    $(tersify("""
    # at this point, we have only added the sampling to the database...
    # ...along with the monads and simulations that make it up
    # before running, we will set the number of parallel simulations to run.
    # note: this will only be used when running locally, i.e., not on an HPC
    # by default, PhysiCellModelManager.jl will run the simulations serially, i.e., 1 in \"parallel\".
    # change this by calling:
    """))\
    setNumberOfParallelSims(4) # for example, to run 4 simulations in parallel

    $(tersify("""
    # you can change this default behavior on your machine by setting an environment variable...
    # called PCMM_NUM_PARALLEL_SIMS
    # this is read during `initializeModelManager`...
    # meaning subsequent calls to `setNumberOfParallelSims` will overwrite the value
    # A simple way to use this when running the script is to run in your shell:
    # `PCMM_NUM_PARALLEL_SIMS=4 julia $(path_to_generate_data)`
    """))\

    $(tersify("""
    # now run the sampling
    """))\
    out = run(sampling; force_recompile=force_recompile)

    $(tersify("""
    # If you are running on an SLURM-based HPC, PhysiCellModelManager.jl will detect this and calls to `sbatch`...
    # ...to parallelize the simulations, batching out each simulation to its own job.
    """))\
    """

    open(path_to_generate_data, "w") do f
        write(f, generate_data_lines)
    end
end

"""
    createDefaultGitIgnore(project_dir::String)

Create a default `.gitignore` file for the data directory.
The following are ignored:
- all databases
- all variations folders (folders containing modified versions of the base files)
- compile-time-generated files
- all outputs
"""
function createDefaultGitIgnore(project_dir::String)
    data_gitignore_path = joinpath(project_dir, "data", ".gitignore")
    mode = isfile(data_gitignore_path) ? "a" : "w" # append if file exists, otherwise write
    open(data_gitignore_path, mode) do f
        write(
            f,
            """
            # PCMM

            ## databases
            *.db

            ## variations folders
            $(locationVariationsFolder("*"))/

            ## custom codes
            compilation*
            macros.txt
            physicell_commit_hash.txt
            project*

            ## outputs
            /outputs/
            """
        )
    end
end