module PCMMCalibrationExt

using PhysiCellModelManager
using PhysiCellModelManager: CalibrationProblem, CalibrationParameter, ABCResult, Calibration,
    VariationID, addVariations, GridVariation, Monad, DiscreteVariation,
    createCalibration, calibrationMonadsCSV, calibrationABCDBPath,
    pcmm_globals
using PyCall
using Distributions: Distribution, Uniform, Normal, LogNormal, Exponential
using DataFrames: DataFrame

################## Python Environment ##################

"""
    _importPyABC()

Import the `pyabc` Python module, using the UQ-specific Python environment
(`PCMM_UQ_PYTHON_PATH` / `pcmm_globals.path_to_uq_python`) when set.

Raises a helpful error if `pyabc` is not importable.
"""
function _importPyABC()
    uq_python = pcmm_globals.path_to_uq_python
    if !ismissing(uq_python)
        # Ensure PyCall uses the configured Python; no-op if already configured
        if PyCall.python != uq_python
            @warn """
            PyCall is currently using $(PyCall.python) but PCMM_UQ_PYTHON_PATH is set to
            $(uq_python). PyCall cannot switch Python interpreters at runtime.
            To use the UQ Python environment, rebuild PyCall before starting Julia:

                ENV["PYTHON"] = "$(uq_python)"
                import Pkg; Pkg.build("PyCall")
            """
        end
    end

    try
        return pyimport("pyabc")
    catch
        throw(ErrorException("""
        Could not import `pyabc`. Make sure it is installed in the Python environment
        that PyCall is using (currently: $(PyCall.python)).

        Setup instructions:
            conda create -n pcmm-uq python=3.10
            conda activate pcmm-uq
            pip install pyabc

        Then point PCMM to this environment (add to your shell profile or set per-session):
            export PCMM_UQ_PYTHON_PATH="/path/to/conda/envs/pcmm-uq/bin/python"

        Then rebuild PyCall in Julia (once per machine):
            ENV["PYTHON"] = ENV["PCMM_UQ_PYTHON_PATH"]
            import Pkg; Pkg.build("PyCall")
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
    # to pickle the model function across Python processes, which fails for PyCall-wrapped
    # Julia functions. Simulation-level parallelism is handled by PCMM's own runner
    # (setNumberOfParallelSims), so this is no loss of throughput.
    sampler = pyabc.sampler.SingleCoreSampler()

    abc = pyabc.ABCSMC(py_model, prior, py_distance; population_size=population_size, sampler=sampler)

    # Convert observed_data dict to Python dict for pyabc
    py_observed = Dict(k => v for (k, v) in problem.observed_data)

    abc.new(abc_db_path, py_observed)
    history = abc.run(; minimum_epsilon=minimum_epsilon, max_nr_populations=max_nr_populations)

    return ABCResult(calibration, history, problem.parameters)
end

################## posterior ##################

function PhysiCellModelManager.posterior(result::ABCResult; generation::Union{Int,Symbol}=:final)
    t = generation === :final ? result.history.max_t : Int(generation)
    py_df, py_weights = result.history.get_distribution(m=0, t=t)
    # pandas DataFrame doesn't implement Tables.jl; extract columns via PyCall
    col_names = [String(c) for c in py_df.columns]
    df = DataFrame(Dict(c => Vector{Float64}(py_df[c].values) for c in col_names))
    weights = collect(Float64, py_weights)
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
    # pyabc.Distribution is a dict subclass; pycall with PyObject return type prevents
    # PyCall from auto-converting it to a Julia Dict (which would strip the .rvs() method).
    return pycall(pyabc.Distribution, PyObject; rv_dict...)
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
        # Build one single-valued DiscreteVariation per calibration parameter
        avs = [DiscreteVariation(p.xml_path, [Float64(params_dict[p.name])]) for p in problem.parameters]

        # Use the user-supplied reference variation ID (for fixed params like max_time),
        # falling back to the base variation ID if none was provided.
        ref_id = ismissing(problem.reference_variation_id) ?
            VariationID(problem.inputs) : problem.reference_variation_id

        # Resolve to a VariationID and create / retrieve the matching Monad
        add_result = addVariations(GridVariation(), problem.inputs, avs, ref_id)
        variation_id = add_result.variation_ids[1]
        monad = Monad(problem.inputs, variation_id; n_replicates=problem.n_replicates, use_previous=true)

        run(monad)

        # Record this monad in the calibration's monads.csv
        open(monads_csv, "a") do io
            println(io, monad.id)
        end

        # Return summary statistics as a plain Julia Dict (PyCall converts to Python dict)
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

Keys are coerced to `String`. Values are coerced as follows:
- Python scalars (float, int) → `Float64`
- Python lists / numpy arrays → `Vector{Float64}` (for time-series summary statistics)
- Complex-valued scalars → `Float64` via `real()`

Raises an informative error if a value cannot be converted.
"""
function _pyDictToJulia(d)
    result = Dict{String,Any}()
    for (k, v) in d
        key = String(k)
        result[key] = _pyValueToJulia(key, v)
    end
    return result
end

function _pyValueToJulia(key::String, v)
    # Try scalar first
    try
        return Float64(v)
    catch end
    # Try real part of a complex scalar
    try
        return Float64(real(v))
    catch end
    # Try converting to a Vector{Float64} (list or numpy array)
    try
        return Vector{Float64}(v)
    catch end
    throw(ArgumentError(
        """
        Cannot convert summary statistic value for key \"$key\" (Python type: $(pytype(v))) to Float64 or Vector{Float64}. Ensure your summary_statistic returns Dict{String,<:Real} or Dict{String,Vector{<:Real}}.
        """
    ))
end

end # module PCMMCalibrationExt
