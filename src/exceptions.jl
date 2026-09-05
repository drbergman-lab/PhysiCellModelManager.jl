#! PCMM's own exception types.
#!
#! These exist so that a caller — in particular Model Manager Studio, which drives PCMM
#! programmatically and cannot parse prose out of an `ErrorException` — can branch on *what*
#! went wrong. Every one of them subtypes `PCMMException`, so a GUI can catch the family for
#! "PCMM refused" or a concrete type for a specific condition, and each carries the identifiers
#! a caller needs to act rather than only a message string.

@compat public PCMMException, PCMMMissingProject, PCMMStudioLaunchError

"""
    PCMMException

Abstract supertype of every exception PhysiCellModelManager.jl raises on its own behalf.

Catch this to handle any PCMM-specific failure, or a concrete subtype to handle one condition.
Errors raised by Julia itself or by a dependency are not part of this hierarchy.

# Examples
```julia
try
    runStudio(1)
catch e
    e isa PCMMException || rethrow()   # a PCMM refusal, not a bug
    @info "PCMM could not do that" reason=sprint(showerror, e)
end
```
"""
abstract type PCMMException <: Exception end

"""
    PCMMMissingProject(msg::String)

A PhysiCellModelManager.jl project could not be found.

Raised by [`initializeModelManager`](@ref) when neither the given nor the inferred paths hold a
PhysiCell directory and a data directory. Auto-initialization on `using PhysiCellModelManager`
catches this one and prints guidance instead of failing.

# Fields
- `msg::String`: which paths were searched.

# Examples
```julia
try
    initializeModelManager("not-a-project")
catch e
    e isa PCMMMissingProject && @info "no project there"
end
```
"""
struct PCMMMissingProject <: PCMMException
    msg::String
end

Base.showerror(io::IO, e::PCMMMissingProject) = print(io, "PCMMMissingProject: ", e.msg)

"""
    PCMMStudioLaunchError(cmd::Cmd, cause::Exception)

PhysiCell Studio could not be launched, or exited with an error.

Carries the command that was run and the underlying exception, which differs by failure mode:
`Base.IOError` when the Python executable itself could not be spawned (a wrong
`PCMM_PYTHON_PATH`), and `ProcessFailedException` when Studio ran and exited non-zero (a wrong
`PCMM_STUDIO_PATH`, or a Studio-side error). Inspect `cause` to tell those apart.

# Fields
- `cmd::Cmd`: the command PCMM ran.
- `cause::Exception`: the exception raised by `run`.

# Examples
```julia
try
    runStudio(1)
catch e
    e isa PCMMStudioLaunchError || rethrow()
    e.cause isa Base.IOError ? @warn("check PCMM_PYTHON_PATH") : @warn("Studio itself failed")
end
```
"""
struct PCMMStudioLaunchError <: PCMMException
    cmd::Cmd
    cause::Exception
end

function Base.showerror(io::IO, e::PCMMStudioLaunchError)
    print(io, "PCMMStudioLaunchError: could not run PhysiCell Studio.\n")
    print(io, "Check that the paths to python and to PhysiCell Studio are correct.\n")
    print(io, "  Command: $(e.cmd)\n")
    print(io, "  Cause:   $(sprint(showerror, e.cause))")
end
