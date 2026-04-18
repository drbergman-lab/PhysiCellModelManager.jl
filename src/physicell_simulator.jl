export PhysiCellSimulator

#! AbstractSimulator and all interface function stubs are defined in ModelManager.jl.
#! This file defines the PhysiCell concrete backend and re-exports AbstractSimulator
#! (already exported by ModelManager, re-exported from the module level).

"""
    PhysiCellSimulator <: AbstractSimulator

The PhysiCell backend for [`AbstractSimulator`](@ref ModelManager.AbstractSimulator). Holds all PhysiCell-specific
state (paths, compiler, version ID) so that the generic infrastructure in
[`ModelManagerGlobals`](@ref) remains simulator-agnostic.

Interface methods are implemented in `src/physicell_simulator.jl`.

# Fields
- `dir::String`: Path to the PhysiCell source directory.
- `compiler::String`: C++ compiler command (default `"g++"`; overridden by `PHYSICELL_CPP` env var).
- `strict_check::Bool`: If `true`, require a clean git directory to skip recompile.
- `current_version_id::Int`: Database ID for the active PhysiCell version; set during initialization.
- `march_flag::String`: `-march` flag for compilation (e.g. `"native"` or `"x86-64"` on HPC).
- `path_to_python::Union{Missing,String}`: Python executable path for PhysiCell Studio.
- `path_to_studio::Union{Missing,String}`: PhysiCell Studio directory path.
- `path_to_magick::Union{Missing,String}`: ImageMagick binary path for movie creation.
- `path_to_ffmpeg::Union{Missing,String}`: FFmpeg binary path for movie creation.
"""
mutable struct PhysiCellSimulator <: ModelManager.AbstractSimulator
    dir::String
    compiler::String
    strict_check::Bool
    current_version_id::Int
    march_flag::String
    path_to_python::Union{Missing,String}
    path_to_studio::Union{Missing,String}
    path_to_magick::Union{Missing,String}
    path_to_ffmpeg::Union{Missing,String}
end

"""
    PhysiCellSimulator()

Construct a default `PhysiCellSimulator` with placeholder values. Fields are
populated during `__init__` and [`initializeModelManager`](@ref).
"""
function PhysiCellSimulator()
    run_on_hpc = isRunningOnHPC()
    return PhysiCellSimulator(
        "",          # dir — set by initializeModelManager
        "g++",       # compiler — overridden by __init__ from ENV
        true,        # strict_check
        -1,          # current_version_id — set during DB init
        run_on_hpc ? "x86-64" : "native", # march_flag
        missing,     # path_to_python
        missing,     # path_to_studio
        missing,     # path_to_magick
        missing,     # path_to_ffmpeg
    )
end
