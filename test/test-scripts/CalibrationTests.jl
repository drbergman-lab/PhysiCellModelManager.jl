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

    prob = CalibrationProblem(inputs, [dv], observed, endpointPopulationCounts, mseDistance)
    @test prob.n_replicates == 1
    @test prob.reference_variation_id == PhysiCellModelManager.VariationID(inputs)

    prob_with_ref = CalibrationProblem(inputs, [dv], observed, endpointPopulationCounts, mseDistance;
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
# These assert the builders reproduce their monad-level counterparts EXACTLY (`==`, not `isapprox`).
# That is the point of the migration: handing the same quantity to a `QoI` consumer must not move
# anyone's numbers. The three statistics disagree with each other in ways a shared reducer would
# silently erase, so each divergence gets its own assertion.

@testset "QoI builder reducers" begin
    counts_q = endpointPopulationCountQoIs([cell_type]) |> first
    fracs_q = endpointPopulationFractionQoIs([cell_type]) |> first

    # Missing replicates are SKIPPED, not propagated. ModelManager hands `reduce` every replicate's
    # value including `missing`, so a default `mean` would return `missing` for the whole monad --
    # reachable on ordinary data, because pruning makes a replicate unreadable.
    @test counts_q.reduce([1, missing, 3]) == 2
    @test fracs_q.reduce([0.25, missing, 0.75]) == 0.5
    # ...and all-missing is `missing`, matching the monad-level functions.
    @test ismissing(counts_q.reduce([missing, missing]))
    @test ismissing(fracs_q.reduce([missing, missing]))

    # Float associativity is observable, and the two existing functions disagree about it:
    # `finalPopulationCount(::Monad)` averages a generator (sequential summation) while
    # `_averageStatDicts` averages a materialised Vector. 1200 copies of 0.1 is a deliberately
    # boring input that separates them: `sum` over an array switches to pairwise summation above a
    # blocksize of 1024, so the divergence here comes from Julia's algorithm rather than from SIMD
    # width, and therefore reproduces on any machine. (Shorter vectors can differ too, but only via
    # vectorised reassociation, which varies by CPU and would make this test machine-dependent.)
    diverging = fill(0.1, 1200)
    @test mean(diverging) != mean(x for x in diverging)

    # Each reducer matches its OWN original form on that input...
    @test counts_q.reduce(diverging) == mean(x for x in diverging)
    @test fracs_q.reduce(diverging) == mean(Float64[x for x in diverging])
    # ...and therefore differ from each other, which is what makes the two assertions above
    # load-bearing rather than two spellings of the same check.
    @test counts_q.reduce(diverging) != fracs_q.reduce(diverging)
end

@testset "QoI builders match the monad-level functions" begin
    # `_asSummaryStatistic` is ModelManager's own calibration seam and has no public equivalent.
    # Going through it rather than calling `compute`/`reduce` directly is deliberate: it is what
    # wraps the reduced value as `Dict(name => value)`, so this is the assertion that catches the
    # nesting hazard -- one QoI named "counts" would produce `Dict("counts" => Dict(...))` and break
    # `mseDistance`, which compares cell-type keys elementwise.
    evaluate(qois, monad_id) = ModelManager._asSummaryStatistic(qois)(monad_id)

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

    for (builder, monadwise) in [(endpointPopulationCountQoIs, endpointPopulationCounts),
                                 (endpointPopulationFractionQoIs, endpointPopulationFractions),
                                 (meanPopulationTimeSeriesQoIs, meanPopulationTimeSeries)]
        via_qoi = evaluate(builder([cell_type]), monad_id)
        direct = monadwise(monad_id; cell_types=[cell_type])
        @test keys(via_qoi) == keys(direct)          # flat, keyed by cell type -- not nested
        @test via_qoi[cell_type] == direct[cell_type]
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

    for (builder, monadwise) in [(endpointPopulationCountQoIs, endpointPopulationCounts),
                                 (endpointPopulationFractionQoIs, endpointPopulationFractions),
                                 (meanPopulationTimeSeriesQoIs, meanPopulationTimeSeries)]
        via_qoi = evaluate(builder([cell_type]), monad_id)
        direct = monadwise(monad_id; cell_types=[cell_type])
        @test via_qoi[cell_type] == direct[cell_type]
    end
end

################## ABC-SMC End-to-End Test (with PhysiCell) ##################
# Uses the actual PhysiCell simulator with a tiny population/generation budget.

@testset "runABC end-to-end" begin
    observed = Dict(cell_type => Float64(endpointPopulationCounts(1)[cell_type]))
    params = [DistributedVariation(xml_path_phase, Uniform(200.0, 400.0); name="phase_dur")]
    problem = CalibrationProblem(
        inputs, params, observed,
        endpointPopulationCounts, mseDistance;
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
        endpointPopulationCounts, mseDistance;
        reference_variation_id=ref.variation_id
    )

    # Initial run: 1 generation, tiny population
    method_initial = ABCSMC(population_size=3, max_nr_populations=1, minimum_epsilon=0.0)
    #! ModelManager takes the method first: `runCalibration(::ABCSMC, ::CalibrationProblem; ...)`.
    result1 = runCalibration(method_initial, problem; description="resume test")
    @test length(result1.generations) == 1

    # Resume with a method that allows 2 more generations
    method_continue = ABCSMC(population_size=3, max_nr_populations=3, minimum_epsilon=0.0)
    result2 = resumeABC(result1.calibration; problem=problem, method=method_continue)
    @test length(result2.generations) > 1
    @test result2.calibration.id == result1.calibration.id

    # First generation particles should be preserved across resume
    @test result2.generations[1].particles.phase_dur ≈ result1.generations[1].particles.phase_dur
end
