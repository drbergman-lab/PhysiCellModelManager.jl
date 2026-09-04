using DataFrames

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
qoi_inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)
qoi_discrete_variations = [DiscreteVariation(configPath("max_time"), 12.0)]

#! a plain, un-pruned simulation to probe the returned closure directly
qoi_simulation = createTrial(qoi_inputs, qoi_discrete_variations; use_previous=false)
qoi_out = run(qoi_simulation; force_recompile=false)
@test qoi_out.n_success == 1
qoi_sim_id = PhysiCellModelManager.trialID(qoi_out)
#! A `Simulation`, not a `SimulationProcess`. Since ModelManager #46 that is what `run` hands a
#! `post_processor`, and probing the closure with anything else tests a contract that no longer
#! exists. This test passed against a `SimulationProcess` only because the closure was untyped --
#! precisely the silent divergence MM's migration warning was added for.
qoi_sim = Simulation(qoi_sim_id)

#! default (:final) matches finalPopulationCount
@test populationCountQoI()(qoi_sim) == Dict("count_$(k)" => v for (k, v) in finalPopulationCount(qoi_sim_id))

#! integer index matches populationCount at that snapshot
snapshot0 = PhysiCellSnapshot(qoi_sim_id, 0; include_cells=true)
@test populationCountQoI(; index=0)(qoi_sim) == Dict("count_$(k)" => v for (k, v) in populationCount(snapshot0))

#! cell_types filter
@test populationCountQoI(; cell_types=["default"])(qoi_sim) == populationCountQoI()(qoi_sim)
@test populationCountQoI(; cell_types=["nonexistent_type"])(qoi_sim) == Dict{String,Int}()

#! include_dead just needs to run without erroring and return a Dict
@test populationCountQoI(; include_dead=true)(qoi_sim) isa Dict

#! missing snapshot (pruned) -> nothing, not an error
@test isnothing(populationCountQoI(; index=:initial)(Simulation(pruned_simulation_id)))

#! full integration: run(...; post_processor=populationCountQoI()) populates the sink
qoi_simulation2 = createTrial(qoi_inputs, qoi_discrete_variations; use_previous=false)
qoi_out2 = run(qoi_simulation2; force_recompile=false, post_processor=populationCountQoI())
@test qoi_out2.n_success == 1
qoi_sim_id2 = PhysiCellModelManager.trialID(qoi_out2)
df = postProcessingTable(qoi_out2.trial)
@test size(df, 1) == 1
@test df.SimID[1] == qoi_sim_id2
expected2 = finalPopulationCount(qoi_sim_id2)
for (cell_type, count) in expected2
    @test df[1, "count_$(cell_type)"] == count
end
