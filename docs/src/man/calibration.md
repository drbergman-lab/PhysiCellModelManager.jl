# Calibration(@id calibration_section_man)

PhysiCellModelManager.jl supports Bayesian parameter calibration via the Approximate Bayesian Computation Sequential Monte Carlo (ABC-SMC) algorithm.
ABC-SMC is a likelihood-free inference method that iteratively refines a population of parameter samples (particles) by accepting only those whose simulated outputs are within a shrinking tolerance (epsilon) of the observed data.
It is well-suited to agent-based models where an explicit likelihood function is unavailable or intractable.

The implementation is native Julia — no Python or conda environment is required.

## Quick start

```julia
using PhysiCellModelManager
using Distributions

# 1. Model inputs
inputs = InputFolders("default", "default")

# 2. Parameters to infer, with priors from Distributions.jl
parameters = [
    CalibrationParameter(
        "apoptosis_rate",
        configPath("cancer", "apoptosis", "rate"),
        Uniform(1e-4, 5e-3)
    ),
    CalibrationParameter(
        "cycle_duration",
        configPath("cancer", "cycle", "duration", 0),
        Uniform(480.0, 1440.0)
    ),
]

# 3. Observed data
observed_data = Dict("cancer" => 3500.0, "immune" => 800.0)

# 4. Build the problem: summary statistic + distance function
problem = CalibrationProblem(
    inputs,
    parameters,
    observed_data,
    endpointPopulationCounts,   # summary statistic
    mseDistance;                # distance function
    n_replicates = 3,
)

# 5. Run ABC-SMC
result = runABC(
    problem;
    population_size    = 200,
    max_nr_populations = 15,
    minimum_epsilon    = 0.05,
    description        = "apoptosis-cycle calibration",
)

# 6. Extract the posterior
df, weights = posterior(result)           # final generation
df3, w3     = posterior(result; generation=3)  # specific earlier generation
```

## The ABC-SMC algorithm

Each generation proceeds as follows:

1. **Propose** `population_size` particles
   - Generation 1: sample directly from the priors.
   - Generation *t > 1*: resample a particle from the previous (weighted) generation and perturb it with a Gaussian kernel whose covariance is twice the weighted sample covariance of the previous generation (Beaumont et al. 2009).
2. **Evaluate** each proposed particle
   - Create a `Monad` at the proposed parameter values (reusing existing simulations where possible via `use_previous=true`).
   - Run the simulations quietly (per-simulation output is suppressed during calibration).
   - Apply the user's `summary_statistic` and `distance` to produce a scalar distance.
3. **Accept** particles whose distance is below the current `epsilon`. In generation 1 all proposals are kept; in later generations a rejection step is used.
4. **Reweight** using the standard ABC-SMC importance weights.
5. **Adapt** the next generation's epsilon as a quantile (default: median) of the current accepted distances, never dropping below `minimum_epsilon`.
6. **Save** the generation to disk (see below) and stop if epsilon has reached `minimum_epsilon` or `max_nr_populations` is exhausted.

### Method type

For extensibility (future support for GP-accelerated ABC, Bayesian optimization, etc.), calibration methods are represented as subtypes of [`AbstractCalibrationMethod`](@ref). ABC-SMC is [`ABCSMC`](@ref):

```julia
method = ABCSMC(population_size=200, max_nr_populations=10, minimum_epsilon=0.05)
result = runCalibration(problem, method)
```

[`runABC`](@ref) is a convenience wrapper that constructs an `ABCSMC` from keyword arguments and delegates to [`runCalibration`](@ref).

### On warm-starting from existing simulations

PCMM does **not** seed generation 1 with pre-existing simulations. Doing so would bias the gen-1 sample away from the prior distribution (e.g., if prior sweeps or sensitivity designs were clustered). Instead, every gen-1 particle is drawn fresh from the prior.

However, `Monad(...; use_previous=true)` is used internally for every particle, so any exact-match parameter point that happens to already exist in the database (e.g., from a previous calibration at the same point) is reused for free.

## Resuming a calibration

If a calibration is interrupted (crash, user stop, HPC timeout), the completed generations are already saved on disk. Use [`resumeABC`](@ref) to continue:

```julia
# Previously: result = runABC(problem; max_nr_populations=10)
# ... interrupted at generation 4 ...

# Load the calibration by ID and continue
calibration = Calibration(42)
result = resumeABC(calibration, problem)
```

If no `method` is provided, the original settings are loaded from `method.toml` in the calibration output folder. Pass an explicit `method` to override settings (e.g., to increase `max_nr_populations`).

## Output layout

Each calibration run creates `data/outputs/calibrations/{id}/` with:

- `monads.csv` — one line per monad evaluated, in order.
- `method.toml` — the [`ABCSMC`](@ref) settings used (for `resumeABC`).
- `generations/generation_{t}.csv` — one file per completed generation. Columns: each parameter name, plus `weight`, `distance`, `monad_id`.

## Built-in summary statistics

Three built-in summary statistics accept a monad ID and return a summary suitable for the `summary_statistic` argument of [`CalibrationProblem`](@ref).

### `endpointPopulationCounts`

```julia
endpointPopulationCounts(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type to its population count at the final simulation time point.

### `endpointPopulationFractions`

```julia
endpointPopulationFractions(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type to its **fraction** of the total live cell population at the final time point.

### `meanPopulationTimeSeries`

```julia
meanPopulationTimeSeries(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Vector{Float64}}` mapping each cell type to a vector of mean population counts across all output time points. Useful when observed data is a time series rather than a single endpoint value.

## Built-in distance functions

### `mseDistance`

```julia
mseDistance(simulated, observed)
```

Computes the mean squared error between `simulated` and `observed`. Both scalar and vector values are supported; when the dicts contain a mix, the per-key contributions (squared error for scalars, mean squared error for vectors) are averaged across all keys in `observed`.

## Deprecated: pyabc backend

Earlier versions of PCMM provided ABC-SMC via pyabc (Python), accessed through a `PythonCall`-based extension. This backend has been replaced by the native Julia implementation described above. Loading `PythonCall` alongside `PhysiCellModelManager` now emits a one-time deprecation warning and does not affect calibration behavior.
