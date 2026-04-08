# [Calibration](@id calibration_section_man)

PhysiCellModelManager.jl supports Bayesian parameter calibration via the Approximate Bayesian Computation Sequential Monte Carlo (ABC-SMC) algorithm.
ABC-SMC is a likelihood-free inference method that iteratively refines a population of parameter samples (particles) by accepting only those whose simulated outputs are within a shrinking tolerance (epsilon) of the observed data.
It is well-suited to agent-based models where an explicit likelihood function is unavailable or intractable.

The implementation is native Julia — no Python or conda environment is required.
All algorithm infrastructure lives in ModelManager; PCMM contributes the PhysiCell-specific summary statistics ([`endpointPopulationCounts`](@ref), [`endpointPopulationFractions`](@ref), [`meanPopulationTimeSeries`](@ref)).

## Quick start

```julia
using PhysiCellModelManager
using Distributions

# 1. Model inputs — fix non-calibrated parameters via a reference monad
inputs  = InputFolders("default", "default")
dv_time = DiscreteVariation(configPath("overall", "max_time"), 1440.0)
ref     = createTrial(inputs, [dv_time]; n_replicates = 0)

# 2. Parameters to infer, with priors from Distributions.jl
parameters = [
    DistributedVariation(
        configPath("cancer", "apoptosis", "rate"),
        Uniform(1e-4, 5e-3);
        name = "apoptosis_rate"
    ),
    DistributedVariation(
        configPath("cancer", "cycle", "duration", 0),
        Uniform(480.0, 1440.0);
        name = "cycle_duration"
    ),
]

# 3. Observed data — must match the return type of your summary statistic
observed_data = Dict("cancer" => 3500.0, "immune" => 800.0)

# 4. Build the problem
problem = CalibrationProblem(
    ref,                        # Monad — sets inputs + reference_variation_id
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
df, weights = posterior(result)                    # final generation
df3, w3     = posterior(result; generation = 3)   # specific earlier generation
```

## Defining the calibration problem

[`CalibrationProblem`](@ref) bundles everything the calibration loop needs.
There are two constructor forms depending on whether you need to fix non-calibrated parameters.

### Simple form — `InputFolders` as first argument

All parameters start from their XML-file defaults:

```julia
problem = CalibrationProblem(
    inputs,              # InputFolders
    parameters,          # Vector of DistributedVariation / CoVariation / LatentVariation
    observed_data,       # Dict{String,<:Any} — the target the model should match
    summary_statistic,   # (monad_id::Int) → Dict{String,<:Any}
    distance;            # (simulated, observed) → Float64
    n_replicates = 1,    # replicates per particle (averaged by the summary statistic)
)
```

### Reference monad form — fixing non-calibrated parameters

Pass a `Monad` (or any result of `createTrial`) as the first argument.
This sets the `inputs` **and** locks all non-calibrated parameters to the monad's variation,
exactly as you would with `run` or `createTrial`:

```julia
# Fix max_time and save interval for every particle evaluation
dv_time     = DiscreteVariation(configPath("overall", "max_time"), 1440.0)
dv_interval = DiscreteVariation(configPath("full_data", "interval"), 60.0)
ref = createTrial(inputs, [dv_time, dv_interval]; n_replicates = 0)

problem = CalibrationProblem(
    ref,                 # Monad — provides both inputs and reference_variation_id
    parameters,
    observed_data,
    summary_statistic,
    distance;
    n_replicates = 3,
)
```

`n_replicates = 0` on `createTrial` creates the monad entry without running any simulations — it only reserves the variation ID.

### Parameters

Any `DistributedVariation`, `CoVariation{DistributedVariation}`, or `LatentVariation` can be a calibration parameter.
Priors come from `Distributions.jl`.

```julia
# Single XML path with a continuous prior
dv = DistributedVariation(configPath("default", "migration", "speed"), LogNormal(0.0, 1.0))

# Two parameters that move together (CoVariation)
cv = CoVariation([
    DistributedVariation(configPath("cancer", "birth", "rate"),  Uniform(0.01, 0.1)),
    DistributedVariation(configPath("cancer", "death", "rate"),  Uniform(0.001, 0.05)),
])

# Latent variation: one scalar controls multiple XML paths through user-supplied maps
lv = LatentVariation(
    [Uniform(0.0, 1.0)],
    [configPath("cancer", "apoptosis", "rate"), configPath("immune", "apoptosis", "rate")],
    [u -> 1e-4 * exp(5*u[1]), u -> 5e-5 * exp(5*u[1])];
    name = "apoptosis_scale",
    target_names = ["cancer_apoptosis", "immune_apoptosis"],
    inverse_maps = [v -> log(v[1] / 1e-4) / 5],
)
```

!!! warning "LatentVariation requires `inverse_maps` to use the simulation bank"
    For `DistributedVariation` and `CoVariation` parameters, inverse maps are constructed automatically.
    For `LatentVariation`, they must be supplied explicitly via the `inverse_maps` keyword.

    Without `inverse_maps`, the simulation bank (`cdf_grid_k`) is **silently disabled** for the
    entire calibration: proposals cannot be matched to existing monads, so every proposal triggers
    a new simulation.

    Supply one inverse map per latent dimension — it should satisfy `inverse_maps[i](maps[i](u)) ≈ u`:

    ```julia
    lv = LatentVariation(
        [Uniform(0.0, 1.0)],
        [configPath("cancer", "apoptosis", "rate")],
        [u -> 1e-4 * exp(5*u[1])];
        inverse_maps = [v -> log(v[1] / 1e-4) / 5],  # enables simulation bank
    )
    ```

    If you do not need the bank (i.e. `cdf_grid_k` is not set), omitting `inverse_maps` is harmless.

### Summary statistics

A summary statistic is any function `(monad_id::Int) → Dict{String,<:Any}`.
The three built-in statistics are described in [Built-in summary statistics](@ref builtin_ss).

You can supply a custom function instead:

```julia
function my_stat(monad_id::Int)
    # load your own output files via the monad's simulation IDs
    sim_ids = simulationIDs(Monad(monad_id))
    # ... compute your statistic ...
    return Dict("metric_a" => value_a, "metric_b" => value_b)
end

problem = CalibrationProblem(inputs, params, observed, my_stat, mseDistance)
```

The distance function is called as `distance(simulated, observed_data) → Float64`, where `simulated` is the direct return value of `summary_statistic` and `observed_data` is whatever you passed into `CalibrationProblem`. Both can be any type — your distance function just needs to handle them. `mseDistance` accepts dicts, vectors, and scalars; when using it with dicts, the keys of `observed_data` must be a subset of the keys returned by `summary_statistic`.

### Distance functions

A distance function is any `(simulated, observed) → Float64` — the types of both arguments are whatever your `summary_statistic` returns and whatever you set `observed_data` to.
[`mseDistance`](@ref) is the built-in option and handles dicts, vectors, and scalars. A custom function can work with any types:

```julia
# Dict-based: weighted MSE on two cell populations
function my_dist(sim, obs)
    return 0.9 * (sim["cancer"] - obs["cancer"])^2 +
           0.1 * (sim["immune"] - obs["immune"])^2
end

# Vector-based: L2 norm on a time series
function ts_dist(sim_vec::Vector{Float64}, obs_vec::Vector{Float64})
    return sum((sim_vec .- obs_vec).^2) / length(obs_vec)
end
```

## Running calibration

### `runABC` — convenience entry point

```julia
result = runABC(problem;
    population_size    = 200,
    max_nr_populations = 15,
    minimum_epsilon    = 0.05,
    description        = "my run",
)
```

All keyword arguments are forwarded to [`ABCSMC`](@ref). See [ABCSMC settings](@ref abcsmc_settings) for the full list.

### `runCalibration` — explicit method object

For reproducibility or to reuse settings:

```julia
method = ABCSMC(population_size = 200, max_nr_populations = 15, minimum_epsilon = 0.05)
result = runCalibration(problem, method; description = "my run")
```

## [ABCSMC settings](@id abcsmc_settings)

All fields have defaults and are specified as keyword arguments:

| Field | Default | Description |
|-------|---------|-------------|
| `population_size` | `100` | Accepted particles per generation |
| `max_nr_populations` | `10` | Maximum number of generations |
| `minimum_epsilon` | `0.01` | Stop when ε reaches this value |
| `epsilon_quantile` | `0.5` | Quantile of accepted distances used to set the next ε (default: median) |
| `perturbation_kernel` | `GaussianKernel()` | Proposal kernel; see [Perturbation kernels](@ref perturbation_kernels_calibration) |
| `epsilon_schedule` | `nothing` | Manual ε sequence overriding adaptive rule; see below |
| `min_acceptance_rate` | `0.0` (off) | Stop when acceptance rate drops below this fraction |
| `min_epsilon_decrease` | `0.0` (off) | Stop when relative ε decrease falls below this fraction |
| `min_ess_fraction` | `0.0` (off) | Stop when ESS / population_size falls below this fraction |
| `accept_overflow` | `false` | Keep all particles passing ε, not just `population_size` |
| `cdf_grid_k` | `nothing` (off) | Enable simulation bank with dyadic-grid snapping at depth `k`; see below |
| `max_evaluations` | `nothing` (off) | Hard budget cap on total particle evaluations |

### Manual epsilon schedule

Supply a strictly decreasing vector to drive ε by hand instead of letting the algorithm adapt it:

```julia
method = ABCSMC(
    population_size  = 100,
    epsilon_schedule = [100.0, 30.0, 10.0, 3.0, 1.0],
)
```

Generation `t` uses `epsilon_schedule[t-1]`; the schedule takes precedence over `epsilon_quantile`.
`min_acceptance_rate` is useful as a safety stop alongside a schedule.

### Simulation bank and CDF-grid snapping (`cdf_grid_k`)

When `cdf_grid_k = k` is set, ModelManager builds a registry (the *simulation bank*) of all existing monads whose calibrated parameters fall inside the prior support.
For each proposal, it first checks whether any bank entry falls within the grid cell around that proposal; if so, that monad is reused at its actual coordinates with no new simulation.
Only when no bank match is found does the proposal get snapped to the nearest dyadic grid point at depth `k`, where a new simulation is run (or an exact match from a previous calibration is reused).
The grid refines each generation (`k_eff = k + t − 1`), tracking the narrowing posterior.

```julia
method = ABCSMC(population_size = 200, max_nr_populations = 10, cdf_grid_k = 3)
```

### Evaluation budget (`max_evaluations`)

A hard cap on the total number of particle evaluations across the entire run, regardless of generation count:

```julia
method = ABCSMC(population_size = 100, max_nr_populations = 20, max_evaluations = 5000)
```

The current generation's accepted particles are saved before stopping.

## [Perturbation kernels](@id perturbation_kernels_calibration)

The kernel controls how generation-t+1 proposals are generated from generation-t particles.
Pass it as `perturbation_kernel` to `ABCSMC` or `runABC`.

| Kernel | When to use |
|--------|-------------|
| [`GaussianKernel`](@ref) (default) | Low-dimensional problems with roughly elliptical posteriors |
| [`ComponentwiseKernel`](@ref) | High dimensions where full covariance estimation is noisy |
| [`LocalNNKernel`](@ref) | Posteriors that concentrate at different rates in different regions |
| [`LocalNNCovKernel`](@ref) | Strongly anisotropic or banana-shaped posteriors |

```julia
# Full covariance Gaussian (default)
method = ABCSMC(perturbation_kernel = GaussianKernel())

# Diagonal — independent per-parameter bandwidths
method = ABCSMC(perturbation_kernel = ComponentwiseKernel())

# Local bandwidth based on k nearest neighbours
method = ABCSMC(perturbation_kernel = LocalNNKernel(k = 15))

# Local covariance based on k nearest neighbours
method = ABCSMC(perturbation_kernel = LocalNNCovKernel(k = 15))
```

Both `GaussianKernel` and `ComponentwiseKernel` accept an optional `scale` multiplier (default `2.0`) applied to the weighted (co)variance:

```julia
GaussianKernel(1.0)          # scale = 1 × covariance
GaussianKernel([1.0, 2.0])   # per-generation scale vector
```

## The ABC-SMC algorithm

Each generation proceeds as follows:

1. **Propose** `population_size` particles
   - Generation 1: draw a Sobol low-discrepancy sequence in the unit hypercube `(0,1)^d` (one dimension per parameter), then map each coordinate through its prior CDF to obtain parameter values. This gives better prior coverage than random sampling.
   - Generation *t > 1*: systematically resample a parent from the previous (weighted) generation and perturb it with the fitted perturbation kernel.
2. **Evaluate** each proposed particle
   - Create a `Monad` at the proposed parameter values (reusing existing simulations where possible via `use_previous=true`).
   - Run the simulations quietly (per-simulation output is suppressed during calibration).
   - Apply the user's `summary_statistic` and `distance` to produce a scalar distance.
3. **Accept** particles whose distance is below the current `epsilon`. In generation 1 all proposals are kept; in later generations a rejection step is used.
4. **Reweight** using the standard ABC-SMC importance weights.
5. **Adapt** the next generation's epsilon as the `epsilon_quantile` quantile of the current accepted distances, never dropping below `minimum_epsilon`.
6. **Save** the generation to disk (see below) and check stopping criteria.

### On warm-starting from existing simulations

ModelManager does **not** seed generation 1 with pre-existing simulations. Doing so would bias the gen-1 population away from the prior (e.g., if prior sweeps or sensitivity designs were clustered at particular values). Instead, every gen-1 particle is placed via the Sobol sequence, giving a fresh, well-dispersed prior sample.

`Monad(...; use_previous=true)` is used internally for every particle, so any exact-match parameter point that already exists in the database is reused for free.

When `cdf_grid_k` is set, the simulation bank goes further: at calibration start it queries **all** existing monads in the database (from prior sweeps, sensitivity analyses, previous calibration runs, etc.) whose calibrated parameters fall inside the prior support. These are indexed in a KD-tree and consulted at every proposal — for any generation. If a proposal snaps to a grid cell already covered by an existing monad, that monad is reused directly with no new simulation required. This is the practical mechanism for leveraging prior computational work.

## Resuming a calibration

If a calibration is interrupted (crash, user stop, HPC timeout), the completed generations are already saved on disk. Use [`resumeABC`](@ref) to continue:

```julia
# Load the calibration by ID and continue from where it left off
calibration = Calibration(42)
result = resumeABC(calibration)

# Override settings — e.g. allow more generations than the original run
result = resumeABC(calibration; method = ABCSMC(population_size=200, max_nr_populations=20))

# If the original problem used anonymous functions (not serializable), re-supply it:
result = resumeABC(calibration; problem = problem)
```

The original [`CalibrationProblem`](@ref) is loaded automatically from `problem.jld2` in the calibration folder. The original settings are restored from `method.toml` unless overridden. Both `problem` and `method` are keyword arguments.

### Resumability and anonymous functions

!!! warning "Use named functions for full resumability"
    ModelManager serializes the `CalibrationProblem` to `problem.jld2` at the start of each run.
    **Anonymous functions** (including lambda-style `x -> ...` and closures that capture variables)
    **cannot be serialized** and are stored as `nothing` in the saved manifest.

    The following fields are affected:
    - `summary_statistic` — e.g. `m -> Dict(...)` in the `CalibrationProblem` call
    - `distance` — e.g. `(s, o) -> sum(...)` in the `CalibrationProblem` call
    - `LatentVariation` map functions (`maps` and `inverse_maps`) — if any are anonymous

    If any of these are anonymous, `problem.jld2` is incomplete, and `resumeABC` will throw an
    error unless you re-supply the problem explicitly:

    ```julia
    result = resumeABC(Calibration(42); problem = problem)
    ```

    To avoid this requirement entirely, use named functions — either built-ins passed directly,
    or functions defined at module level in your script:

    ```julia
    # ✓  Built-ins are named functions — pass them directly
    problem = CalibrationProblem(ref, params, observed, endpointPopulationCounts, mseDistance)

    # ✓  Custom logic: define at module level (not inside another function or as a lambda)
    function my_stat(monad_id::Int)
        counts = endpointPopulationCounts(monad_id)
        # ... transform as needed ...
        return counts
    end

    apoptosis_map(u) = 1e-4 * exp(5*u[1])
    apoptosis_inv(v) = log(v[1] / 1e-4) / 5

    lv = LatentVariation(
        [Uniform(0.0, 1.0)],
        [configPath("cancer", "apoptosis", "rate")],
        [apoptosis_map];
        inverse_maps = [apoptosis_inv],
    )

    # ✗  Anonymous: problem.jld2 will be incomplete
    problem = CalibrationProblem(ref, params, observed,
        m -> endpointPopulationCounts(m),   # anonymous — not serializable
        mseDistance)
    ```

## Inspecting results

### Posterior samples

```julia
# From a live ABCResult
df, weights = posterior(result)                   # final generation
df3, w3     = posterior(result; generation = 3)   # any earlier generation

# From just a calibration ID (after a session restart)
df, weights = posterior(Calibration(42))
df, weights = posterior(Calibration(42); generation = 3)
```

`df` is a `DataFrame` with one column per calibrated parameter (display names), one row per particle.
`weights` is a `Vector{Float64}` summing to 1.

### Convergence diagnostics

[`ConvergenceSummary`](@ref) collects per-generation statistics into a table:

```julia
cs = ConvergenceSummary(result)
# or, from a calibration ID after a session restart:
cs = ConvergenceSummary(Calibration(42))
```

Columns: `t`, `epsilon`, `acceptance_rate`, `n_accepted`, `ess`, `ess_fraction`, `n_evaluations`.

### Visualization

Requires a Plots.jl backend (e.g. `using Plots`).

```julia
# Corner (pairs) plot of the final-generation posterior
plot(result)
plot(result; generation = 3)       # specific generation
plot(result; space = :cdf)         # CDF coordinates (should be ≈ Uniform for a good fit)

# Posterior narrowing across generations (one panel per parameter)
plot(result, :ridgeline)

# Convergence trace (epsilon, acceptance rate, ESS fraction)
plot(ConvergenceSummary(result))

# Generation-transition plot: gen-t posterior + gen-(t+1) proposals (accepted=green, rejected=red)
plot(result, :transition)                  # last complete transition
plot(result, :transition; generation = 2)  # specific transition t → t+1
```

All plots also work with a `Calibration` object instead of an `ABCResult`, loading data from disk:

```julia
plot(Calibration(42))
plot(Calibration(42), :ridgeline)
```

## Output layout

Each calibration run creates `data/outputs/calibrations/{id}/` with:

- `method.toml` — the [`ABCSMC`](@ref) settings (restored automatically by `resumeABC`).
- `problem.jld2` — the serialized [`CalibrationProblem`](@ref) (restored automatically by `resumeABC`; contains a partial manifest if the problem used anonymous functions).
- `parameters.toml` — human-readable mapping from display column names to prior strings, for quick inspection.
- `generations/generation_{t}.csv` — one file per completed generation. Columns: each parameter's display name, plus `weight`, `distance`, `monad_id`.
- `generations/generation_{t}_monads.csv` — all monad IDs evaluated during generation `t` (written before simulations run, for crash safety and the `:transition` plot).
- `generations/generation_cdfs/generation_{t}.csv` — raw CDF coordinates used internally by `resumeABC` for exact particle reconstruction.

## [Built-in summary statistics](@id builtin_ss)

Three built-in summary statistics accept a monad ID and return a `Dict` suitable for the `summary_statistic` argument of [`CalibrationProblem`](@ref).

### `endpointPopulationCounts`

```julia
endpointPopulationCounts(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type to its mean population count at the final simulation time point, averaged across all replicates.
Returns `missing` if no simulation output is available.

### `endpointPopulationFractions`

```julia
endpointPopulationFractions(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type to its **fraction** of the total live cell population at the final time point, averaged across replicates.
Returns `missing` if no simulation output is available.

### `meanPopulationTimeSeries`

```julia
meanPopulationTimeSeries(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Vector{Float64}}` mapping each cell type to a vector of mean population counts across all output time points.
Useful when `observed_data` is a time series rather than a single endpoint value.

For all three statistics, pass `cell_types = ["cancer", "immune"]` to restrict the output to specific cell types.

## Built-in distance functions

### `mseDistance`

```julia
mseDistance(simulated, observed)
```

Computes the mean squared error between `simulated` and `observed`. Accepts dicts, vectors, or scalars:
- **Dicts** (`Dict{String,<:Any}`): per-key MSE contributions are averaged across all keys in `observed`. Values may be scalars or vectors.
- **Vectors**: element-wise MSE averaged over the length of `observed`.
- **Scalars**: squared error.
