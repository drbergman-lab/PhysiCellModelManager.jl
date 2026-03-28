using Distributions

export CalibrationParameter, CalibrationProblem, Calibration, ABCResult

"""
    CalibrationParameter

Defines a single parameter to be calibrated.

# Fields
- `name::String`: Name used as the key in pyabc's parameter dictionary and for display.
- `xml_path::XMLPath`: Path into the PhysiCell XML config specifying where to inject the value.
- `prior::Distribution`: Prior distribution over this parameter (from `Distributions.jl`).
  Supported: `Uniform`, `Normal`, `LogNormal`, `Exponential`. Open an issue to request others.

# Examples
```julia
p = CalibrationParameter(
    "apoptosis_rate",
    configPath("cell_definitions", "cell_definition:name:default", "phenotype",
               "death:model:code:100", "death_rate"),
    Uniform(1e-7, 1e-4)
)
```
"""
struct CalibrationParameter
    name::String
    xml_path::XMLPath
    prior::Distribution
end

function CalibrationParameter(name::String, xml_path::AbstractVector{<:AbstractString}, prior::Distribution)
    return CalibrationParameter(name, XMLPath(xml_path), prior)
end

"""
    CalibrationProblem

Defines a full calibration problem: model inputs, parameters to infer, observed data,
and how to compare simulated to observed output.

# Fields
- `inputs::InputFolders`: Base model configuration shared across all calibration runs.
- `parameters::Vector{CalibrationParameter}`: Parameters to calibrate.
- `observed_data::Dict{String,<:Any}`: Observed summary statistics (keys match those
  returned by `summary_statistic`). Values may be scalars (`Float64`) for endpoint
  comparisons or vectors (`Vector{Float64}`) for time-series comparisons.
- `summary_statistic::Function`: `(monad_id::Int) → Dict{String,<:Any}`.
  Called once per pyabc particle. The user controls how to aggregate over
  `simulationIDs(Monad, monad_id)` (e.g. averaging, taking a single replicate).
  Values must be the same shape as the corresponding entries in `observed_data`.
  Built-ins: [`endpointPopulationCounts`](@ref), [`endpointPopulationFractions`](@ref).
- `distance::Function`: `(simulated::Dict{String,<:Any}, observed::Dict{String,<:Any}) → Float64`.
  `simulated` is the output of `summary_statistic`; `observed` is `observed_data`.
  Built-in: [`mseDistance`](@ref) — handles both scalar and vector values.
- `n_replicates::Int`: Number of PhysiCell replicate simulations to run per pyabc particle
  (default 1). Values > 1 reduce stochastic noise in each particle evaluation at the cost
  of N× more compute. pyabc handles stochasticity inherently across generations even with
  `n_replicates = 1`.
- `reference_variation_id::Union{Missing,VariationID}`: Optional base variation ID
  establishing fixed parameter values (e.g. `max_time`, save intervals) that apply to
  every particle evaluation. If `missing`, the default base variation ID is used.
  Obtain from a reference monad: `createTrial(inputs, fixed_dvs...; n_replicates=0).variation_id`.

# Examples
```julia
# Short run for testing — set max_time via a reference
ref = createTrial(inputs, DiscreteVariation(["overall","max_time"], 12.0); n_replicates=0)

observed = Dict("default" => 100.0)
problem = CalibrationProblem(
    inputs,
    [CalibrationParameter("death_rate", xml_path, Uniform(1e-7, 1e-4))],
    observed,
    monad_id -> endpointPopulationCounts(monad_id),
    mseDistance;
    reference_variation_id=ref.variation_id
)
```
"""
struct CalibrationProblem
    inputs::InputFolders
    parameters::Vector{CalibrationParameter}
    observed_data::Dict{String,Any}
    summary_statistic::Function
    distance::Function
    n_replicates::Int
    reference_variation_id::Union{Missing,VariationID}
end

function CalibrationProblem(inputs, parameters, observed_data::Dict{String,<:Any},
    summary_statistic, distance;
    n_replicates::Int=1, reference_variation_id::Union{Missing,VariationID}=missing)
    return CalibrationProblem(inputs, parameters, Dict{String,Any}(observed_data),
                              summary_statistic, distance, n_replicates, reference_variation_id)
end

"""
    Calibration

Represents a calibration run tracked in the PCMM database.

Created automatically by [`runABC`](@ref). The associated output folder at
`data/outputs/calibrations/{id}/` contains:
- `monads.csv`: monad IDs evaluated during calibration (appended as pyabc proposes particles)
- `abc_history.db`: pyabc's internal SQLite database

# Fields
- `id::Int`: Unique ID, matched to the `calibrations` table in `pcmm.db`.
"""
struct Calibration
    id::Int
end

"""
    ABCResult

Holds the result of an ABC-SMC calibration run.

# Fields
- `calibration::Calibration`: The PCMM calibration record (DB entry + folder).
- `history`: The pyabc `History` object (Python, via PyCall). Access posterior samples
  with [`posterior`](@ref).
- `parameters::Vector{CalibrationParameter}`: The calibrated parameters (same as in
  the `CalibrationProblem`).

# Examples
```julia
result = runABC(problem)
df, weights = posterior(result)           # final generation
df, weights = posterior(result; generation=2)  # specific generation
```
"""
struct ABCResult
    calibration::Calibration
    history::Any   # PyObject — typed as Any to avoid PyCall at load time
    parameters::Vector{CalibrationParameter}
end

"""
    posterior(result::ABCResult; generation::Union{Int,Symbol}=:final)

Extract posterior samples from an [`ABCResult`](@ref).

# Returns
- `df::DataFrame`: One row per particle, columns are parameter names.
- `weights::Vector{Float64}`: Importance weights (sum to 1).

# Arguments
- `generation`: Integer generation index (0-based) or `:final` for the last generation.
"""
function posterior(result::ABCResult; generation::Union{Int,Symbol}=:final)
    t = generation === :final ? result.history.max_t : Int(generation)
    py_df, py_weights = result.history.get_distribution(m=0, t=t)
    # pandas DataFrame doesn't implement Tables.jl; extract columns via PyCall
    col_names = [String(c) for c in py_df.columns]
    df = DataFrame(Dict(c => Vector{Float64}(py_df[c].values) for c in col_names))
    weights = collect(Float64, py_weights)
    return df, weights
end
