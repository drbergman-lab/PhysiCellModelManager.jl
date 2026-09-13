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
    endpointPopulationCountQoI(),  # summary statistic (QoI form — see below)
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
Fix non-calibrated parameters by passing a reference `Monad` instead of `InputFolders`; ModelManager also accepts a `StudySpec`.

### Simple form — `InputFolders` as first argument

All parameters start from their XML-file defaults:

```julia
problem = CalibrationProblem(
    inputs,              # InputFolders
    parameters,          # Vector of DistributedVariation / CoVariation / LatentVariation
    observed_data,       # whatever your distance's second argument expects (Dict, Vector, or scalar)
    summary_statistic,   # a QoI, a vector of QoIs, or a plain (sim::Simulation) -> value
    distance;            # (simulated, observed) → Float64
    n_replicates = 1,    # replicates per particle (combined by the QoI's `reduce`; mean by default)
)
```

### Reference monad form — fixing non-calibrated parameters

Pass a `Monad` as the first argument. The reference has to fix each non-calibrated parameter to a single value, so build it from single-valued variations — a multi-valued one yields a `Sampling`, which this constructor does not accept.
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

A summary statistic measures **one simulation**; ModelManager combines a parameter set's replicates
for you. Pass a [`QoI`](@ref ModelManager.QoI), a vector of them, or a plain function of a
`Simulation`:

```julia
function my_stat(sim::Simulation)
    # ... measure this one simulation ...
    return value
end

problem = CalibrationProblem(inputs, params, observed, my_stat, mseDistance)
```

A plain function is averaged across replicates with `mean`; pass a `QoI` when you need a different
reduction, or when the quantity must be computed *after* the replicates are combined rather than
before.

!!! warning "Changed in ModelManager 0.9"
    Summary statistics used to be called once per **monad**, with an `Int` monad ID, and did their
    own aggregation. Such a function now receives a `Simulation`. If it is untyped it will return a
    different number rather than erroring, so annotate the argument `::Simulation` — ModelManager
    warns when it is not declared. The three built-in statistics below remain monad-level and are no
    longer valid `summary_statistic` arguments; use their [QoI form](@ref qoi_form_ss) instead.

The built-in measurements are described in [Built-in summary statistics](@ref builtin_ss).

The keys of `observed_data` are the comparison: `mseDistance` resolves each one in the simulated summary, an observed key the summary statistic did not produce is an error rather than a silent zero, and an extra simulated component is ignored — a simulation is always known better than the data.

### Distance functions

A distance function is any `(simulated, observed) → Float64`. `simulated` is a [`SummaryValues`](@ref) holding what each QoI's `reduce` returned; index it by cell type (`sim["cancer"]`) while only one QoI reports that key, or by `"<qoi name>.<key>"` when several do. `observed` is whatever you set `observed_data` to. [`mseDistance`](@ref) is the built-in option; a custom function can use any types:

```julia
# Weighted MSE on two cell populations
function my_dist(sim, obs)
    return 0.9 * (sim["cancer"] - obs["cancer"])^2 +
           0.1 * (sim["immune"] - obs["immune"])^2
end

# L2 norm on one cell type's time series (the shape meanPopulationTimeSeriesQoI produces)
function ts_dist(sim, obs)
    return sum((sim["tumor"] .- obs["tumor"]).^2) / length(obs["tumor"])
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

Method settings may be given either as loose keywords naming [`ABCSMC`](@ref) fields (as above) or as a ready-made `method =` object, but not both. Alongside them `runABC` takes its own run controls — `description`, `tags`, `run_kwargs`, `progress`, `on_monad_failure`. See [ABCSMC settings](@ref abcsmc_settings).

### `runCalibration` — explicit method object

For reproducibility or to reuse settings:

```julia
method = ABCSMC(population_size = 200, max_nr_populations = 15, minimum_epsilon = 0.05)
result = runCalibration(method, problem; description = "my run")
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
| `store_rejected` | `false` | Persist rejected proposals, so `plot(result, :transition; space = :cdf)` can show them |

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

The cap is applied before each batch of proposals is dispatched: a batch that would exceed the budget is trimmed to exactly the remaining allowance, so the run never evaluates more than `max_evaluations` particles. As a result, the final generation may hold fewer than `population_size` particles (and if `max_evaluations` is smaller than `population_size`, even the first generation is trimmed). The current generation's accepted particles are saved before stopping.

!!! note "Budget counts particles, not simulations"
    Each particle evaluation is one `Monad`, and PCMM runs `n_replicates` simulations per monad (set on the [`CalibrationProblem`](@ref)). So `max_evaluations` bounds the number of *particles*, and a calibration launches up to `max_evaluations × n_replicates` PhysiCell simulations. For example, `max_evaluations = 5000` with `n_replicates = 3` can launch up to 15,000 simulations — size the budget with your replicate count in mind.

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

When `cdf_grid_k` is set, the simulation bank goes further: at calibration start it queries **all** existing monads in the database (from prior sweeps, sensitivity analyses, previous calibration runs, etc.) whose calibrated parameters fall inside the prior support. Only monads with at least one simulation running or completed are eligible — one whose simulations never started has nothing to reuse. These are indexed in a KD-tree and consulted at every proposal — for any generation. If a proposal snaps to a grid cell already covered by an existing monad, that monad is reused directly with no new simulation required. This is the practical mechanism for leveraging prior computational work.

## Resuming a calibration

If a calibration is interrupted (crash, user stop, HPC timeout), the completed generations are already saved on disk. Use [`resumeABC`](@ref) to continue:

```julia
# Load the calibration by ID and continue from where it left off
calibration = Calibration(42)
result = resumeABC(calibration)

# Patch one setting — e.g. allow more generations than the original run
result = resumeABC(calibration; max_nr_populations = 20)

# If the original problem used anonymous functions (not serializable), re-supply it:
result = resumeABC(calibration; problem = problem)
```

The original [`CalibrationProblem`](@ref) is loaded automatically from `problem.jld2` in the calibration folder, and the settings from `method.toml`.

!!! warning "`method =` replaces; keywords patch"
    An `ABCSMC` object supplies *every* field, so `method = ABCSMC(max_nr_populations=20)` silently
    resets population size, kernel, epsilon rule and the rest to constructor defaults rather than
    the values the run used. To change some settings and keep the rest, pass them as keywords, as
    above. Passing both a `method` object and individual settings is an error.

### Resumability and anonymous functions

!!! warning "Pass `problem=` when resuming a PCMM calibration"
    ModelManager saves the `CalibrationProblem` to `problem.jld2` at the start of each run, and can
    restore a function from it only when JLD2 can name it: a function defined at the top level of a
    file or module. A lambda or closure — including a named function defined *inside* another
    function — is saved as `nothing`, and a bare `resumeABC(Calibration(42))` then refuses with
    "problem.jld2 contains only a partial manifest". Re-supply the problem:

    ```julia
    result = resumeABC(Calibration(42); problem = problem)
    ```

    **PCMM's QoI builders are closures** — `endpointPopulationCountQoI()` captures `cell_types` and
    `include_dead` — so every calibration built from them needs `problem=` today (making them
    restorable is issue #234). `mseDistance`, a top-level `my_stat`, and top-level `LatentVariation`
    maps restore on their own:

    ```julia
    # Custom logic: define at module level (not inside another function or as a lambda).
    # A summary statistic measures ONE simulation; the library reduces the replicates.
    function my_stat(sim::Simulation)
        counts = finalPopulationCount(sim)
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

    # Anonymous: problem.jld2 will be incomplete, so keep `problem` for `resumeABC`
    problem = CalibrationProblem(ref, params, observed,
        sim -> finalPopulationCount(sim),   # a lambda cannot be restored by name
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

Columns: `t`, `max_epsilon_accepted`, `epsilon_threshold`, `acceptance_rate`, `n_accepted`, `ess`, `ess_fraction`, `n_evaluations`. ModelManager 0.9 split the single `epsilon` in two: `max_epsilon_accepted` is the largest distance the generation actually accepted, `epsilon_threshold` the value it ran against (`nothing` for generation 1, which accepts everything).

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

Each calibration run creates `data/outputs/calibrations/{id}/`: three files describing the run, then
one folder per generation.

```
data/outputs/calibrations/1/
├── problem.jld2          # the serialized CalibrationProblem, so a resume needs no re-supplied problem
├── method.toml           # the ABCSMC settings
├── parameters.toml       # display name → database column → prior, per parameter
└── generations/
    ├── 01/
    │   ├── particles.csv          # accepted particles, in target space
    │   ├── cdfs.csv               # the same particles in CDF space
    │   ├── metadata.toml          # both epsilons, ESS, acceptance rate, evaluation count
    │   ├── monads.csv             # every monad evaluated, as compressed ID ranges
    │   ├── proposals.csv          # distance and outcome for every proposal
    │   ├── failed_simulations.csv # only when a simulation failed
    │   └── failed_monads.csv      # only when a monad lost every simulation
    ├── 02/
    └── …
```

The folder name is the generation number, zero-padded to fit `max_nr_populations`.

Calibrations written before ModelManager 0.9 stored the same artifacts as flat files
(`generation_01.csv`, `generation_01_monads.csv`, and a `generation_cdfs/` subdirectory). Those are
read as they are, and are moved into the folder layout the first time the run is resumed.

ModelManager owns this layout and documents it in full — including what each column means — under
[What a run leaves on disk](https://drbergman-lab.github.io/ModelManager.jl/stable/man/calibration/#What-a-run-leaves-on-disk).

## [Built-in summary statistics](@id builtin_ss)

Three built-in **monad-level** statistics accept a monad ID and return a `Dict`. They do their own
averaging over a monad's replicates, which is what makes them useful for analysing a finished monad
directly.

!!! warning "These are not `summary_statistic` arguments"
    Since ModelManager 0.9 a `summary_statistic` measures a single [`Simulation`](@ref) and
    ModelManager reduces the replicates. Passing one of these three to
    [`CalibrationProblem`](@ref) fails when the first monad is measured. Use the
    [QoI form](@ref qoi_form_ss) below, which measures the same quantities in that shape.

### [`endpointPopulationCounts`](@id endpoint_population_counts_section)

```julia
endpointPopulationCounts(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type to its mean population count at the final simulation time point, averaged across all replicates.
Returns `missing` if no simulation output is available.

### [`endpointPopulationFractions`](@id endpoint_population_fractions_section)

```julia
endpointPopulationFractions(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type to its **fraction** of the total live cell population at the final time point, averaged across replicates.
Returns `missing` if no simulation output is available.

### [`meanPopulationTimeSeries`](@id mean_population_time_series_section)

```julia
meanPopulationTimeSeries(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Vector{Float64}}` mapping each cell type to a vector of mean population counts across all output time points.
Useful when `observed_data` is a time series rather than a single endpoint value.

For all three statistics, pass `cell_types = ["cancer", "immune"]` to restrict the output to specific cell types.

### [QoI form](@id qoi_form_ss)

Each statistic also has a builder returning a [`QoI`](@ref ModelManager.QoI), so the same
measurement serves a `CalibrationProblem` without being rewritten:

```julia
problem = CalibrationProblem(inputs, params, observed, endpointPopulationCountQoI(), mseDistance)
```

[`endpointPopulationFractionQoI`](@ref) and [`meanPopulationTimeSeriesQoI`](@ref) are the other two. Each yields a `Dict` keyed by cell type — the same shape as the monad-level statistic above — so `observed_data` does not change between them.

Pass `cell_types` to restrict the measurement; omit it and every cell type present is measured, exactly as the monad-level functions do.

```julia
endpointPopulationCountQoI(; cell_types=["cancer", "immune"])
```

From ModelManager 0.9.1 the two **endpoint** builders — [`endpointPopulationCountQoI`](@ref) and
[`endpointPopulationFractionQoI`](@ref) — also work with `run(::GSAMethod, ...; functions=)`, which
spreads a `Dict`-valued measurement into one sensitivity analysis per key, the same reading the
post-processing sink gives it. So `endpointPopulationCountQoI()` yields one analysis per cell type
without naming them in advance, labelled `endpoint_population_count.<cell_type>`.

[`meanPopulationTimeSeriesQoI`](@ref) does **not**: each of its components is a time series rather
than the `Real` an index is computed from. See
[One measurement, one analysis per cell type](@ref gsa_keyed_qoi).

!!! note "Two builders, two reducers"
    [`populationCountQoI`](@ref) defines no `reduce` of its own, so ModelManager's default per-key
    mean applies wherever it is reduced, and that default refuses a monad whose replicates report
    different cell types. [`endpointPopulationCountQoI`](@ref) measures the same thing at the final
    snapshot and zero-fills a cell type a replicate lacks.

## Built-in distance functions

### [`mseDistance`](@id mse_distance_section)

[`mseDistance`](@ref) walks the keys of `observed_data`: each is resolved in the simulated
[`SummaryValues`](@ref) (an observed key with no simulated counterpart is an error; extra simulated
components are ignored), every squared difference is summed — a time-series value contributes one
difference per time point — and the total is divided by the number of differences computed. A
series key therefore weighs its whole length against an endpoint key's single term; write your own
`distance` to weight them differently. Outside calibration it also compares two dicts, two arrays,
or two scalars; its docstring lists all five forms.
