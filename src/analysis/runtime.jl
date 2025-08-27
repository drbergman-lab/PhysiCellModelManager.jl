using Dates

export simulationRuntime, simulationRuntimeIntervals

""" 
    simulationRuntime(snapshot::PhysiCellSnapshot)
    simulationRuntime(simulation::Simulation)
    simulationRuntime(pcmm_output::PCMMOutput{Simulation})
    simulationRuntime(simulation_id::Integer)

Get the runtime (in nanoseconds) to reach a given snapshot or the final snapshot of a simulation or PCMM output.

# Examples
```jldoctest
runtime = simulationRuntime(snapshot)
typeof(runtime)
# output
Nanosecond
```
```julia
using Statistics
sim_ids = 1:4
runtimes = simulationRuntime.(sim_ids)
exact_mean_runtime = mean([runtime.value for runtime in runtimes]) # in nanoseconds
mean_runtime = Nanosecond(round(exact_mean_runtime)) # rounded to nearest nanosecond
println(canonicalize(mean_runtime)) # e.g. 2 minutes, 53 seconds, 748 milliseconds, 31 microseconds
```
"""

simulationRuntime(snapshot::PhysiCellSnapshot) = snapshot.runtime
simulationRuntime(simulation::Simulation) = PhysiCellSnapshot(simulation, :final) |> simulationRuntime
simulationRuntime(simulation_id::Integer) = PhysiCellSnapshot(simulation_id, :final) |> simulationRuntime
simulationRuntime(pcmm_output::PCMMOutput{Simulation}) = pcmm_output.trial |> simulationRuntime

"""
    simulationRuntimeIntervals(sequence::PhysiCellSequence)
    simulationRuntimeIntervals(simulation::Simulation)
    simulationRuntimeIntervals(pcmm_output::PCMMOutput{Simulation})
    simulationRuntimeIntervals(simulation_id::Integer)

Get the runtime intervals of a simulation.

# Returns
A named tuple with the time and runtime vectors.
Each entry corresponds to the amount of runtime to simulate from the previous snapshot to the current snapshot.

# Examples
```julia
seq = simulationRuntimeIntervals(1)
using Plots
plot(seq.time, seq.runtime) # plot time from previous save time vs time
plot(seq.time, cumsum(seq.runtime)) # plot time vs cumulative runtime (same as plotting against the runtime values of each snapshot)
```
"""
function simulationRuntimeIntervals(sequence::PhysiCellSequence)
    time = [snapshot.time for snapshot in sequence.snapshots]
    runtime = vcat(Nanosecond(0), map(s -> simulationRuntime(s), sequence.snapshots)) |> diff
    return (; time=time, runtime=runtime)
end

function simulationRuntimeIntervals(simulation::Simulation)
    sequence = PhysiCellSequence(simulation)
    return simulationRuntimeIntervals(sequence)
end

simulationRuntimeIntervals(pcmm_output::PCMMOutput{Simulation}) = simulationRuntimeIntervals(pcmm_output.trial)
simulationRuntimeIntervals(simulation_id::Integer) = PhysiCellSequence(simulation_id) |> simulationRuntimeIntervals
