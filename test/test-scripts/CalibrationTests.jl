using DataFrames, Distributions, Statistics

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

cell_type = "default"
config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

# Short fixed-parameter reference (max_time=12, fast save intervals)
dv_max_time = DiscreteVariation(configPath("max_time"), 12.0)
dv_full_data = DiscreteVariation(configPath("full_data"), 6.0)
dv_svg = DiscreteVariation(configPath("svg_save"), 6.0)
ref = createTrial(inputs, [dv_max_time, dv_full_data, dv_svg]; n_replicates=1)
run(ref)  # run the reference monad so it has a folder (avoids orphan DB entries that databaseDiagnostics flags)

xml_path_phase = PhysiCellModelManager.cyclePath(cell_type, "phase_durations", "duration:index:0")

################## Type Construction Tests ##################

@testset "DistributedVariation construction (calibration parameter)" begin
    dv = DistributedVariation(xml_path_phase, Uniform(200.0, 400.0); name="phase_dur")
    @test variationName(dv) == "phase_dur"
    @test dv.distribution isa Uniform
end

@testset "CalibrationProblem construction" begin
    observed = Dict("default" => 100.0)
    dv = DistributedVariation(xml_path_phase, Uniform(200.0, 400.0); name="phase_dur")

    #! The monad-level statistics are no longer valid `summary_statistic` arguments: since #46 a
    #! measurement function receives a `Simulation`, and these take a monad ID. The QoI builders are
    #! the replacement for that role; the monad-level functions remain monad-level analysis.
    prob = CalibrationProblem(inputs, [dv], observed, populationCountQoI(), mseDistance)
    @test prob.n_replicates == 1
    @test prob.reference_variation_id == PhysiCellModelManager.VariationID(inputs)

    prob_with_ref = CalibrationProblem(inputs, [dv], observed, populationCountQoI(), mseDistance;
        n_replicates=3, reference_variation_id=ref.variation_id)
    @test prob_with_ref.n_replicates == 3
    @test !ismissing(prob_with_ref.reference_variation_id)
end

################## DB / Folder Tests ##################

@testset "createCalibration" begin
    calibration = ModelManager.createCalibration("ABC-SMC"; description="test calibration")
    @test calibration isa Calibration
    @test calibration.id isa Int

    folder = ModelManager.calibrationFolder(calibration)
    @test isdir(folder)

    # no per-generation monad files exist yet (no particles evaluated)
    @test isempty(ModelManager.calibrationMonadIDs(calibration))

    # calibrations table has this entry
    query = PhysiCellModelManager.constructSelectQuery(
        "calibrations", "WHERE calibration_id=$(calibration.id)")
    df = PhysiCellModelManager.queryToDataFrame(query)
    @test nrow(df) == 1
    @test df.method[1] == "ABC-SMC"
    @test df.description[1] == "test calibration"
end

################## Built-in Summary Statistic Tests ##################
# Monad 1 was created by earlier tests (RunnerTests.jl); use it here.

@testset "finalPopulationCount(Monad)" begin
    counts = finalPopulationCount(Monad(1))
    @test counts isa Dict{String,Float64}
    @test haskey(counts, cell_type)
    @test all(v >= 0.0 for v in values(counts))
end

################## QoI-returning builders ##################
#
# These assert what each builder's value IS, computed from the replicates' own output rather than
# compared against a second implementation. The monad-level statistics these used to be checked
# against are gone (#232): under the default reducer each was its builder's value computed a second
# way, so the comparison had stopped testing anything but float summation order. Tolerances stay
# `≈`: the builders reduce through ModelManager's default per-key mean, which need not sum in the
# same order as a mean written here.

#! The builders carry their keyword arguments in `data`, which selects the two-argument calling
#! convention ModelManager uses for them: `compute(sim, data)` and `reduce(values, data)`.
computeOn(q, sim) = q.compute(sim, q.data)
reduceWith(q, values) = q.reduce(values, q.data)

#! ModelManager's own seam -- compute per replicate, drop the `missing` ones, reduce -- which is the
#! path calibration and sensitivity analysis take, and so the path these equalities are about.
#! Internal, but the alternative is re-implementing it here and asserting against a copy.
evaluate(q, monad_id) = PhysiCellModelManager.ModelManager._reduceOverMonad(q, monad_id)

@testset "QoI builder reducers" begin
    counts_q = populationCountQoI()
    fracs_q = populationFractionQoI()

    # Restorable by name: the keywords ride in `data` and both functions are top-level, so a
    # `problem.jld2` written from any builder is complete. Asked of ModelManager's own predicate,
    # the one `_saveProblem` consults; the bare `resumeABC` further down is the end-to-end form.
    for q in (counts_q, fracs_q, meanPopulationTimeSeriesQoI())
        @test !PhysiCellModelManager.ModelManager._isAnonymousFunction(q)
    end

    # Missing replicates never reach `reduce`: ModelManager drops them first (`skip_missing`, the
    # `QoI` default, which the builders keep) and reduces a monad with nothing readable to `missing`
    # itself -- reachable on ordinary data, because pruning makes a replicate unreadable. The
    # pruned-replicate path is exercised end to end further down.
    @test counts_q.skip_missing && fracs_q.skip_missing
    # No builder carries a `reduce` of its own any more (#232), so `q.reduce` here IS ModelManager's
    # default per-key mean, reached through the two-argument convention `data` selects.
    @test reduceWith(counts_q, [Dict("a" => 1), Dict("a" => 3)]) == Dict("a" => 2.0)
    @test reduceWith(fracs_q, [Dict("a" => 0.25), Dict("a" => 0.75)]) == Dict("a" => 0.5)

    # Two things used to be pinned here and are deliberately gone, because the code they described
    # is deleted rather than merely changed. One was the counts reducer's union-of-keys zero-fill
    # of a cell type absent from a replicate; nothing zero-fills now, and nothing needs to -- the
    # default reducer's one rule is that replicates agree about their keys, and they do by
    # construction, since `populationCount` keys every cell type the model declares and a monad's
    # replicates share a config. The other was the float-associativity gap between the two bespoke
    # reducers' accumulations (1200 copies of 0.1), pinned to prove they were genuinely different
    # functions.
    # There is one reducer now, so there is no gap between builders to pin; the testset below
    # asserts each builder's value against the replicates' own output instead.
end

@testset "QoI builder values" begin
    # Evaluate each QoI the way ModelManager does -- `reduce` over `compute` for every replicate --
    # using only the QoI's own documented parts. An earlier version of this test called
    # `ModelManager._asSummaryStatistic`, which was renamed to `_validateSummaryStatistic` in #46 and
    # took the test with it. Pinning another package's internals is the same mistake as pinning its
    # on-disk layout: the flat-vs-nested dict shape is ModelManager's contract to keep, not ours.

    # A monad of this test's own, distinguished by a phase duration nothing else uses. PCMM reuses
    # matching simulations, so pruning a replicate of a monad another file also builds -- Monad(1)
    # with three replicates, which PopulationTests does -- would hand that file a replicate whose
    # output is already gone.
    probe = createTrial(inputs, [dv_max_time, dv_full_data, dv_svg,
                                 DiscreteVariation(xml_path_phase, 321.0)]; n_replicates=3)
    run(probe)
    monad_id = probe.id
    sids = simulationIDs(probe)
    @test length(sids) == 3

    #! `cell_types` has to be applied by `compute`, not only by `reduce`: the post-processing sink
    #! calls `compute` and never `reduce`, so a builder that filtered in its reducer alone would
    #! write a column for every cell type and silently ignore the argument.
    #! The fraction builder did exactly that once. A nonexistent type is what discriminates here --
    #! this model defines one cell type, so filtering *to* it cannot tell the two apart.
    for builder in (populationCountQoI, populationFractionQoI)
        @test isempty(computeOn(builder(; cell_types=["nonexistent_type"]), Simulation(first(sids))))
        @test haskey(computeOn(builder(; cell_types=[cell_type]), Simulation(first(sids))), cell_type)
    end
    #! The fraction denominator stays the whole population, so restricting does not renormalise: a
    #! single-cell-type model still reads 1.0 whether or not the filter is applied.
    @test computeOn(populationFractionQoI(; cell_types=[cell_type]), Simulation(first(sids)))[cell_type] ==
          computeOn(populationFractionQoI(), Simulation(first(sids)))[cell_type]
    #! ...and every replicate's fractions sum to 1 over the whole roster.
    for sid in sids
        @test sum(values(computeOn(populationFractionQoI(), Simulation(sid)))) ≈ 1.0 atol=1e-10
    end

    #! Each builder's reduced value, against the replicates' own output. Flat and keyed by cell type
    #! -- not nested -- and, with no `cell_types`, discovered from the output rather than named at
    #! construction, which is the thing the previous `Vector{QoI}` shape could not do.
    countsOfReplicates(ids) = [finalPopulationCount(Simulation(sid))[cell_type] for sid in ids]
    seriesOfReplicates(ids) =
        [PhysiCellModelManager.SimulationPopulationTimeSeries(sid; verbose=false).cell_count[cell_type]
         for sid in ids]

    via_counts = evaluate(populationCountQoI(; cell_types=[cell_type]), monad_id)
    @test collect(keys(via_counts)) == [cell_type]
    @test via_counts[cell_type] ≈ mean(countsOfReplicates(sids))
    @test haskey(evaluate(populationCountQoI(), monad_id), cell_type)

    via_fracs = evaluate(populationFractionQoI(; cell_types=[cell_type]), monad_id)
    @test collect(keys(via_fracs)) == [cell_type]
    @test 0.0 <= via_fracs[cell_type] <= 1.0
    @test sum(values(evaluate(populationFractionQoI(), monad_id))) ≈ 1.0 atol=1e-10

    via_series = evaluate(meanPopulationTimeSeriesQoI(; cell_types=[cell_type]), monad_id)
    @test collect(keys(via_series)) == [cell_type]
    @test via_series[cell_type] ≈ mean(seriesOfReplicates(sids))

    # Now prune one replicate and assert the equality survives the path that actually differs.
    # A clean monad agrees under any reducer and proves nothing.
    victim = last(sids)
    rm(joinpath(PhysiCellModelManager.trialFolder(Simulation, victim), "summary"); recursive=true, force=true)
    let outdir = PhysiCellModelManager.pathToOutputFolder(victim)
        for f in readdir(outdir)
            endswith(f, ".xml") && rm(joinpath(outdir, f); force=true)
        end
    end
    @test ismissing(PhysiCellModelManager.SimulationPopulationTimeSeries(victim; verbose=false))
    @test ismissing(finalPopulationCount(victim))

    #! The pruned replicate is dropped rather than zero-filled: each builder now averages the two
    #! that are still readable, and nothing throws.
    kept = filter(!=(victim), sids)
    @test evaluate(populationCountQoI(; cell_types=[cell_type]), monad_id)[cell_type] ≈
          mean(countsOfReplicates(kept))
    @test evaluate(meanPopulationTimeSeriesQoI(; cell_types=[cell_type]), monad_id)[cell_type] ≈
          mean(seriesOfReplicates(kept))
    @test sum(values(evaluate(populationFractionQoI(), monad_id))) ≈ 1.0 atol=1e-10
end

################## ABC-SMC End-to-End Test (with PhysiCell) ##################
# Uses the actual PhysiCell simulator with a tiny population/generation budget.

@testset "runABC end-to-end" begin
    observed = Dict(cell_type => finalPopulationCount(Monad(1))[cell_type])
    params = [DistributedVariation(xml_path_phase, Uniform(200.0, 400.0); name="phase_dur")]
    problem = CalibrationProblem(
        inputs, params, observed,
        populationCountQoI(), mseDistance;
        reference_variation_id=ref.variation_id
    )

    result = runABC(problem;
        population_size=3,
        max_nr_populations=2,
        minimum_epsilon=0.0,
        description="test ABC run"
    )

    @test result isa ABCResult
    @test result.calibration isa Calibration
    @test isdir(ModelManager.calibrationFolder(result.calibration))
    @test !isempty(result.generations)
    @test result.method isa ABCSMC

    monad_ids = ModelManager.calibrationMonadIDs(result.calibration)
    @test !isempty(monad_ids)

    # DB entry created
    query = PhysiCellModelManager.constructSelectQuery(
        "calibrations", "WHERE calibration_id=$(result.calibration.id)")
    df = PhysiCellModelManager.queryToDataFrame(query)
    @test nrow(df) == 1
    @test df.description[1] == "test ABC run"

    # posterior extraction
    post_df, weights = posterior(result)
    @test post_df isa DataFrame
    @test "phase_dur" in names(post_df)
    @test length(weights) == nrow(post_df)
    @test sum(weights) ≈ 1.0 atol=1e-6

    # Specific generation access
    post_df1, _ = posterior(result; generation=1)
    @test post_df1 isa DataFrame
    post_df_final, _ = posterior(result; generation=:final)
    @test nrow(post_df_final) == nrow(post_df)

    # Out-of-range generation throws
    @test_throws ArgumentError posterior(result; generation=99)

    # Generation artifacts saved to disk. Deliberately layout-agnostic: ModelManager moved from a
    # flat `generation_<t>.csv` to a folder per generation (and still reads both), so pinning a
    # filename here pins ModelManager's internal layout from PCMM's test suite. That generation 1
    # was persisted *and* is readable is already asserted above, via `posterior(result; generation=1)`.
    gen_dir = joinpath(ModelManager.calibrationFolder(result.calibration), "generations")
    @test isdir(gen_dir)
    @test !isempty(readdir(gen_dir))
end

@testset "resumeABC" begin
    # Run a short calibration, then resume with more generations
    observed = Dict(cell_type => finalPopulationCount(Monad(1))[cell_type])
    params = [DistributedVariation(xml_path_phase, Uniform(200.0, 400.0); name="phase_dur")]
    problem = CalibrationProblem(
        inputs, params, observed,
        populationCountQoI(), mseDistance;
        reference_variation_id=ref.variation_id
    )

    # Initial run: 1 generation, tiny population
    method_initial = ABCSMC(population_size=3, max_nr_populations=1, minimum_epsilon=0.0)
    #! ModelManager takes the method first: `runCalibration(::ABCSMC, ::CalibrationProblem; ...)`.
    result1 = runCalibration(method_initial, problem; description="resume test")
    @test length(result1.generations) == 1

    # Resume with a method that allows 2 more generations. No `problem=`: the builder's functions
    # are named and its keywords ride in `data`, so `problem.jld2` restores the problem by itself.
    method_continue = ABCSMC(population_size=3, max_nr_populations=3, minimum_epsilon=0.0)
    result2 = resumeABC(result1.calibration; method=method_continue)
    @test length(result2.generations) > 1
    @test result2.calibration.id == result1.calibration.id

    # First generation particles should be preserved across resume
    @test result2.generations[1].particles.phase_dur ≈ result1.generations[1].particles.phase_dur
end
