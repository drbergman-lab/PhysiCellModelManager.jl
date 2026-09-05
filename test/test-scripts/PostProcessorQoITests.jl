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
#! `post_processor`, and probing with anything else tests a contract that no longer exists. This
#! test passed against a `SimulationProcess` only because the closure was untyped -- precisely the
#! silent divergence MM's migration warning was added for.
qoi_sim = Simulation(qoi_sim_id)

#! `populationCountQoI` returns a `QoI` now, so its measurement is reached through `compute`. It is
#! one QoI covering every cell type: the types come from the simulation's own output, so they are not
#! known at construction, and ModelManager expands a `Dict` return into one sink column per key,
#! named `"<qoi name>.<key>"` since 0.9.1. The keys here are therefore bare cell type names.
@test populationCountQoI() isa QoI
@test populationCountQoI().name == "population_count"
measure(q) = q.compute(qoi_sim)

#! default (:final) matches finalPopulationCount
@test measure(populationCountQoI()) == finalPopulationCount(qoi_sim_id)

#! integer index matches populationCount at that snapshot
snapshot0 = PhysiCellSnapshot(qoi_sim_id, 0; include_cells=true)
@test measure(populationCountQoI(; index=0)) == populationCount(snapshot0)

#! cell_types filter
@test measure(populationCountQoI(; cell_types=["default"])) == measure(populationCountQoI())
@test measure(populationCountQoI(; cell_types=["nonexistent_type"])) == Dict{String,Int}()

#! include_dead just needs to run without erroring and return a Dict
@test measure(populationCountQoI(; include_dead=true)) isa Dict

#! missing snapshot (pruned) -> nothing, not an error
@test isnothing(populationCountQoI(; index=:initial).compute(Simulation(pruned_simulation_id)))

#! full integration: run(...; post_processor=populationCountQoI()) populates the sink
qoi_simulation2 = createTrial(qoi_inputs, qoi_discrete_variations; use_previous=false)
qoi_out2 = run(qoi_simulation2; force_recompile=false, post_processor=populationCountQoI())
@test qoi_out2.n_success == 1
qoi_sim_id2 = PhysiCellModelManager.trialID(qoi_out2)
df = postProcessingTable(qoi_out2.trial)
@test size(df, 1) == 1
@test df.SimID[1] == qoi_sim_id2
#! The sink namespaces a spread column by the QoI that wrote it, so the column is
#! `population_count.<cell_type>` -- not the bare key, and not the `count_` prefix the builder
#! carried before ModelManager 0.9.1 supplied a namespace of its own.
expected2 = finalPopulationCount(qoi_sim_id2)
for (cell_type, count) in expected2
    @test df[1, "population_count.$(cell_type)"] == count
end
@test !("count_default" in names(df))
