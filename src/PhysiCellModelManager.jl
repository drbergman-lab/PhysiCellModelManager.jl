module PhysiCellModelManager

using Reexport
@reexport using ModelManager
using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol, Compat
using PhysiCellXMLRules, PhysiCellCellCreator

export initializeModelManager
export getSimulationIDs, getMonadIDs #! deprecated aliases

# Backward-compatibility alias: PCMMOutput was the old name for MMOutput
const PCMMOutput = MMOutput
export PCMMOutput

# SobolPCMM was the old ASCII alias for Sobolʼ; SobolMM is the new generic name
const SobolPCMM = SobolMM
export SobolPCMM

#! PhysiCell-specific files only — generic infrastructure is now in ModelManager
include("physicell_simulator.jl")
include("utilities.jl")
include("globals.jl")              # simulator(), findCentralDB(), physicellDir()
include("pruner.jl")
include("variations.jl")           # PhysiCell-specific: variationLocation, addVariationRows, addColumns, etc.

include("compilation.jl")
include("configuration.jl")
include("creation.jl")
include("database.jl")
include("ic_cell.jl")
include("ic_ecm.jl")
include("physicell_runner.jl")
include("up.jl")
include("pcmm_version.jl")
include("physicell_version.jl")
include("components.jl")

include("user_api.jl")

include("loader.jl")

include("analysis/analysis.jl")
include("sensitivity.jl")
include("import.jl")
include("movie.jl")

include("physicell_studio.jl")
include("export.jl")


"""
    baseToExecutable(s::String)

Convert a string to an executable name based on the operating system.
If the operating system is Windows, append ".exe" to the string.
"""
function baseToExecutable end
if Sys.iswindows()
    baseToExecutable(s::String) = "$(s).exe"
else
    baseToExecutable(s::String) = s
end

"""
    PCMMMissingProject

An exception type for when a PhysiCellModelManager.jl project cannot be found during initialization.

# Fields
- `msg::String`: The error message.
"""
struct PCMMMissingProject <: Exception
    msg::String
end

function __init__()
    sim = PhysiCellSimulator()
    sim.compiler = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "g++"
    sim.path_to_python = haskey(ENV, "PCMM_PYTHON_PATH") ? ENV["PCMM_PYTHON_PATH"] : missing
    sim.path_to_studio = haskey(ENV, "PCMM_STUDIO_PATH") ? ENV["PCMM_STUDIO_PATH"] : missing
    sim.path_to_magick = haskey(ENV, "PCMM_IMAGEMAGICK_PATH") ? ENV["PCMM_IMAGEMAGICK_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")
    sim.path_to_ffmpeg = haskey(ENV, "PCMM_FFMPEG_PATH") ? ENV["PCMM_FFMPEG_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")

    n_parallel = haskey(ENV, "PCMM_NUM_PARALLEL_SIMS") ? parse(Int, ENV["PCMM_NUM_PARALLEL_SIMS"]) : 1
    ModelManager.mm_globals_ref[] = ModelManagerGlobals(simulator=sim, max_number_of_parallel_simulations=n_parallel)

    try
        initializeModelManager()
    catch e
        if !(e isa PCMMMissingProject)
            rethrow(e)
        end
        @info """
        PhysiCellModelManager: Could not find a project to initialize in $(pwd()). Do the following to begin:
        1) (Optional) Create a new project with `createProject()` or `createProject("path/to/project")`.
        2) Run `initializeModelManager("path/to/project")` or `initializeModelManager("path/to/physicell", "path/to/data")`.
        """
    end
end

################## Initialization Functions ##################

"""
    pcmmLogo()

Return a string representation of the awesome PhysiCellModelManager.jl logo.
"""
function pcmmLogo()
    return """
    \n
    ▐▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▌
    ▐~~███████████~~~~█████████~~██████~~~██████~██████~~~██████~▌
    ▐~░░███░░░░░███~~███░░░░░███░░██████~██████~░░██████~██████~~▌
    ▐~~░███~~~~░███~███~~~~~░░░~~░███░█████░███~~░███░█████░███~~▌
    ▐~~░██████████~░███~~~~~~~~~~░███░░███~░███~~░███░░███~░███~~▌
    ▐~~░███░░░░░░~~░███~~~~~~~~~~░███~░░░~~░███~~░███~░░░~~░███~~▌
    ▐~~░███~~~~~~~~░░███~~~~~███~░███~~~~~~░███~~░███~~~~~~░███~~▌
    ▐~~█████~~~~~~~~░░█████████~~█████~~~~~█████~█████~~~~~█████~▌
    ▐~░░░░░~~~~~~~~~~░░░░░░░░░~~░░░░░~~~~~░░░░░~░░░░░~~~~~░░░░░~~▌
    ▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌
    \n
      """
end

"""
    initializeModelManager()
    initializeModelManager(path_to_project_dir::AbstractString)
    initializeModelManager(path_to_physicell::AbstractString, path_to_data::AbstractString)

Initialize the PhysiCellModelManager.jl project model manager, identifying the data folder, PhysiCell folder, and loading the central database.

If no arguments are provided, it assumes that the PhysiCell and data directories are in the current working directory.

# Arguments
- `path_to_project_dir::AbstractString`: Path to the project directory as either an absolute or relative path. This folder must contain the `PhysiCell` and `data` directories.
- `path_to_physicell::AbstractString`: Path to the PhysiCell directory as either an absolute or relative path.
- `path_to_data::AbstractString`: Path to the data directory as either an absolute or relative path.
"""
function initializeModelManager(path_to_physicell::AbstractString, path_to_data::AbstractString; auto_upgrade::Bool=false)
    path_to_physicell, path_to_data = (path_to_physicell, path_to_data) .|> abspath .|> normpath

    if !isdir(path_to_physicell) || !isdir(path_to_data)
        throw(PCMMMissingProject("Could not find PhysiCell and/or data directories. Looked for them in: $path_to_physicell, $path_to_data"))
    end

    println(pcmmLogo())
    simulator().dir = path_to_physicell
    mm_globals().data_dir = path_to_data
    findCentralDB()
    if !resolvePCMMVersion(auto_upgrade)
        println("Could not successfully upgrade database. Please check the logs for more information.")
        return false
    end
    s = "PhysiCellModelManager.jl v$(string(pcmmVersion()))"
    println(s)
    println("-"^length(s))
    println(rpad("Path to PhysiCell:", 25, ' ') * physicellDir())
    println(rpad("Path to data:", 25, ' ') * dataDir())
    println(rpad("Path to database:", 25, ' ') * centralDB().file)
    println(rpad("Path to inputs.toml:", 25, ' ') * pathToInputsConfig())
    if !parseProjectInputsConfigurationFile()
        println("Project configuration file parsing failed.")
        return false
    end
    initializeDatabase()
    if !isInitialized()
        mm_globals().db = SQLite.DB()
        println("Database initialization failed.")
        return false
    end
    postInitDisplay(mm_globals().simulator)
    println(rpad("Running on HPC:", 25, ' ') * string(mm_globals().run_on_hpc))
    println(rpad("Max parallel sims:", 25, ' ') * string(mm_globals().max_number_of_parallel_simulations))
    flush(stdout)

    try
        databaseDiagnostics()
    catch e
        """
        Database diagnostics failed during initialization with error: $(e).
        PCMM was not able to check the integrity of the database.
        This is unexpected behavior; please report this issue on the PhysiCellModelManager.jl GitHub page.
        """ |> println
    end

    return isInitialized()
end

function initializeModelManager(path_to_project::AbstractString; kwargs...)
    path_to_physicell, path_to_data = (joinpath(path_to_project, folder) for folder in ("PhysiCell", "data"))
    return initializeModelManager(path_to_physicell, path_to_data; kwargs...)
end

initializeModelManager(; kwargs...) = initializeModelManager("PhysiCell", "data"; kwargs...)

################## Deprecated aliases ##################

"""
    getSimulationIDs(args...)

Deprecated alias for [`simulationIDs`](@ref). Use `simulationIDs` instead.
"""
function getSimulationIDs(args...)
    Base.depwarn("`getSimulationIDs` is deprecated. Use `simulationIDs` instead.", :getSimulationIDs; force=true)
    return simulationIDs(args...)
end

"""
    getMonadIDs(args...)

Deprecated alias for [`monadIDs`](@ref). Use `monadIDs` instead.
"""
function getMonadIDs(args...)
    Base.depwarn("`getMonadIDs` is deprecated. Use `monadIDs` instead.", :getMonadIDs; force=true)
    return monadIDs(args...)
end

end