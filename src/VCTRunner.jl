import Base.run

export runAbstractTrial

function prepareSimulationCommand(simulation::Simulation, monad_id::Int, do_full_setup::Bool, force_recompile::Bool)
    path_to_simulation_output = joinpath(trialFolder(simulation), "output")
    mkpath(path_to_simulation_output)

    if do_full_setup
        for loc in project_locations.varied
            prepareVariedInputFolder(loc, simulation)
        end
        success = loadCustomCode(simulation; force_recompile=force_recompile)
        if !success
            simulationFailedToRun(simulation, monad_id)
            return nothing
        end
    end

    executable_str = joinpath(locationPath(:custom_code, simulation), baseToExecutable("project")) #! path to executable
    config_str = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(simulation.variation_id[:config]).xml")
    flags = ["-o", path_to_simulation_output]
    if simulation.inputs[:ic_cell].id != -1
        try
            append!(flags, ["-i", pathToICCell(simulation)])
        catch e
            println("\nWARNING: Simulation $(simulation.id) failed to initialize the IC cell file.\n\tCause: $e\n")
            simulationFailedToRun(simulation, monad_id)
            return nothing
        end
    end
    if simulation.inputs[:ic_substrate].id != -1
        append!(flags, ["-s", joinpath(locationPath(:ic_substrate, simulation), "substrates.csv")]) #! if ic file included (id != -1), then include this in the command
    end
    if simulation.inputs[:ic_ecm].id != -1
        try
            append!(flags, ["-e", pathToICECM(simulation)]) #! if ic file included (id != -1), then include this in the command
        catch e
            println("\nWARNING: Simulation $(simulation.id) failed to initialize the IC ECM file.\n\tCause: $e\n")
            simulationFailedToRun(simulation, monad_id)
            return nothing
        end
    end
    if simulation.inputs[:ic_dc].id != -1
        append!(flags, ["-d", joinpath(locationPath(:ic_dc, simulation), "dcs.csv")]) #! if ic file included (id != -1), then include this in the command
    end
    if simulation.variation_id[:rulesets_collection] != -1
        path_to_rules_file = joinpath(locationPath(:rulesets_collection, simulation), "rulesets_collection_variations", "rulesets_collection_variation_$(simulation.variation_id[:rulesets_collection]).xml")
        append!(flags, ["-r", path_to_rules_file])
    end
    if simulation.variation_id[:intracellular] != -1
        path_to_intracellular_file = joinpath(locationPath(:intracellular, simulation), "intracellular_variations", "intracellular_variation_$(simulation.variation_id[:intracellular]).xml")
        append!(flags, ["-n", path_to_intracellular_file])
    end
    return Cmd(`$executable_str $config_str $flags`; env=ENV, dir=physicell_dir)
end

function simulationFailedToRun(simulation::Simulation, monad_id::Int)
    DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Failed")) WHERE simulation_id=$(simulation.id);" )
    eraseSimulationID(simulation.id; monad_id=monad_id)
    return
end

struct SimulationProcess
    simulation::Simulation
    monad_id::Int
    process::Union{Nothing,Base.Process}
end

function SimulationProcess(simulation::Simulation; monad_id::Union{Missing,Int}=missing, do_full_setup::Bool=true, force_recompile::Bool=false)
    if ismissing(monad_id)
        monad = Monad(simulation)
        monad_id = monad.id
    end

    cmd = prepareSimulationCommand(simulation, monad_id, do_full_setup, force_recompile)
    if isnothing(cmd)
        return SimulationProcess(simulation, monad_id, nothing)
    end

    path_to_simulation_folder = trialFolder("simulation", simulation.id)
    DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Running")) WHERE simulation_id=$(simulation.id);" )
    println("\tRunning simulation: $(simulation.id)...")
    flush(stdout)
    if run_on_hpc
        cmd = prepareHPCCommand(cmd, simulation.id)
        p = run(pipeline(ignorestatus(cmd); stdout=joinpath(path_to_simulation_folder, "hpc.out"), stderr=joinpath(path_to_simulation_folder, "hpc.err")); wait=true)
    else
        p = run(pipeline(ignorestatus(cmd); stdout=joinpath(path_to_simulation_folder, "output.log"), stderr=joinpath(path_to_simulation_folder, "output.err")); wait=true)
    end
    return SimulationProcess(simulation, monad_id, p)
end

function prepCmdForWrap(cmd::Cmd)
    cmd = string(cmd)
    cmd = strip(cmd, '`')
    return cmd
end

function prepareHPCCommand(cmd::Cmd, simulation_id::Int)
    path_to_simulation_folder = trialFolder("simulation", simulation_id)
    base_cmd_str = "sbatch"
    flags = ["--wrap=$(prepCmdForWrap(Cmd(cmd.exec)))",
             "--wait",
             "--output=$(joinpath(path_to_simulation_folder, "output.log"))",
             "--error=$(joinpath(path_to_simulation_folder, "output.err"))",
             "--chdir=$(physicell_dir)"
            ]
    for (k, v) in sbatch_options
        if k in ["wrap", "output", "error", "wait", "chdir"]
            println("WARNING: The key $k is reserved for pcvct to set in the sbatch command. Skipping this key.")
            continue
        end
        if typeof(v) <: Function
            v = v(simulation_id)
        end
        #! check if v has any spaces
        if occursin(" ", v)
            v = "\"$v\""
        end
        push!(flags, "--$k=$v")
    end
    return `$base_cmd_str $flags`
end

function resolveSimulation(simulation_process::SimulationProcess, prune_options::PruneOptions)
    simulation = simulation_process.simulation
    monad_id = simulation_process.monad_id
    p = simulation_process.process
    success = p.exitcode == 0
    path_to_simulation_folder = trialFolder(simulation)
    path_to_err = joinpath(path_to_simulation_folder, "output.err")
    if success
        rm(path_to_err; force=true)
        rm(joinpath(path_to_simulation_folder, "hpc.err"); force=true)
        DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Completed")) WHERE simulation_id=$(simulation.id);" )
    else
        println("\nWARNING: Simulation $(simulation.id) failed. Please check $(path_to_err) for more information.\n")
        #! write the execution command to output.err
        lines = readlines(path_to_err)
        open(path_to_err, "w+") do io
            #! read the lines of the output.err file
            println(io, "Execution command: $(p.cmd)")
            println(io, "\n---stderr from PhysiCell---")
            for line in lines
                println(io, line)
            end
        end
        DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Failed")) WHERE simulation_id=$(simulation.id);" )
        eraseSimulationID(simulation.id; monad_id=monad_id)
    end

    pruneSimulationOutput(simulation; prune_options=prune_options)
    return success
end

function runMonad(monad::Monad; do_full_setup::Bool=true, force_recompile::Bool=false)
    mkpath(trialFolder(monad))

    if do_full_setup
        compilation_success = loadCustomCode(monad; force_recompile=force_recompile)
        if !compilation_success
            return Task[] #! do not delete simulations or the monad as these could have succeeded in the past (or on other nodes, etc.)
        end
    end

    for loc in project_locations.varied
        prepareVariedInputFolder(loc, monad)
    end

    simulation_tasks = Task[]
    for simulation_id in getSimulationIDs(monad)
        if isStarted(simulation_id; new_status_code="Queued")
            continue #! if the simulation has already been started (or even completed), then don't run it again
        end
        simulation = Simulation(simulation_id)

        push!(simulation_tasks, @task SimulationProcess(simulation; monad_id=monad.id, do_full_setup=false, force_recompile=false))
    end

    return simulation_tasks
end

function runSampling(sampling::Sampling; force_recompile::Bool=false)
    mkpath(trialFolder(sampling))

    compilation_success = loadCustomCode(sampling; force_recompile=force_recompile)
    if !compilation_success
        return Task[] #! do not delete simulations, monads, or the sampling as these could have succeeded in the past (or on other nodes, etc.)
    end

    simulation_tasks = []
    for monad in Monad.(readSamplingMonadIDs(sampling))
        append!(simulation_tasks, runMonad(monad, do_full_setup=false, force_recompile=false)) #! run the monad and add the number of new simulations to the total
    end

    return simulation_tasks
end

function runTrial(trial::Trial; force_recompile::Bool=false)
    mkpath(trialFolder(trial))

    simulation_tasks = []
    for sampling_id in readTrialSamplingIDs(trial)
        sampling = Sampling(sampling_id) #! instantiate a sampling with the variation_ids and the simulation ids already found
        append!(simulation_tasks, runSampling(sampling; force_recompile=force_recompile)) #! run the sampling and add the number of new simulations to the total
    end

    return simulation_tasks
end

collectSimulationTasks(simulation::Simulation; force_recompile::Bool=false) = 
    isStarted(simulation; new_status_code="Queued") ? Task[] : [@task SimulationProcess(simulation; do_full_setup=true, force_recompile=force_recompile)]
collectSimulationTasks(monad::Monad; force_recompile::Bool=false) = runMonad(monad; do_full_setup=true, force_recompile=force_recompile)
collectSimulationTasks(sampling::Sampling; force_recompile::Bool=false) = runSampling(sampling; force_recompile=force_recompile)
collectSimulationTasks(trial::Trial; force_recompile::Bool=false) = runTrial(trial; force_recompile=force_recompile)

"""
    collectSimulationTasks(T::AbstractTrial[; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()])

Collect the simulation tasks for the given trial, sampling, monad, or simulation.

Used by `run` to collect the tasks to run.

See also [`run`](@ref).
"""
function collectSimulationTasks(T::AbstractTrial; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions=PruneOptions()) end

struct PCVCTOutput
    trial::AbstractTrial
    n_scheduled::Int
    n_success::Int
end

getSimulationIDs(output::PCVCTOutput) = getSimulationIDs(output.trial)

"""
    run(T::AbstractTrial[; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()])`

Run the given simulation, monad, sampling, or trial.

Call the appropriate functions to run the simulations and return the number of successful simulations.
Also print out messages to the console to inform the user about the progress and results of the simulations.

# Arguments
- `T::AbstractTrial`: The trial, sampling, monad, or simulation to run.
- `force_recompile::Bool=false`: If `true`, forces a recompilation of all files by removing all `.o` files in the PhysiCell directory.
- `prune_options::PruneOptions=PruneOptions()`: Options for pruning simulations.
"""
function run(T::AbstractTrial; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())
    simulation_tasks = collectSimulationTasks(T; force_recompile=force_recompile)
    n_simulation_tasks = length(simulation_tasks)
    n_success = 0

    println("Running $(typeof(T)) $(T.id) requiring $(n_simulation_tasks) simulations...")

    num_parallel_sims = run_on_hpc ? n_simulation_tasks : max_number_of_parallel_simulations
    queue_channel = Channel{Task}(n_simulation_tasks)
    result_channel = Channel{Bool}(n_simulation_tasks)
    @async for simulation_task in simulation_tasks
        put!(queue_channel, simulation_task) #! if the queue_channel is full, this will block until there is space
    end

    for _ in 1:num_parallel_sims #! start one task per allowed num of parallel sims
        @async for simulation_task in queue_channel #! do not let the creation of this task block the creation of the other tasks
            #! once the simulation_task is processed, put it in the result_channel and move on to the next simulation_task in the queue_channel
            put!(result_channel, processSimulationTask(simulation_task, prune_options))
        end
    end

    #! this code block effectively blocks the main thread until all the simulation_tasks have been processed
    for _ in 1:n_simulation_tasks #! take exactly the number of expected outputs
        success = take!(result_channel) #! wait until the result_channel has a value to take
        n_success += success
    end

    n_asterisks = 1
    asterisks = Dict{String, Int}()
    size_T = length(T)
    println("Finished $(typeof(T)) $(T.id).")
    println("\t- Consists of $(size_T) simulations.")
    print(  "\t- Scheduled $(n_simulation_tasks) simulations to complete this $(typeof(T)).")
    print_low_schedule_message = n_simulation_tasks < size_T
    if print_low_schedule_message
        println(" ($(repeat("*", n_asterisks)))")
        asterisks["low_schedule_message"] = n_asterisks
        n_asterisks += 1
    else
        println()
    end
    print(  "\t- Successful completion of $(n_success) simulations.")
    print_low_success_warning = n_success < n_simulation_tasks
    if print_low_success_warning
        println(" ($(repeat("*", n_asterisks)))")
        asterisks["low_success_warning"] = n_asterisks
        n_asterisks += 1 #! in case something gets added later
    else
        println()
    end
    if print_low_schedule_message
        println("\n($(repeat("*", asterisks["low_schedule_message"]))) pcvct found matching simulations and will save you time by not re-running them!")
    end
    if print_low_success_warning
        println("\n($(repeat("*", asterisks["low_success_warning"]))) Some simulations did not complete successfully. Check the output.err files for more information.")
    end
    println("\n--------------------------------------------------\n")
    return PCVCTOutput(T, n_simulation_tasks, n_success)
end

"""
    runAbstractTrial(T::AbstractTrial; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())

Alias for [`run`](@ref), but only with this particular signature. Does not work on `Cmd` objects as `Base.run` is built for.
Also, does not work with `run`ning sensitivity samplings.
"""
function runAbstractTrial(T::AbstractTrial; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()) 
    Base.depwarn("`runAbstractTrial` is deprecated. Use `run` instead.", :runAbstractTrial; force=true)
    return run(T; force_recompile=force_recompile, prune_options=prune_options)
end

function processSimulationTask(simulation_task, prune_options)
    schedule(simulation_task)
    simulation_process = fetch(simulation_task)
    if isnothing(simulation_process.process)
        return false
    end
    return resolveSimulation(simulation_process, prune_options)
end