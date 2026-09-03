using Plots
using Statistics: mean

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation = Simulation(1)
out = run(simulation)
finalPopulationCount(out)

plot(Simulation(1))
plot(Sampling(1))

plotbycelltype(Simulation(1))
plotbycelltype(Sampling(1))
plotbycelltype(Sampling(1); include_cell_type_names="default")

# misc tests
out = Monad(1; n_replicates=3) |> run
mpts = PhysiCellModelManager.MonadPopulationTimeSeries(1)
plot(out)
plot(out.trial)
plot(out; include_cell_type_names="default")
plotbycelltype(out)
plotbycelltype(out.trial)

all_cell_types = ["cancer", "immune", "epi", "mes"]
PhysiCellModelManager.processIncludeCellTypes(["cancer", "immune"], all_cell_types)
PhysiCellModelManager.processIncludeCellTypes(["epi", "mes", ["epi", "mes"]], all_cell_types)
@test_throws ArgumentError PhysiCellModelManager.processIncludeCellTypes(:mes, all_cell_types)
@test_throws ArgumentError PhysiCellModelManager.processIncludeCellTypes(1, all_cell_types)

PhysiCellModelManager.processExcludeCellTypes("cancer")
@test_throws ArgumentError PhysiCellModelManager.processExcludeCellTypes(:mes)
plot(out; include_cell_type_names="default", exclude_cell_type_names="default")

plot(simulation_from_import; include_cell_type_names=[["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"]])
monad = Monad(simulation_from_import; n_replicates=2)
out = run(monad)
plot(out; include_cell_type_names=[["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"]])

@test_throws ArgumentError plot(run(Trial(1)))

plotbycelltype(simulation_from_import; include_cell_type_names="fast T cell", exclude_cell_type_names="fast T cell")

@test ismissing(PhysiCellSnapshot(pruned_simulation_id, :initial))
@test ismissing(finalPopulationCount(pruned_simulation_id))

spts = PhysiCellModelManager.SimulationPopulationTimeSeries(1)
println(stdout, spts)
println(stdout, mpts)

@test PhysiCellModelManager.formatTimeRange([78.0]) == "78.0"
@test PhysiCellModelManager.formatTimeRange([0.0, 40.0, 78.0]) == "0.0-78.0 (not equally spaced)"

#! deprecation tests
@test_warn "`include_cell_types` is deprecated as a keyword. Use `include_cell_type_names` instead." plot(out; include_cell_types="fast T cell")
@test_warn "`exclude_cell_types` is deprecated as a keyword. Use `exclude_cell_type_names` instead." plot(out; exclude_cell_types="fast T cell")

@test_warn "`include_cell_types` is deprecated as a keyword. Use `include_cell_type_names` instead." plotbycelltype(out; include_cell_types="fast T cell")
@test_warn "`exclude_cell_types` is deprecated as a keyword. Use `exclude_cell_type_names` instead." plotbycelltype(out; exclude_cell_types="fast T cell")
################## Pruned replicates are dropped, not zero-filled ##################
#
# Regression: `plotbycelltype` sized its count arrays by `length(simulationIDs(monad))` but only
# filled a column per replicate that actually loaded. A pruned replicate therefore left an all-zero
# column, and the `mean(array, dims=2)` below divided by a denominator including it -- so plotting a
# monad with one of three replicates pruned understated every curve by a third, with no error and no
# warning. The denominator is now the number of replicates that loaded, matching what
# `MonadPopulationTimeSeries` does with the same situation.

let
    out = Monad(1; n_replicates=3) |> run
    monad = out.trial
    sids = simulationIDs(monad)
    @test length(sids) == 3

    cell_type = PhysiCellModelManager.SimulationPopulationTimeSeries(first(sids); verbose=false).cell_count |> keys |> first
    per_sim = [PhysiCellModelManager.SimulationPopulationTimeSeries(s; verbose=false).cell_count[cell_type] for s in sids]

    #! Prune one replicate the way PruneOptions(prune_xml=true, prune_initial=true) would, and drop
    #! its cached summary too -- without that the time series reads the cache and nothing is missing.
    victim = last(sids)
    rm(joinpath(PhysiCellModelManager.trialFolder(Simulation, victim), "summary"); recursive=true, force=true)
    let outdir = PhysiCellModelManager.pathToOutputFolder(victim)
        for f in readdir(outdir)
            endswith(f, ".xml") && rm(joinpath(outdir, f); force=true)
        end
    end
    @test ismissing(PhysiCellModelManager.SimulationPopulationTimeSeries(victim; verbose=false))

    survivors = hcat(per_sim[1:end-1]...)
    expected = mean(survivors, dims=2) |> vec
    zero_filled = (sum(survivors, dims=2) ./ length(sids)) |> vec

    plotted = plotbycelltype(monad; include_cell_type_names=[cell_type]).series_list[1][:y]
    @test isapprox(Float64.(plotted), Float64.(expected))
    #! ...and specifically not the old behaviour. Guard against the two coinciding on flat data.
    @test !isapprox(Float64.(expected), Float64.(zero_filled))
    @test !isapprox(Float64.(plotted), Float64.(zero_filled))
end
