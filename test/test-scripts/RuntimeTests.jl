using Dates

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation = Simulation(1)
out = run(simulation)

#! runtime
runtime1 = simulationRuntime(simulation)
runtime2 = simulationRuntime(1)
runtime3 = simulationRuntime(out)

@test typeof(runtime1) == Nanosecond
@test runtime1 == runtime2
@test runtime1 == runtime3

#! runtime intervals
intervals1 = PhysiCellModelManager.simulationRuntimeIntervals(simulation)
intervals2 = PhysiCellModelManager.simulationRuntimeIntervals(1)
intervals3 = PhysiCellModelManager.simulationRuntimeIntervals(out)

@test length(intervals1.time) == length(intervals1.runtime)
@test intervals1.runtime == intervals2.runtime
@test intervals1.runtime == intervals3.runtime
