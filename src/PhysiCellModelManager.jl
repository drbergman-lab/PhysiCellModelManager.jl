module PhysiCellModelManager

using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol, Compat
using PhysiCellXMLRules, PhysiCellCellCreator

export initializeModelManager, simulationIDs, setNumberOfParallelSims, getMonadIDs, getSimulationIDs

#! put these first as they define classes the rest rely on
include("classes.jl")
include("project_configuration.jl")
include("hpc.jl")
include("globals.jl")
include("pruner.jl")
include("variations.jl")

include("compilation.jl")
include("configuration.jl")
include("creation.jl")
include("database.jl")
include("deletion.jl")
include("ic_cell.jl")
include("ic_ecm.jl")
include("runner.jl")
include("recorder.jl")
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

function __init__()
    pcmm_globals.physicell_compiler = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "g++"

    pcmm_globals.max_number_of_parallel_simulations = haskey(ENV, "PCMM_NUM_PARALLEL_SIMS") ? parse(Int, ENV["PCMM_NUM_PARALLEL_SIMS"]) : 1

    pcmm_globals.path_to_python = haskey(ENV, "PCMM_PYTHON_PATH") ? ENV["PCMM_PYTHON_PATH"] : missing
    pcmm_globals.path_to_studio = haskey(ENV, "PCMM_STUDIO_PATH") ? ENV["PCMM_STUDIO_PATH"] : missing
    pcmm_globals.path_to_magick = haskey(ENV, "PCMM_IMAGEMAGICK_PATH") ? ENV["PCMM_IMAGEMAGICK_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")
    pcmm_globals.path_to_ffmpeg = haskey(ENV, "PCMM_FFMPEG_PATH") ? ENV["PCMM_FFMPEG_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")

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
    global pcmm_globals
    path_to_physicell, path_to_data = (path_to_physicell, path_to_data) .|> abspath .|> normpath

    #! print big logo of PhysiCellModelManager.jl here
    println(pcmmLogo())
    pcmm_globals.physicell_dir = path_to_physicell
    pcmm_globals.data_dir = path_to_data
    findCentralDB()
    #! start with PhysiCellModelManager.jl version info
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
    success = initializeDatabase()
    if !success
        pcmm_globals.db = SQLite.DB()
        println("Database initialization failed.")
        return
    end
    println(rpad("PhysiCell version:", 25, ' ') * physicellInfo())
    println(rpad("Compiler:", 25, ' ') * pcmm_globals.physicell_compiler)
    println(rpad("Running on HPC:", 25, ' ') * string(pcmm_globals.run_on_hpc))
    println(rpad("Max parallel sims:", 25, ' ') * string(pcmm_globals.max_number_of_parallel_simulations))
    flush(stdout)

    return isInitialized()
end

function initializeModelManager(path_to_project::AbstractString; kwargs...)
    path_to_physicell, path_to_data = (joinpath(path_to_project, folder) for folder in ("PhysiCell", "data"))
    return initializeModelManager(path_to_physicell, path_to_data; kwargs...)
end

initializeModelManager(; kwargs...) = initializeModelManager("PhysiCell", "data"; kwargs...)

################## Selection Functions ##################

"""
    constituentsType(T::Type{<:AbstractTrial})
    constituentsType(T::AbstractTrial)

Return the type of the constituents of `T`. Used in the [`readConstituentIDs`](@ref) function.
"""
constituentsType(::Type{Simulation}) = throw(ArgumentError("Type Simulation does not have constituents."))
constituentsType(::Type{Monad}) = Simulation
constituentsType(::Type{Sampling}) = Monad
constituentsType(::Type{Trial}) = Sampling

constituentsType(T::AbstractTrial) = constituentsType(typeof(T))

"""
    constituentsTypeFilename(T::Type{<:AbstractTrial})
    constituentsTypeFilename(T::AbstractTrial)

Return the filename of the constituents of `T`. Used in the [`readConstituentIDs`](@ref) function.
"""
constituentsTypeFilename(T) = "$(T |> constituentsType |> lowerClassString)s.csv"

"""
    readConstituentIDs(T::AbstractTrial)

Read a CSV file containing constituent IDs from `T` and return them as a vector of integers.

For a trial, this is the sampling IDs.
For a sampling, this is the monad IDs.
For a monad, this is the simulation IDs.

# Examples
```julia
ids = readConstituentIDs(Sampling(1)) # read the IDs of the monads in sampling 1
ids = readConstituentIDs(Sampling, 1) # identical to above but does not need to create the Sampling object

ids = readConstituentIDs(Monad, 1) # read the IDs of the simulations in monad 1
ids = readConstituentIDs(Trial, 1) # read the IDs of the samplings in trial 1
```
"""
function readConstituentIDs(path_to_csv::String)
    if !isfile(path_to_csv)
        return Int[]
    end
    df = CSV.read(path_to_csv, DataFrame; header=false, silencewarnings=true, types=String, delim=",")
    ids = Int[]
    for i in axes(df,1)
        s = df.Column1[i]
        I = split(s,":") .|> x->parse(Int,x)
        if length(I)==1
            push!(ids,I[1])
        else
            append!(ids,I[1]:I[2])
        end
    end
    return ids
end

readConstituentIDs(T::AbstractTrial) = readConstituentIDs(joinpath(trialFolder(T), constituentsTypeFilename(T)))
readConstituentIDs(T::Type{<:AbstractTrial}, id::Int) = readConstituentIDs(joinpath(trialFolder(T, id), constituentsTypeFilename(T)))

"""
    samplingSimulationIDs(sampling_id::Int)

Internal function to get the simulation IDs for a given sampling ID. Users should use [`simulationIDs`](@ref) instead.
"""
function samplingSimulationIDs(sampling_id::Int)
    monad_ids = readConstituentIDs(Sampling, sampling_id)
    return vcat([readConstituentIDs(Monad, monad_id) for monad_id in monad_ids]...)
end

"""
    trialSimulationIDs(trial_id::Int)

Internal function to get the simulation IDs for a given trial ID. Users should use [`simulationIDs`](@ref) instead.
"""
function trialSimulationIDs(trial_id::Int)
    sampling_ids = readConstituentIDs(Trial, trial_id)
    return vcat([samplingSimulationIDs(sampling_id) for sampling_id in sampling_ids]...)
end

"""
    simulationIDs()

Return a vector of all simulation IDs in the database.

Alternate forms take a simulation, monad, sampling, or trial object (or an array of any combination of them) and return the corresponding simulation IDs.

# Examples
```julia
simulationIDs() # all simulation IDs in the database
simulationIDs(simulation) # just a vector with the simulation ID, i.e. [simulation.id]
simulationIDs(monad) # all simulation IDs in a monad
simulationIDs(sampling) # all simulation IDs in a sampling
simulationIDs(trial) # all simulation IDs in a trial
simulationIDs([trial1, trial2]) # all simulation IDs between trial1 and trial2
```
"""
simulationIDs() = constructSelectQuery("simulations"; selection="simulation_id") |> queryToDataFrame |> x -> x.simulation_id
simulationIDs(simulation::Simulation) = [simulation.id]
simulationIDs(monad::Monad) = readConstituentIDs(monad)
simulationIDs(sampling::Sampling) = samplingSimulationIDs(sampling.id)
simulationIDs(trial::Trial) = trialSimulationIDs(trial.id)
simulationIDs(Ts::AbstractArray{<:AbstractTrial}) = reduce(vcat, simulationIDs.(Ts))

"""
    getSimulationIDs(args...)

Deprecated alias for [`simulationIDs`](@ref). Use `simulationIDs` instead.
"""
function getSimulationIDs(args...)
    Base.depwarn("`getSimulationIDs` is deprecated. Use `simulationIDs` instead.", :getSimulationIDs; force=true)
    return simulationIDs(args...)
end

"""
    trialMonads(trial_id::Int)

Internal function to get the monad IDs for a given trial ID. Users should use [`getMonadIDs`](@ref) instead.
"""
function trialMonads(trial_id::Int)
    sampling_ids = readConstituentIDs(Trial, trial_id)
    return vcat([readConstituentIDs(Sampling, sampling_id) for sampling_id in sampling_ids]...)
end

"""
    getMonadIDs()

Return a vector of all monad IDs in the database.

Alternate forms take a monad, sampling, or trial object (or an array of any combination of them) and return the corresponding monad IDs.

# Examples
```julia
getMonadIDs() # all monad IDs in the database
getMonadIDs(monad) # just a vector with the monad ID, i.e. [monad.id]
getMonadIDs(sampling) # all monad IDs in a sampling
getMonadIDs(trial) # all monad IDs in a trial
getMonadIDs([trial1, trial2]) # all monad IDs between trial1 and trial2
```
"""
getMonadIDs() = constructSelectQuery("monads"; selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
getMonadIDs(monad::Monad) = [monad.id]
getMonadIDs(sampling::Sampling) = readConstituentIDs(sampling)
getMonadIDs(trial::Trial) = trialMonads(trial.id)
getMonadIDs(Ts::AbstractArray{<:AbstractTrial}) = reduce(vcat, getMonadIDs.(Ts))

################## Miscellaneous Functions ##################

"""
    trialFolder(T::Type{<:AbstractTrial}, id::Int)

Return the path to the folder for a given subtype of [`AbstractTrial`](@ref) and ID.

# Examples
```julia
trialFolder(Simulation, 1)
# output
"abs/path/to/data/outputs/simulations/1"
```
"""
trialFolder(T::Type{<:AbstractTrial}, id::Int) = joinpath(dataDir(), "outputs", "$(lowerClassString(T))s", string(id))

"""
    trialFolder(T::Type{<:AbstractTrial})

Return the path to the folder for the [`AbstractTrial`](@ref) object, `T`.

# Examples
```julia
simulation = Simulation(1)
trialFolder(Simulation)
# output
"abs/path/to/data/outputs/simulations/1"
```
"""
trialFolder(T::AbstractTrial) = trialFolder(typeof(T), T.id)

"""
    lowerClassString(T::AbstractTrial)
    lowerClassString(T::Type{<:AbstractTrial})

Return the lowercase string representation of the type of `T`, excluding the module name. Without this, it may return, e.g., Main.PhysiCellModelManager.Sampling.

# Examples
```julia
lowerClassString(Simulation) # "simulation"
lowerClassString(Simulation(1)) # "simulation"
```
"""
function lowerClassString(T::Type{<:AbstractTrial})
    name = string(T) |> lowercase
    return split(name, ".")[end]
end

lowerClassString(T::AbstractTrial) = lowerClassString(typeof(T))

"""
    setMarchFlag(flag::String)

Set the march flag to `flag`. Used for compiling the PhysiCell code.
"""
function setMarchFlag(flag::String)
    pcmm_globals.march_flag = flag
end

"""
    setNumberOfParallelSims(n::Int)

Set the maximum number of parallel simulations to `n`.
"""
function setNumberOfParallelSims(n::Int)
    pcmm_globals.max_number_of_parallel_simulations = n
end

end