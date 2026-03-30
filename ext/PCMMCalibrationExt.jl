module PCMMCalibrationExt

using PhysiCellModelManager
using PhysiCellModelManager: CalibrationProblem, CalibrationParameter, ABCResult, Calibration,
    VariationID, addVariations, GridVariation, Monad, DiscreteVariation,
    createCalibration, calibrationMonadsCSV, calibrationABCDBPath
using PythonCall
using Distributions: Distribution, Uniform, Normal, LogNormal, Exponential
using DataFrames: DataFrame

################## Python Environment ##################

"""
    _importPyABC()

Import the `pyabc` Python module. The Python environment (including pyabc) is managed
automatically by CondaPkg.jl when PythonCall is loaded.

Raises a helpful error if `pyabc` is not importable.
"""
function _importPyABC()
    try
        return pyimport("pyabc")
    catch
        throw(ErrorException("""
        Could not import `pyabc`.

        pyabc should be installed automatically via CondaPkg when PythonCall is loaded
        in a project that depends on PhysiCellModelManager. If the install failed,
        ensure you have a `CondaPkg.toml` file in your project. If not, add it to your project by:

                pkg> conda pip_add pyabc # in the Julia Pkg REPL

        """))
    end
end

################## runABC ##################

function PhysiCellModelManager.runABC(problem::CalibrationProblem;
    population_size::Int=100,
    max_nr_populations::Int=10,
    minimum_epsilon::Float64=0.01,
    description::String="")

    pyabc = _importPyABC()

    calibration = createCalibration("ABC-SMC"; description=description)
    monads_csv = calibrationMonadsCSV(calibration)
    abc_db_path = "sqlite:///$(calibrationABCDBPath(calibration))"

    prior = _buildPrior(pyabc, problem.parameters)

    py_model = _buildPyModel(problem, monads_csv)
    py_distance = _buildPyDistance(problem)

    # SingleCoreSampler is required: pyabc's default MulticoreEvalParallelSampler attempts
    # to pickle the model function across Python processes, which fails for PythonCall-wrapped
    # Julia functions. Simulation-level parallelism is handled by PCMM's own runner
    # (setNumberOfParallelSims), so this is no loss of throughput.
    sampler = pyabc.sampler.SingleCoreSampler()

    abc = pyabc.ABCSMC(py_model, prior, py_distance; population_size=population_size, sampler=sampler)

    py_observed = Dict(k => v for (k, v) in problem.observed_data)

    abc.new(abc_db_path, py_observed)
    history = abc.run(; minimum_epsilon=minimum_epsilon, max_nr_populations=max_nr_populations)

    return ABCResult(calibration, history, problem.parameters)
end

################## posterior ##################

function PhysiCellModelManager.posterior(result::ABCResult; generation::Union{Int,Symbol}=:final)
    t = generation === :final ? result.history.max_t : Int(generation)
    py_df, py_weights = result.history.get_distribution(m=0, t=t)
    col_names = pyconvert(Vector{String}, py_df.columns.tolist())
    df = DataFrame(Dict(c => pyconvert(Vector{Float64}, py_df[c].to_numpy()) for c in col_names))
    weights = pyconvert(Vector{Float64}, py_weights)
    return df, weights
end

################## Prior Construction ##################

"""
    _buildPrior(pyabc, parameters)

Build a `pyabc.Distribution` prior from a vector of [`CalibrationParameter`](@ref)s.
Each parameter's `prior::Distribution` (from `Distributions.jl`) is mapped to a
`pyabc.RV` (scipy distribution).

Supported distributions: `Uniform`, `Normal`, `LogNormal`, `Exponential`.
"""
function _buildPrior(pyabc, parameters::Vector{CalibrationParameter})
    rv_dict = Dict(Symbol(p.name) => _distributionToRV(pyabc, p.prior) for p in parameters)
    return pyabc.Distribution(; rv_dict...)
end

"""
    _distributionToRV(pyabc, d::Distribution)

Map a Julia `Distributions.jl` distribution to a `pyabc.RV` (scipy-backed).

Note on parameterization:
- `Uniform(a, b)`: scipy `uniform(loc=a, scale=b-a)` — covers [a, b].
- `Normal(μ, σ)`: scipy `norm(loc=μ, scale=σ)`.
- `LogNormal(μ, σ)`: scipy `lognorm(s=σ, loc=0, scale=exp(μ))` where μ, σ are the
  mean and std of the *underlying normal* (Julia's parameterization).
- `Exponential(θ)`: scipy `expon(loc=0, scale=θ)` where θ is the mean (Julia's
  `Exponential` uses mean parameterization, i.e., rate = 1/θ).
"""
function _distributionToRV(pyabc, d::Uniform)
    return pyabc.RV("uniform", d.a, d.b - d.a)
end

function _distributionToRV(pyabc, d::Normal)
    return pyabc.RV("norm", d.μ, d.σ)
end

function _distributionToRV(pyabc, d::LogNormal)
    # Julia LogNormal(μ, σ): underlying normal has mean μ and std σ
    return pyabc.RV("lognorm", d.σ, 0.0, exp(d.μ))
end

function _distributionToRV(pyabc, d::Exponential)
    # Julia Exponential(θ): mean = θ; scipy expon scale = mean
    return pyabc.RV("expon", 0.0, d.θ)
end

function _distributionToRV(::Any, d::Distribution)
    D = typeof(d)
    throw(ArgumentError(
        """
        Unsupported prior distribution: $D.
        - Supported types: Uniform, Normal, LogNormal, Exponential.
        - Open an issue to request support for additional distributions.
        - Or create the method yourself by writing the method as

            function PhysiCellModelManager._distributionToRV(pyabc, d::$(nameof(D)))
                ...
                return pyabc.RV(...)
            end
        """
    ))
end

################## Model and Distance Wrappers ##################

"""
    _buildPyModel(problem, monads_csv)

Return a Julia function suitable for use as a pyabc model callable.

The returned function accepts a Python dict of parameter values (one entry per
`CalibrationParameter`), runs the corresponding `Monad`, appends the monad ID to
`monads_csv`, and returns the summary statistic dict.
"""
function _buildPyModel(problem::CalibrationProblem, monads_csv::String)
    function py_model(params_dict)
        # params_dict is a Python dict; index with Julia strings (PythonCall converts automatically)
        avs = [DiscreteVariation(p.xml_path, [pyconvert(Float64, params_dict[p.name])]) for p in problem.parameters]

        ref_id = ismissing(problem.reference_variation_id) ?
            VariationID(problem.inputs) : problem.reference_variation_id

        add_result = addVariations(GridVariation(), problem.inputs, avs, ref_id)
        variation_id = add_result.variation_ids[1]
        monad = Monad(problem.inputs, variation_id; n_replicates=problem.n_replicates, use_previous=true)

        run(monad)

        open(monads_csv, "a") do io
            println(io, monad.id)
        end

        # Return Julia Dict; PythonCall converts it to a Python dict automatically
        return problem.summary_statistic(monad.id)
    end
    return py_model
end

"""
    _buildPyDistance(problem)

Return a Julia function suitable for use as a pyabc distance callable.

The returned function accepts two Python dicts (simulated and observed summary statistics)
and returns a Float64 distance.
"""
function _buildPyDistance(problem::CalibrationProblem)
    function py_distance(x_simulated, x_observed)
        sim = _pyDictToJulia(x_simulated)
        obs = _pyDictToJulia(x_observed)
        return problem.distance(sim, obs)
    end
    return py_distance
end

"""
    _pyDictToJulia(d) → Dict{String,Any}

Convert a Python dict (from pyabc) to a `Dict{String,Any}`.

Keys are converted to `String`. Values are converted as follows:
- Python scalars (float, int) → `Float64`
- Python lists / numpy arrays → `Vector{Float64}` (for time-series summary statistics)

Raises an informative error if a value cannot be converted.
"""
function _pyDictToJulia(d)
    result = Dict{String,Any}()
    for (k, v) in d
        key = pyconvert(String, k)
        result[key] = _pyValueToJulia(key, v)
    end
    return result
end

function _pyValueToJulia(key::String, v)
    # Try scalar first
    try
        return pyconvert(Float64, v)
    catch end
    # Try converting to a Vector{Float64} (list or numpy array)
    try
        return pyconvert(Vector{Float64}, v)
    catch end
    throw(ArgumentError(
        """
        Cannot convert summary statistic value for key \"$key\" (Python type: $(pytype(v))) to Float64 or Vector{Float64}. Ensure your summary_statistic returns Dict{String,<:Real} or Dict{String,Vector{<:Real}}.
        """
    ))
end

end # module PCMMCalibrationExt
