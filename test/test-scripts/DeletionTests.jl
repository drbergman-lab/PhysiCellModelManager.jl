filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

# make a few more sims to test deletion
out = run(Monad(1; n_replicates=3))
@test out.trial isa Monad

simulation_id = simulationIDs(out.trial)[1]

deleteSimulation(simulation_id:simulation_id)
@test !isdir(joinpath(PhysiCellModelManager.dataDir(), "outputs", "simulations", string(simulation_id)))

PhysiCellModelManager.eraseSimulationIDFromConstituents(simulationIDs(out.trial)[2])

PhysiCellModelManager.deleteMonad(1:4)
PhysiCellModelManager.deleteSampling(1)
PhysiCellModelManager.deleteTrial(1)

deleteSimulations(1:78; filters=Dict("config_id" => 2))
@test_throws ArgumentError deleteSimulations(1:78; filters=Dict("bad filter; --" => 2))

input_buffer = IOBuffer("n")
old_stdin = stdin  #! Save the original stdin
Base.stdin = input_buffer
deleteSimulationsByStatus(["Queued", "Failed"])
Base.stdin = old_stdin

deleteSimulationsByStatus(; user_check=false)

PhysiCellModelManager.deleteAllSimulations()
resetDatabase(; force_reset=true)

input_buffer = IOBuffer("y")
old_stdin = stdin  #! Save the original stdin
Base.stdin = input_buffer
resetDatabase()
Base.stdin = old_stdin

input_buffer = IOBuffer("n\nn\n")
old_stdin = stdin  #! Save the original stdin
Base.stdin = input_buffer
@test_throws ErrorException resetDatabase()
Base.stdin = old_stdin

input_buffer = IOBuffer("n\ny\n")
old_stdin = stdin  #! Save the original stdin
Base.stdin = input_buffer
resetDatabase()
Base.stdin = old_stdin