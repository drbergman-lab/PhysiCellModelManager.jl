using DataFrames, Distributions, PyCall

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
ref = createTrial(inputs, [dv_max_time, dv_full_data, dv_svg]; n_replicates=0)

xml_path_phase = PhysiCellModelManager.cyclePath(cell_type, "phase_durations", "duration:index:0")

################## Distance Function Unit Tests ##################

@testset "mseDistance" begin
    @test PhysiCellModelManager.mseDistance(
        Dict("a" => 3.0, "b" => 4.0),
        Dict("a" => 1.0, "b" => 2.0)
    ) ≈ 4.0   # ((3-1)^2 + (4-2)^2) / 2 = 4.0

    @test PhysiCellModelManager.mseDistance(
        Dict("a" => 1.0),
        Dict("a" => 1.0)
    ) ≈ 0.0

    # Missing key in simulated → treated as 0.0
    @test PhysiCellModelManager.mseDistance(
        Dict{String,Float64}(),
        Dict("a" => 2.0)
    ) ≈ 4.0

    # Empty observed → distance is 0.0
    @test PhysiCellModelManager.mseDistance(
        Dict("a" => 99.0),
        Dict{String,Any}()
    ) ≈ 0.0

    # Vector values (time-series): MSE averaged element-wise, then averaged across keys
    @test PhysiCellModelManager.mseDistance(
        Dict{String,Any}("a" => [1.0, 2.0, 3.0]),
        Dict{String,Any}("a" => [2.0, 2.0, 2.0])
    ) ≈ (1.0 + 0.0 + 1.0) / 3   # mean of element-wise squared errors, 1 key

    # Mixed scalar and vector keys
    @test PhysiCellModelManager.mseDistance(
        Dict{String,Any}("counts" => [1.0, 3.0], "frac" => 0.5),
        Dict{String,Any}("counts" => [2.0, 2.0], "frac" => 1.0)
    ) ≈ ((1.0 + 1.0)/2 + 0.25) / 2   # (mean vector MSE + scalar MSE) / n_keys

    # Mismatched vector lengths → DimensionMismatch
    @test_throws DimensionMismatch PhysiCellModelManager.mseDistance(
        Dict{String,Any}("a" => [1.0, 2.0]),
        Dict{String,Any}("a" => [1.0, 2.0, 3.0])
    )
end

################## Type Construction Tests ##################

@testset "CalibrationParameter construction" begin
    p = CalibrationParameter("phase_dur", xml_path_phase, Uniform(200.0, 400.0))
    @test p.name == "phase_dur"
    @test p.prior isa Uniform
end

@testset "CalibrationProblem construction" begin
    observed = Dict("default" => 100.0)
    p = CalibrationParameter("phase_dur", xml_path_phase, Uniform(200.0, 400.0))

    prob = CalibrationProblem(inputs, [p], observed, endpointPopulationCounts, mseDistance)
    @test prob.n_replicates == 1
    @test ismissing(prob.reference_variation_id)

    prob_with_ref = CalibrationProblem(inputs, [p], observed, endpointPopulationCounts, mseDistance;
        n_replicates=3, reference_variation_id=ref.variation_id)
    @test prob_with_ref.n_replicates == 3
    @test !ismissing(prob_with_ref.reference_variation_id)
end

################## DB / Folder Tests ##################

@testset "createCalibration" begin
    calibration = PhysiCellModelManager.createCalibration("ABC-SMC"; description="test calibration")
    @test calibration isa Calibration
    @test calibration.id isa Int

    folder = PhysiCellModelManager.calibrationFolder(calibration)
    @test isdir(folder)

    csv_path = PhysiCellModelManager.calibrationMonadsCSV(calibration)
    @test csv_path == joinpath(folder, "monads.csv")

    db_path = PhysiCellModelManager.calibrationABCDBPath(calibration)
    @test db_path == joinpath(folder, "abc_history.db")

    # monads.csv doesn't exist yet (no particles evaluated)
    @test isempty(PhysiCellModelManager.calibrationMonadIDs(calibration))

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

################## pyabc Integration Tests (guarded) ##################

pyabc_available = try
    pyimport("pyabc")
    true
catch
    false
end

if !pyabc_available
    @warn "pyabc not available — skipping ABC-SMC integration tests. " *
          "Install pyabc in your UQ Python environment to enable them:\n" *
          "    pip install pyabc"
end

@testset "ABC-SMC integration" begin
    if !pyabc_available
        @test_skip "pyabc not available"
    else
        # _importPyABC succeeds
        @test_nowarn PhysiCellModelManager._importPyABC()

        # Prior construction from Julia Distributions → pyabc.Distribution
        pyabc = PhysiCellModelManager._importPyABC()
        params = [
            CalibrationParameter("phase_dur", xml_path_phase, Uniform(200.0, 400.0)),
        ]
        prior = PhysiCellModelManager._buildPrior(pyabc, params)
        # prior is a PyObject (pyabc.Distribution); call .rvs() to draw a sample dict
        sample = prior.rvs()
        @test haskey(sample, "phase_dur")
        val = Float64(sample["phase_dur"])
        @test 200.0 <= val <= 400.0

        # Normal prior round-trip
        params_normal = [CalibrationParameter("phase_dur", xml_path_phase, Normal(300.0, 30.0))]
        @test_nowarn PhysiCellModelManager._buildPrior(pyabc, params_normal)

        # Unsupported prior type raises ArgumentError
        struct _Dummy <: ContinuousUnivariateDistribution end
        @test_throws ArgumentError PhysiCellModelManager._distributionToRV(pyabc, _Dummy())

        # Full runABC end-to-end with tiny budget
        observed = Dict(cell_type => Float64(endpointPopulationCounts(1)[cell_type]))
        problem = CalibrationProblem(
            inputs, params, observed,
            endpointPopulationCounts, mseDistance;
            reference_variation_id=ref.variation_id
        )

        result = runABC(problem;
            population_size=3,
            max_nr_populations=2,
            minimum_epsilon=Inf,   # never stop on epsilon
            description="test ABC run"
        )

        @test result isa ABCResult
        @test result.calibration isa Calibration
        @test isdir(PhysiCellModelManager.calibrationFolder(result.calibration))
        @test isfile(PhysiCellModelManager.calibrationABCDBPath(result.calibration))

        monad_ids = PhysiCellModelManager.calibrationMonadIDs(result.calibration)
        @test !isempty(monad_ids)
        @test all(id isa Int for id in monad_ids)

        # DB entry created
        query = PhysiCellModelManager.constructSelectQuery(
            "calibrations", "WHERE calibration_id=$(result.calibration.id)")
        df = PhysiCellModelManager.queryToDataFrame(query)
        @test nrow(df) == 1
        @test df.description[1] == "test ABC run"

        # posterior extraction
        post_df, weights = PhysiCellModelManager.posterior(result)
        @test post_df isa DataFrame
        @test "phase_dur" in names(post_df)
        @test length(weights) == nrow(post_df)
        @test sum(weights) ≈ 1.0 atol=1e-6
    end
end
