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

################## The cell type roster survives a pruned FIRST replicate ##################
#
# Regression: the fix above corrected the denominator but not the roster. `plotbycelltype` still
# read its cell types from `simulationIDs(T) |> first`, and `cellTypeToNameDict` reads back an empty
# `Dict` for a simulation whose initial XML is gone -- so pruning *that* replicate left `:all`
# expanding to no cell types at all, a `(0, 1)` layout, and an empty figure with nothing said.
# Which replicate was pruned decided whether plotting worked; the test above prunes the last, so it
# never saw this.
#
# The initial XML is stashed and put back rather than deleted: simulation 1 is monad 1's first
# replicate, and GraphsTests.jl and PCFTests.jl read its snapshots later in the run.

let
    out = Monad(1; n_replicates=3) |> run
    monad = out.trial
    sids = simulationIDs(monad)

    #! The roster the monad ought to report, read from a replicate that still has its initial XML.
    i_surviving = findfirst(sid -> !isempty(PhysiCellModelManager.cellTypeToNameDict(sid)), sids)
    @test !isnothing(i_surviving)
    roster = PhysiCellModelManager.cellTypeToNameDict(sids[i_surviving]) |> values |> collect
    @test !isempty(roster)

    #! Naming the roster explicitly never consults `cellTypeToNameDict`, so this is the panel count
    #! an intact monad plots: one series per cell type per monad.
    expected_n_series = plotbycelltype(monad; include_cell_type_names=roster).series_list |> length
    @test expected_n_series == length(roster)

    #! Take the initial XML off the FIRST replicate -- the one the roster came from unconditionally.
    #! A real prune leaves `summary/population_time_series.csv` behind, so this replicate still
    #! contributes its counts; only the roster lookup goes missing, which is the reported bug.
    victim = first(sids)
    path_to_initial_xml = PhysiCellModelManager.pathToOutputXML(victim, :initial)
    @test isfile(path_to_initial_xml)
    path_to_stash = path_to_initial_xml * ".stashed"
    mv(path_to_initial_xml, path_to_stash)
    try
        @test isempty(PhysiCellModelManager.cellTypeToNameDict(victim))

        plt = plotbycelltype(monad)
        @test length(plt.series_list) == expected_n_series
        @test !isempty(plt.series_list) #! ...and specifically not the old empty figure.
    finally
        mv(path_to_stash, path_to_initial_xml)
    end

    #! Every replicate gone is a different thing from one replicate gone, and says so rather than
    #! drawing nothing. `pruned_simulation_id` (PrunerTests.jl) has no initial XML at all.
    @test_throws ArgumentError PhysiCellModelManager._samplingCellTypeRoster(Simulation(pruned_simulation_id))

    #! A Trial gathers samplings whose configs, and so rosters, may differ, so the recipe refuses it
    #! and says what to pass instead (ClassesTests.jl created Trial 1).
    @test_throws ArgumentError plotbycelltype(Trial(1))
end
