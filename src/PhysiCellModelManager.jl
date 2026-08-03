module PhysiCellModelManager

using Reexport
@reexport using ModelManager
using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol, Compat
using PhysiCellXMLRules, PhysiCellCellCreator
using PhysiCellOutput

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

"""
    _pcmmGlobalsRegistered()

Return `true` when [`ModelManager.mm_globals_ref`](@ref) already holds initialized globals whose
simulator is a [`PhysiCellSimulator`](@ref) — that is, when PhysiCellModelManager.jl has already
initialized a project in this Julia process.

`mm_globals_ref` is shared by every ModelManager backend but holds only one `simulator`, so the
simulator type must be checked too: if another backend owns the globals, PhysiCellModelManager.jl
has to claim them rather than defer and then run against a foreign simulator.

# Returns
- `Bool`: `true` only if PhysiCellModelManager.jl owns initialized globals.

# Examples
```julia
julia> using PhysiCellModelManager   # auto-initializes when a project is in the working directory

julia> PhysiCellModelManager._pcmmGlobalsRegistered()
true
```
"""
function _pcmmGlobalsRegistered()
    globals = ModelManager.mm_globals_ref[]
    return !isnothing(globals) && globals.simulator isa PhysiCellSimulator && globals.initialized
end

#! `Base.generating_output()` is itself only `ccall(:jl_generating_output, ...) == 1` when called
#! with no argument, and is unexported either way. Prefer it where it exists so Base owns the
#! mapping to the C entry point, and fall back to the `ccall` on versions that predate it.
@static if isdefined(Base, :generating_output)
    _generatingOutput() = Base.generating_output()
else
    _generatingOutput() = ccall(:jl_generating_output, Cint, ()) == 1
end

"""
    _generatingOutput()

Return `true` while this Julia process is writing a precompilation cache file or a system image.

`__init__` also runs inside the precompilation subprocess of every package that depends on
PhysiCellModelManager.jl, so work with effects outside the process must be skipped there.

# Returns
- `Bool`: `true` if a cache file or system image is being generated.

# Examples
```julia
julia> PhysiCellModelManager._generatingOutput()   # in an ordinary session
false
```
"""
_generatingOutput

function __init__()
    #! Nothing to do if we already own initialized globals. Deliberately keyed on the simulator
    #! type as well: when another backend owns them, fall through and claim them for PhysiCell.
    _pcmmGlobalsRegistered() && return

    sim = PhysiCellSimulator()
    sim.compiler = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "g++"
    sim.path_to_python = haskey(ENV, "PCMM_PYTHON_PATH") ? ENV["PCMM_PYTHON_PATH"] : missing
    sim.path_to_studio = haskey(ENV, "PCMM_STUDIO_PATH") ? ENV["PCMM_STUDIO_PATH"] : missing
    sim.path_to_magick = haskey(ENV, "PCMM_IMAGEMAGICK_PATH") ? ENV["PCMM_IMAGEMAGICK_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")
    sim.path_to_ffmpeg = haskey(ENV, "PCMM_FFMPEG_PATH") ? ENV["PCMM_FFMPEG_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")

    n_parallel = haskey(ENV, "PCMM_NUM_PARALLEL_SIMS") ? parse(Int, ENV["PCMM_NUM_PARALLEL_SIMS"]) : 1
    ModelManager.mm_globals_ref[] = ModelManagerGlobals(simulator=sim, max_number_of_parallel_simulations=n_parallel)

    #! Registering the globals above is pure in-memory work, so it is safe to do while a cache file
    #! is being written — and keeps `mm_globals()` usable by any precompilation workload downstream.
    #! Auto-initializing a project is not safe there: this `__init__` runs in the precompilation
    #! subprocess of every dependent package, where it would open (and create) the database of
    #! whatever project `pwd()` happens to contain and print the banner from a throwaway process.
    _generatingOutput() && return

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