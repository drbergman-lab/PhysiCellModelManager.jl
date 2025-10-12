using Parameters, SQLite

"""
    PCMMGlobals

A mutable struct to hold global variables for the PhysiCellModelManager.jl package.
The global variable `pcmm_globals` is the instance of this struct that is used throughout the package.

# Fields
- `initialized::Bool`: Indicates whether the project database has been initialized.
- `data_dir::String`: The path to the data directory. This is set when the model manager is initialized.
- `physicell_dir::String`: The path to the PhysiCell directory. This is set when the model manager is initialized.
- `inputs_dict::Dict{Symbol,Any}`: A dictionary that maps the types of inputs to the data that defines how they are set up and what they can do. Read in from the `inputs.toml` file in the `data` directory.
- `project_locations::ProjectLocations`: The global [`ProjectLocations`](@ref) object that contains information about the locations of input files in the project.
- `db::SQLite.DB`: The database connection object to the central SQLite database for the open project. Set this with [`initializeModelManager`](@ref).
- `strict_physicell_check::Bool`: Indicates whether to perform strict checks on the PhysiCell directory for reproducibility. If true, requires a clean git folder (in particular, not downloaded) to skip recompile.
- `current_physicell_version_id::Int`: The ID of the current version of PhysiCell being used as defined in the database. This is set when the model manager is initialized.
- `physicell_compiler::String`: The compiler used to compile the PhysiCell code. This is set when the model manager is initialized.
- `march_flag::String`: The march flag to be used when compiling the code. If running on an HPC, this is set to "x86-64" which will work across different CPU manufacturers that may be present on an HPC. Otherwise, set to "native".
- `run_on_hpc::Bool`: A boolean that indicates whether the code is running on an HPC environment. This is set to true if the `sbatch` command is available when compiling PhysiCellModelManager.jl.
- `sbatch_options::Dict{String,Any}`: A dictionary that will be used to pass options to the sbatch command. The keys are the flag names and the values are the values used for the flag. This is initialized using [`defaultJobOptions`](@ref) and can be modified using [`setJobOptions`](@ref).
- `max_number_of_parallel_simulations::Int`: The maximum number of parallel simulations that can be run at once. If running on an HPC, this is ignored and instead PhysiCellModelManager.jl will queue one job per simulation.
- `path_to_python::Union{Missing,String}`: The path to the python executable for running PhysiCell Studio. See [`runStudio`](@ref).
- `path_to_studio::Union{Missing,String}`: The path to the PhysiCell Studio directory. See [`runStudio`](@ref).
- `path_to_magick::Union{Missing,String}`: The path to the ImageMagick installation. See [`makeMovie`](@ref).
- `path_to_ffmpeg::Union{Missing,String}`: The path to the FFmpeg installation. See [`makeMovie`](@ref).
"""
@with_kw mutable struct PCMMGlobals
    initialized::Bool = false

    data_dir::String = ""
    physicell_dir::String = ""

    inputs_dict::Dict{Symbol,Any} = Dict{Symbol,Any}()
    project_locations::ProjectLocations = ProjectLocations(inputs_dict)

    db::SQLite.DB = SQLite.DB()

    strict_physicell_check::Bool = true
    current_physicell_version_id::Int = -1
    physicell_compiler::String = "g++"

    run_on_hpc::Bool = isRunningOnHPC()
    sbatch_options::Dict{String,Any} = defaultJobOptions()

    march_flag::String = run_on_hpc ? "x86-64" : "native"

    max_number_of_parallel_simulations::Int = 1

    path_to_python::Union{Missing,String} = missing
    path_to_studio::Union{Missing,String} = missing
    path_to_magick::Union{Missing,String} = missing
    path_to_ffmpeg::Union{Missing,String} = missing
end

const pcmm_globals = PCMMGlobals()

"""
    findCentralDB()

Find the central database for the PhysiCellModelManager.jl package and update the global `pcmm_globals.db` variable.
This function checks for the existence of the old `vct.db` file and uses it if it exists, otherwise it uses the new `pcmm.db` file.
"""
function findCentralDB()
    global pcmm_globals
    path_to_db(f) = joinpath(dataDir(), f)
    old_db_path = path_to_db("vct.db")
    path_to_central_db = isfile(old_db_path) ? old_db_path : path_to_db("pcmm.db")
    pcmm_globals.db = SQLite.DB(path_to_central_db)
end

"""
    dataDir()

Get the data directory global variable for the current project.
"""
dataDir() = pcmm_globals.data_dir

"""
    physicellDir()

Get the PhysiCell directory global variable for the current project.
"""
physicellDir() = pcmm_globals.physicell_dir

"""
    inputsDict()

Get the inputs dictionary global variable for the current project.
"""
inputsDict() = pcmm_globals.inputs_dict

"""
    projectLocations()

Get the project locations global variable for the current project.
"""
projectLocations() = pcmm_globals.project_locations

"""
    centralDB()

Get the database global variable for the current project.
"""
centralDB() = pcmm_globals.db

"""
    isInitialized()

Check if the model manager has been initialized for a project.
"""
isInitialized() = pcmm_globals.initialized

"""
    assertInitialized()

Assert that the model manager has been initialized for a project.
If not, throw an error with a message indicating that the user should run `initializeModelManager` first.
"""
function assertInitialized()
    @assert isInitialized() "The model manager has not been initialized for a project. Please run `initializeModelManager` first."
end