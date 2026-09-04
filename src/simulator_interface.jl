#! PhysiCellSimulator interface implementations.

#! Import ModelManager interface stubs so PCMM's method definitions
#! extend them (rather than creating new PhysiCellModelManager-local functions).
import ModelManager: simulationCommand, simulatorDir, simulatorVersionSchema,
                     simulatorVersionTableName, simulatorVersionIDName, resolveSimulatorVersionID,
                     currentSimulatorVersionID, simulatorInfo, postInitDisplay, setupMonad, setupSampling,
                     dbVersionTableName, upgradeMilestones, upgradeToMilestone,
                     postSimulationCleanup, initializeInputFolder, getInputFolderDescription,
                     shortLocationVariationID, shortVariationName

#! Bring ModelManager functions/types into scope without extending them, so we can call them from PCMM implementations when needed.
#! `postSimulationProcessing` is only referenced (for `@ref` cross-links / the default no-op); PCMM extends `postSimulationCleanup` instead.
using ModelManager: SimulationProcess, SimulationSpec, postSimulationProcessing

"""
    simulationCommand(::PhysiCellSimulator, spec::SimulationSpec)

PhysiCell implementation of [`simulationCommand`](@ref ModelManager.simulationCommand).

Return the `Cmd` that runs one PhysiCell simulation, or `nothing` if it could not be built — which
ModelManager takes to mean "record this simulation as failed and carry on with the rest". See
`prepareSimulationCommand`, which also creates the `output` subfolder the command writes into;
ModelManager creates the trial folder but not that subdirectory.

PCMM used to launch the process itself, wrapping the command in `sbatch` and redirecting
`hpc.out`/`hpc.err`. ModelManager v0.9.0 owns all of that — the local/HPC branch, the redirection,
the submission, waiting for completion, and building the [`SimulationProcess`](@ref
ModelManager.SimulationProcess). A simulator package only says what to run.

Setup (compilation, varied input folders) is always performed by
[`ModelManager.prepareTrialHierarchy`](@ref) before this function is called.
"""
simulationCommand(::PhysiCellSimulator, spec::SimulationSpec) =
    prepareSimulationCommand(spec.simulation)

"""
    simulatorDir(::PhysiCellSimulator)

Return the path to the PhysiCell source directory, as stored in `mm_globals`.
"""
simulatorDir(::PhysiCellSimulator) = physicellDir()

"""
    simulatorVersionSchema(::PhysiCellSimulator)

Return the SQL sub-schema for the `physicell_versions` table.
"""
simulatorVersionSchema(::PhysiCellSimulator) = physicellVersionsSchema()

"""
    simulatorVersionTableName(::PhysiCellSimulator)

Return `"physicell_versions"` — the name of the simulator version table in the database.
"""
simulatorVersionTableName(::PhysiCellSimulator) = "physicell_versions"

"""
    resolveSimulatorVersionID(::PhysiCellSimulator)

Resolve the current PhysiCell version against the database, inserting a row for it if
this version has not been seen before, and return its ID.
"""
resolveSimulatorVersionID(::PhysiCellSimulator) = resolvePhysiCellVersionID()

"""
    simulatorInfo(::PhysiCellSimulator)

Return a human-readable string describing the active PhysiCell version.
"""
simulatorInfo(::PhysiCellSimulator) = physicellInfo()

########################################################
############   Upgrade interface   #####################
########################################################

"""
    dbVersionTableName(::PhysiCellSimulator)

Return `"pcmm_version"` — the SQLite table that tracks the PCMM database version.
"""
dbVersionTableName(::PhysiCellSimulator) = "pcmm_version"

"""
    simulatorVersionIDName(::PhysiCellSimulator)

Return `"physicell_version_id"` — the SQL column name used by PhysiCell for the
simulator version FK in `simulations`, `monads`, and `samplings`.
"""
simulatorVersionIDName(::PhysiCellSimulator) = "physicell_version_id"

"""
    currentSimulatorVersionID(::PhysiCellSimulator)

Return the current PhysiCell version ID from the database.
"""
currentSimulatorVersionID(::PhysiCellSimulator) = currentPhysiCellVersionID()

"""
    postInitDisplay(::PhysiCellSimulator)

Print all PCMM initialization information. Called by the generic
[`ModelManager.initializeModelManager`](@ref) after the database is ready.
Overrides the ModelManager default to prepend the PCMM logo, version banner,
and PhysiCell-specific fields (simulator dir, version, compiler).
"""
function postInitDisplay(::PhysiCellSimulator)
    println(pcmmLogo())
    s = "PhysiCellModelManager.jl v$(string(pcmmVersion()))"
    println(s)
    println("-"^length(s))
    println(rpad("Path to PhysiCell:", 25, ' ') * physicellDir())
    println(rpad("Path to data:", 25, ' ') * dataDir())
    println(rpad("Path to database:", 25, ' ') * centralDB().file)
    println(rpad("Path to inputs.toml:", 25, ' ') * pathToInputsConfig())
    println(rpad("PhysiCell version:", 25, ' ') * simulatorInfo(PhysiCellSimulator()))
    println(rpad("Compiler:", 25, ' ') * simulator().compiler)
    println(rpad("Running on HPC:", 25, ' ') * string(mm_globals().run_on_hpc))
    println(rpad("Max parallel sims:", 25, ' ') * string(mm_globals().max_number_of_parallel_simulations))
end

"""
    setupMonad(::PhysiCellSimulator, M::AbstractMonad; kwargs...)

PhysiCell implementation of [`setupMonad`](@ref).

Prepares all varied input folders at the monad level. Always called after
[`setupSampling`](@ref) (which handles compilation), so no compilation is
performed here. Returns `true` unconditionally.

Accepts `AbstractMonad` so it handles both `Simulation` and `Monad` inputs.
"""
function setupMonad(::PhysiCellSimulator, M::AbstractMonad; kwargs...)
    for loc in projectLocations().varied
        prepareVariedInputFolder(loc, M)
    end
    return true
end

"""
    setupSampling(::PhysiCellSimulator, S::AbstractSampling; force_recompile::Bool=false, kwargs...)

PhysiCell implementation of [`setupSampling`](@ref).

Compiles the custom code for this sampling (once, shared across all monads with the
same `InputFolders`). Returns `true` on success, `false` if compilation fails.

Accepts `AbstractSampling` so it can be called on a `Simulation`, `Monad`, or
`Sampling` without requiring a wrapping object to be created.
"""
function setupSampling(::PhysiCellSimulator, S::AbstractSampling; force_recompile::Bool=false, kwargs...)
    return loadCustomCode(S; force_recompile=force_recompile)
end

"""
    prepareSimulationCommand(simulation::Simulation)

Internal PhysiCell function to build the `Cmd` to run a single simulation.

Setup (compilation, varied input folders) is always performed by
[`ModelManager.prepareTrialHierarchy`](@ref) before this is called. Returns `nothing`
if command construction fails (e.g. IC cell or IC ECM setup error); in that case the
caller returns a failed [`SimulationProcess`](@ref) and MM's `processSimulationTask`
updates the database.
"""
function prepareSimulationCommand(simulation::Simulation)
    path_to_simulation_output = joinpath(trialFolder(simulation), "output")
    mkpath(path_to_simulation_output)

    executable_str = pathToExecutable(simulation)
    config_str = joinpath(locationPath(:config, simulation), locationVariationsFolder(:config), "config_variation_$(simulation.variation_id[:config]).xml")
    flags = ["-o", path_to_simulation_output]
    if simulation.inputs[:ic_cell].id != -1
        try
            append!(flags, ["-i", setUpICCell(simulation)])
        catch e
            println("\nWARNING: Simulation $(simulation.id) failed to initialize the IC cell file.\n\tCause: $e\n")
            return nothing
        end
    end
    if simulation.inputs[:ic_substrate].id != -1
        append!(flags, ["-s", joinpath(locationPath(:ic_substrate, simulation), "substrates.csv")])
    end
    if simulation.inputs[:ic_ecm].id != -1
        try
            append!(flags, ["-e", setUpICECM(simulation)])
        catch e
            println("\nWARNING: Simulation $(simulation.id) failed to initialize the IC ECM file.\n\tCause: $e\n")
            return nothing
        end
    end
    if simulation.inputs[:ic_dc].id != -1
        append!(flags, ["-d", joinpath(locationPath(:ic_dc, simulation), "dcs.csv")])
    end
    if simulation.variation_id[:rulesets_collection] != -1
        path_to_rules_file = joinpath(locationPath(:rulesets_collection, simulation), locationVariationsFolder(:rulesets_collection), "rulesets_collection_variation_$(simulation.variation_id[:rulesets_collection]).xml")
        append!(flags, ["-r", path_to_rules_file])
    end
    if simulation.variation_id[:intracellular] != -1
        path_to_intracellular_file = joinpath(locationPath(:intracellular, simulation), locationVariationsFolder(:intracellular), "intracellular_variation_$(simulation.variation_id[:intracellular]).xml")
        append!(flags, ["-n", path_to_intracellular_file])
    end
    #! `dir` only, deliberately no `env`. Setting `env` was a no-op locally -- a child inherits the
    #! parent's environment anyway, including the `DYLD_LIBRARY_PATH`/`LD_LIBRARY_PATH` entry that
    #! `compilation.jl` adds for libRoadrunner -- but the two are not equivalent everywhere:
    #! Julia's `Cmd.env` *replaces* the environment while `sbatch --export` *extends* it, so a
    #! command carrying an explicit env behaves one way locally and the opposite on a cluster.
    #! ModelManager v0.9.0 refuses such a `Cmd` outright rather than run it divergently.
    return Cmd(`$executable_str $config_str $flags`; dir=physicellDir())
end

"""
    postSimulationCleanup(::PhysiCellSimulator, simulation_process::SimulationProcess; prune_options::PruneOptions=PruneOptions())

PhysiCell implementation of [`postSimulationCleanup`](@ref).

Runs as the last per-simulation step — after any user `post_processor` (see
[`run`](@ref)) has read the intact output folder. This is where PCMM does its
**destructive** work, so a `post_processor` always sees un-pruned output:
1. If successful, remove the `output.err` and `hpc.err` files.
2. If failed, augment `output.err` with the execution command for debugging.
3. Prune the simulation output according to `prune_options`.

Runs for every completed simulation regardless of success. Non-destructive work
belongs in [`postSimulationProcessing`](@ref), which runs before the callback.
"""
function postSimulationCleanup(::PhysiCellSimulator, simulation_process::SimulationProcess;
                                   prune_options::PruneOptions=PruneOptions(), kwargs...)
    #! `cmd`, not `process`. The two coincided before v0.9.0, so this used to read `process`; now
    #! `process === nothing` is also true for every SLURM job, whose work ran on a compute node and
    #! left no local process object. Testing `process` would early-return for every simulation on a
    #! cluster and silently skip everything below -- no pruning for a whole campaign, `output.err`
    #! never cleaned or annotated, and nothing reported anywhere.
    #! `isnothing(cmd)` means what `isnothing(process)` used to: nothing was ever launched.
    if isnothing(simulation_process.cmd)
        return
    end
    simulation = simulation_process.simulation
    p = simulation_process.process
    path_to_simulation_folder = trialFolder(simulation)
    path_to_err = joinpath(path_to_simulation_folder, "output.err")
    if simulation_process.success
        rm(path_to_err; force=true)
        rm(joinpath(path_to_simulation_folder, "hpc.err"); force=true)
    else
        println("\nWARNING: Simulation $(simulation.id) failed. Please check $(path_to_err) for more information.\n")
        #! On HPC, sbatch redirects the job's stderr to output.err too (ModelManager sets
        #! `--output`/`--error`), but a submission failure (bad partition, malformed script, etc.)
        #! can mean the job never ran and this file was never created.
        lines = isfile(path_to_err) ? readlines(path_to_err) :
                ["(no output.err file was found — the job likely never ran)"]
        open(path_to_err, "w+") do io
            #! `simulation_process.cmd`, not `p.cmd`: `p` is `nothing` for a SLURM job, so reaching
            #! through it threw on any failed simulation with `run_on_hpc` set, inside a hook `run()`
            #! treats as fail-fast -- one failed job took the campaign with it. It is also the better
            #! line to print, being PhysiCell's own command on both paths where `p.cmd` on HPC gave
            #! the whole `sbatch` wrapper.
            println(io, "Execution command: $(simulation_process.cmd)")
            println(io, "\n---stderr from PhysiCell---")
            for line in lines
                println(io, line)
            end
        end
    end
    pruneSimulationOutput(simulation, prune_options)
    return
end

function shortLocationVariationID(::PhysiCellSimulator, fieldname::Symbol)
    if fieldname == :config
        return :ConfigVarID
    elseif fieldname == :rulesets_collection
        return :RulesVarID
    elseif fieldname == :intracellular
        return :IntraVarID
    elseif fieldname == :ic_cell
        return :ICCellVarID
    elseif fieldname == :ic_ecm
        return :ICECMVarID
    else
        throw(ArgumentError("Got fieldname $(fieldname). However, it must be 'config', 'rulesets_collection', 'intracellular', 'ic_cell', or 'ic_ecm'."))
    end
end

function shortVariationName(::PhysiCellSimulator, location::Symbol, name::String)
    if location == :config
        return shortConfigVariationName(name)
    elseif location == :rulesets_collection
        return shortRulesetsVariationName(name)
    elseif location == :intracellular
        return shortIntracellularVariationName(name)
    elseif location == :ic_cell
        return shortICCellVariationName(name)
    elseif location == :ic_ecm
        return shortICECMVariationName(name)
    else
        throw(ArgumentError("location must be 'config', 'rulesets_collection', 'intracellular', 'ic_cell', or 'ic_ecm'."))
    end
end

"""
    getInputFolderDescription(::PhysiCellSimulator, path::AbstractString)

Return the description from `metadata.xml` inside `path`.
Called by `insertFolder` in ModelManager when registering a new input folder.
"""
getInputFolderDescription(::PhysiCellSimulator, path::String) = metadataDescription(path)

"""
    initializeInputFolder(::PhysiCellSimulator, input_folder::InputFolder)

Call `prepareBaseFile` for `input_folder` when it is first registered in the database.
"""
function initializeInputFolder(::PhysiCellSimulator, input_folder::InputFolder)
    prepareBaseFile(input_folder)
end

"""
    upgradeMilestones(::PhysiCellSimulator)

Return the sorted list of PCMM milestone versions that have associated DB migrations.
"""
upgradeMilestones(::PhysiCellSimulator) = pcmm_milestones

"""
    upgradeToMilestone(::PhysiCellSimulator, version::VersionNumber, auto_upgrade::Bool)

Dispatch to the PCMM-specific migration function for `version`.
"""
function upgradeToMilestone(::PhysiCellSimulator, version::VersionNumber, auto_upgrade::Bool)
    up_fn = get(upgrade_fns, version, nothing)
    @assert !isnothing(up_fn) "No PCMM upgrade function registered for version $(version)."
    return up_fn(auto_upgrade)
end
