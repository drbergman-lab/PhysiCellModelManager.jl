module PhysiCellModelManager

using Reexport
@reexport using ModelManager
using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol, Compat
using PhysiCellXMLRules, PhysiCellCellCreator

import ModelManager: initializeModelManager
export initializeModelManager

# Backward-compatibility alias: PCMMOutput was the old name for MMOutput
const PCMMOutput = MMOutput
export PCMMOutput

# SobolPCMM was the old ASCII alias for Sobolʼ; SobolMM is the new generic name
const SobolPCMM = SobolMM
export SobolPCMM

#! PhysiCell-specific files only — generic infrastructure is now in ModelManager
include("physicell_simulator.jl")
include("utilities.jl")
include("globals.jl")              # centralDBFileName(), physicellDir()
include("pruner.jl")
include("variations.jl")

include("compilation.jl")
include("configuration.jl")
include("creation.jl")
include("database.jl")
include("deletion.jl")
include("ic_cell.jl")
include("ic_ecm.jl")
include("simulator_interface.jl")
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

If no arguments are provided, it assumes that the `PhysiCell` and `data` directories are inside the current working directory.

# Arguments
- `path_to_project_dir::AbstractString`: Path to the project directory. Must contain the `PhysiCell` and `data` subdirectories.
- `path_to_physicell::AbstractString`: Path to the PhysiCell directory.
- `path_to_data::AbstractString`: Path to the data directory.
"""
function initializeModelManager(path_to_physicell::AbstractString, path_to_data::AbstractString; auto_upgrade::Bool=false)
    path_to_physicell, path_to_data = (path_to_physicell, path_to_data) .|> abspath .|> normpath
    if !isdir(path_to_physicell) || !isdir(path_to_data)
        throw(PCMMMissingProject("Could not find PhysiCell and/or data directories. Looked for them in: $path_to_physicell, $path_to_data"))
    end
    simulator().dir = path_to_physicell
    return initializeModelManager(simulator(), path_to_data; auto_upgrade)
end

function initializeModelManager(path_to_project::AbstractString; kwargs...)
    return initializeModelManager(joinpath(path_to_project, "PhysiCell"), joinpath(path_to_project, "data"); kwargs...)
end

initializeModelManager(; kwargs...) = initializeModelManager("PhysiCell", "data"; kwargs...)

end