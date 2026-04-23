using DataFrames, Distributions, Random

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
    @test prob.reference_variation_id == PhysiCellModelManager.VariationID(inputs)

    prob_with_ref = CalibrationProblem(inputs, [p], observed, endpointPopulationCounts, mseDistance;
        n_replicates=3, reference_variation_id=ref.variation_id)
    @test prob_with_ref.n_replicates == 3
    @test !ismissing(prob_with_ref.reference_variation_id)
end

################## ABCSMC Method Construction ##################

@testset "ABCSMC construction and validation" begin
    m = ABCSMC()
    @test m.population_size == 100
    @test m.max_nr_populations == 10
    @test m.minimum_epsilon == 0.01
    @test m.epsilon_quantile == 0.5
    @test m.perturbation_kernel === :gaussian

    m2 = ABCSMC(population_size=50, max_nr_populations=3, minimum_epsilon=0.1)
    @test m2.population_size == 50

    @test_throws ArgumentError ABCSMC(population_size=0)
    @test_throws ArgumentError ABCSMC(max_nr_populations=-1)
    @test_throws ArgumentError ABCSMC(minimum_epsilon=-0.1)
    @test_throws ArgumentError ABCSMC(epsilon_quantile=0.0)
    @test_throws ArgumentError ABCSMC(epsilon_quantile=1.0)
    @test_throws ArgumentError ABCSMC(perturbation_kernel=:uniform)

    # AbstractCalibrationMethod hierarchy is in place
    @test m isa PhysiCellModelManager.AbstractCalibrationMethod
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

################## ABC-SMC Algorithm Unit Tests ##################
# These tests exercise the framework-agnostic ABC-SMC core without running PhysiCell.

@testset "ABC-SMC algorithm on toy model" begin
    # Recover the mean of a Normal distribution from a synthetic "observed" sample mean.
    Random.seed!(1234)
    true_mu = 2.0
    obs_mean = mean(rand(Normal(true_mu, 1.0), 100))

    param_names = ["mu"]
    priors = [Uniform(-5.0, 5.0)]

    # Simple evaluate function: draw samples and compare means
    function evaluate(params::Dict{String,Float64})
        mu = params["mu"]
        sim_mean = mean(rand(Normal(mu, 1.0), 100))
        return abs(sim_mean - obs_mean), 0
    end

    method = ABCSMC(population_size=80, max_nr_populations=4, minimum_epsilon=0.001, epsilon_quantile=0.5)
    gens = PhysiCellModelManager._runABCSMC(method, param_names, priors, evaluate, g -> nothing)

    @test length(gens) == 4
    @test all(g.t == i for (i, g) in enumerate(gens))

    # Epsilon should decrease over generations
    for i in Iterators.drop(eachindex(gens), 1)
        @test gens[i].epsilon <= gens[i-1].epsilon
    end

    # Weights sum to 1 per generation
    for g in gens
        @test sum(g.weights) ≈ 1.0 atol=1e-6
        @test length(g.weights) == g.particles |> nrow
        @test length(g.distances) == g.particles |> nrow
    end

    # Posterior mean should be close to observed mean (weak check)
    final = gens[end]
    post_mean = sum(final.weights .* final.particles.mu)
    @test abs(post_mean - obs_mean) < 0.5
end

@testset "ABC-SMC stops at minimum_epsilon" begin
    # With a trivial problem (distance always 0), epsilon should collapse immediately.
    evaluate = params -> (0.0, 0)
    method = ABCSMC(population_size=10, max_nr_populations=5, minimum_epsilon=0.5)
    gens = PhysiCellModelManager._runABCSMC(method, ["x"], [Uniform(0, 1)], evaluate, g -> nothing)

    # First generation always runs; subsequent generations should be skipped because ε = 0 < 0.5
    @test length(gens) == 1
    @test gens[1].epsilon == 0.0
end

@testset "GenerationResult persistence" begin
    calibration = PhysiCellModelManager.createCalibration("ABC-SMC"; description="persistence test")

    # Build a fake GenerationResult and save it
    particles = DataFrame(mu=[1.0, 2.0, 3.0])
    gen = GenerationResult(1, particles, [0.2, 0.3, 0.5], [0.1, 0.2, 0.3], 0.3, 10, [101, 102, 103])
    PhysiCellModelManager._saveGeneration(calibration, gen)

    path = joinpath(PhysiCellModelManager.calibrationFolder(calibration), "generations", "generation_1.csv")
    @test isfile(path)

    # Round-trip via _loadGenerations
    gens = PhysiCellModelManager._loadGenerations(calibration, ["mu"])
    @test length(gens) == 1
    @test gens[1].t == 1
    @test gens[1].particles.mu == [1.0, 2.0, 3.0]
    @test gens[1].weights ≈ [0.2, 0.3, 0.5]
    @test gens[1].distances ≈ [0.1, 0.2, 0.3]
    @test gens[1].monad_ids == [101, 102, 103]
end

@testset "ABCSMC method save/load" begin
    calibration = PhysiCellModelManager.createCalibration("ABC-SMC"; description="method save test")
    method = ABCSMC(population_size=77, max_nr_populations=6, minimum_epsilon=0.02,
                    epsilon_quantile=0.3, perturbation_kernel=:gaussian)
    PhysiCellModelManager._saveMethod(calibration, method)
    loaded = PhysiCellModelManager._loadMethod(calibration)
    @test loaded.population_size == 77
    @test loaded.max_nr_populations == 6
    @test loaded.minimum_epsilon == 0.02
    @test loaded.epsilon_quantile == 0.3
    @test loaded.perturbation_kernel === :gaussian
end

################## ABC-SMC End-to-End Test (with PhysiCell) ##################
# Uses the actual PhysiCell simulator with a tiny population/generation budget.

@testset "runABC end-to-end" begin
    observed = Dict(cell_type => Float64(endpointPopulationCounts(1)[cell_type]))
    params = [CalibrationParameter("phase_dur", xml_path_phase, Uniform(200.0, 400.0))]
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
    @test isdir(PhysiCellModelManager.calibrationFolder(result.calibration))
    @test !isempty(result.generations)
    @test result.method isa ABCSMC

    monad_ids = PhysiCellModelManager.calibrationMonadIDs(result.calibration)
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
    gen_dir = joinpath(PhysiCellModelManager.calibrationFolder(result.calibration), "generations")
    @test isdir(gen_dir)
    @test isfile(joinpath(gen_dir, "generation_1.csv"))
end

@testset "resumeABC" begin
    # Run a short calibration, then resume with more generations
    observed = Dict(cell_type => Float64(endpointPopulationCounts(1)[cell_type]))
    params = [CalibrationParameter("phase_dur", xml_path_phase, Uniform(200.0, 400.0))]
    problem = CalibrationProblem(
        inputs, params, observed,
        endpointPopulationCounts, mseDistance;
        reference_variation_id=ref.variation_id
    )

    # Initial run: 1 generation, tiny population
    method_initial = ABCSMC(population_size=3, max_nr_populations=1, minimum_epsilon=0.0)
    result1 = PhysiCellModelManager.runCalibration(problem, method_initial; description="resume test")
    @test length(result1.generations) == 1

    # Resume with a method that allows 2 more generations
    method_continue = ABCSMC(population_size=3, max_nr_populations=3, minimum_epsilon=0.0)
    result2 = resumeABC(result1.calibration, problem; method=method_continue)
    @test length(result2.generations) > 1
    @test result2.calibration.id == result1.calibration.id

    # First generation particles should be preserved across resume
    @test result2.generations[1].particles.phase_dur ≈ result1.generations[1].particles.phase_dur
end
