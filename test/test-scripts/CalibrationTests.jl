using DataFrames, Distributions

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

    # Generation files saved to disk
    gen_dir = joinpath(ModelManager.calibrationFolder(result.calibration), "generations")
    @test isdir(gen_dir)
    @test isfile(joinpath(gen_dir, "generation_1.csv"))
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
    result1 = runCalibration(problem, method_initial; description="resume test")
    @test length(result1.generations) == 1

    # Resume with a method that allows 2 more generations
    method_continue = ABCSMC(population_size=3, max_nr_populations=3, minimum_epsilon=0.0)
    result2 = resumeABC(result1.calibration; problem=problem, method=method_continue)
    @test length(result2.generations) > 1
    @test result2.calibration.id == result1.calibration.id

    # First generation particles should be preserved across resume
    @test result2.generations[1].particles.phase_dur ≈ result1.generations[1].particles.phase_dur
end
