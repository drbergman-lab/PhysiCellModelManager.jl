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

@testset "endpointPopulationCounts" begin
    counts = endpointPopulationCounts(1)
    @test counts isa Dict{String,Float64}
    @test all(v >= 0.0 for v in values(counts))
    @test haskey(counts, cell_type)

    # filter to a specific cell type
    counts_filtered = endpointPopulationCounts(1; cell_types=[cell_type])
    @test length(counts_filtered) == 1
    @test haskey(counts_filtered, cell_type)
    @test counts_filtered[cell_type] ≈ counts[cell_type]
end

@testset "endpointPopulationFractions" begin
    fracs = endpointPopulationFractions(1)
    @test fracs isa Dict{String,Float64}
    @test all(0.0 <= v <= 1.0 for v in values(fracs))
    # fractions sum to 1 (within floating-point tolerance)
    @test sum(values(fracs)) ≈ 1.0 atol=1e-10

    fracs_filtered = endpointPopulationFractions(1; cell_types=[cell_type])
    @test length(fracs_filtered) == 1
end

@testset "meanPopulationTimeSeries" begin
    ts = meanPopulationTimeSeries(1)
    @test ts isa Dict{String,Vector{Float64}}
    @test haskey(ts, cell_type)
    @test all(v >= 0.0 for vec in values(ts) for v in vec)

    ts_filtered = meanPopulationTimeSeries(1; cell_types=[cell_type])
    @test length(ts_filtered) == 1
    @test haskey(ts_filtered, cell_type)
    @test ts_filtered[cell_type] ≈ ts[cell_type]
end

@testset "finalPopulationCount(Monad)" begin
    counts = finalPopulationCount(Monad(1))
    @test counts isa Dict{String,Float64}
    @test haskey(counts, cell_type)
    @test counts[cell_type] ≈ endpointPopulationCounts(1)[cell_type]
end

################## QoI-returning builders ##################
#
# These assert the builders reproduce their monad-level counterparts up to floating-point summation
# order (`≈`, not `==`). Handing the same quantity to a `QoI` consumer still must not move anyone's
# numbers, but exact equality is no longer the claim: since #232 the builders define no `reduce` and
# go through ModelManager's default per-key mean, while the monad-level functions keep their own
# accumulation (`finalPopulationCount(::Monad)`'s generator mean, `_averageStatDicts`' materialised
# one, `mean(array, dims=2)`). The two can therefore sum in different orders; they cannot disagree
# about which replicates or which cell types are in the average, because no roster is ragged.

#! The builders carry their keyword arguments in `data`, which selects the two-argument calling
#! convention ModelManager uses for them: `compute(sim, data)` and `reduce(values, data)`.
computeOn(q, sim) = q.compute(sim, q.data)
reduceWith(q, values) = q.reduce(values, q.data)

#! `≈` has no `Dict` method, and these dicts hold a `Float64` for the endpoint builders and a
#! `Vector{Float64}` for the time-series one, so compare the key sets and then each value.
approxDicts(a, b) = keys(a) == keys(b) && all(a[k] ≈ b[k] for k in keys(a))

@testset "QoI builder reducers" begin
    counts_q = populationCountQoI()
    fracs_q = endpointPopulationFractionQoI()

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
    # replicates share a config. The other was the float-associativity gap between
    # `finalPopulationCount(::Monad)`'s generator mean and `_averageStatDicts`' materialised one
    # (1200 copies of 0.1) to prove the two bespoke reducers were genuinely different functions.
    # There is one reducer now, so there is no gap between builders to pin; what is left is the gap
    # between a builder and its monad-level counterpart, and the testset below asserts `≈` for it.
end

@testset "QoI builders match the monad-level functions" begin
    # Evaluate each QoI the way ModelManager does -- `reduce` over `compute` for every replicate --
    # using only the QoI's own documented parts. An earlier version of this test called
    # `ModelManager._asSummaryStatistic`, which was renamed to `_validateSummaryStatistic` in #46 and
    # took the test with it. Pinning another package's internals is the same mistake as pinning its
    # on-disk layout: the flat-vs-nested dict shape is ModelManager's contract to keep, not ours.
    #! ModelManager's own seam -- compute per replicate, drop the `missing` ones, reduce -- which is
    #! the path calibration and sensitivity analysis take, and so the path these equalities are
    #! about. Internal, but the alternative is re-implementing it here and asserting against a copy.
    evaluate(q, monad_id) = PhysiCellModelManager.ModelManager._reduceOverMonad(q, monad_id)

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
    #! `endpointPopulationFractionQoI` did exactly that. A nonexistent type is what discriminates
    #! here -- this model defines one cell type, so filtering *to* it cannot tell the two apart.
    for builder in (populationCountQoI, endpointPopulationFractionQoI)
        @test isempty(computeOn(builder(; cell_types=["nonexistent_type"]), Simulation(first(sids))))
        @test haskey(computeOn(builder(; cell_types=[cell_type]), Simulation(first(sids))), cell_type)
    end
    #! The fraction denominator stays every live cell, so restricting does not renormalise: a
    #! single-cell-type model still reads 1.0 whether or not the filter is applied.
    @test computeOn(endpointPopulationFractionQoI(; cell_types=[cell_type]), Simulation(first(sids)))[cell_type] ==
          computeOn(endpointPopulationFractionQoI(), Simulation(first(sids)))[cell_type]

    for (builder, monadwise) in [(populationCountQoI, endpointPopulationCounts),
                                 (endpointPopulationFractionQoI, endpointPopulationFractions),
                                 (meanPopulationTimeSeriesQoI, meanPopulationTimeSeries)]
        via_qoi = evaluate(builder(; cell_types=[cell_type]), monad_id)
        direct = monadwise(monad_id; cell_types=[cell_type])
        @test keys(via_qoi) == keys(direct)          # flat, keyed by cell type -- not nested
        @test via_qoi[cell_type] ≈ direct[cell_type]
        #! ...and with no `cell_types`, the QoI discovers them exactly as the monad-level function
        #! does -- the thing the previous `Vector{QoI}` shape could not do.
        @test approxDicts(evaluate(builder(), monad_id), monadwise(monad_id))
    end

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

    for (builder, monadwise) in [(populationCountQoI, endpointPopulationCounts),
                                 (endpointPopulationFractionQoI, endpointPopulationFractions),
                                 (meanPopulationTimeSeriesQoI, meanPopulationTimeSeries)]
        @test evaluate(builder(; cell_types=[cell_type]), monad_id)[cell_type] ≈
              monadwise(monad_id; cell_types=[cell_type])[cell_type]
    end
end

################## ABC-SMC End-to-End Test (with PhysiCell) ##################
# Uses the actual PhysiCell simulator with a tiny population/generation budget.

@testset "runABC end-to-end" begin
    observed = Dict(cell_type => Float64(endpointPopulationCounts(1)[cell_type]))
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
    observed = Dict(cell_type => Float64(endpointPopulationCounts(1)[cell_type]))
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
