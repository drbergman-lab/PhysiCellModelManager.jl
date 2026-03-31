# Calibration(@id calibration_section_man)

PhysiCellModelManager.jl supports Bayesian parameter calibration via the Approximate Bayesian Computation Sequential Monte Carlo (ABC-SMC) algorithm.
ABC-SMC is a likelihood-free inference method that iteratively refines a population of parameter samples (particles) by accepting only those whose simulated outputs are within a shrinking tolerance (epsilon) of the observed data.
It is well-suited to agent-based models where an explicit likelihood function is unavailable or intractable.

## Python environment setup

The ABC-SMC backend is provided by pyabc, a Python library.
PhysiCellModelManager.jl calls pyabc through PythonCall.jl, which uses CondaPkg.jl to manage a project-local Python environment.

In practice, first-time users may need to install pyabc explicitly in the active Julia project environment.

!!! note "First-time setup"
    In a fresh Julia project environment, install pyabc with CondaPkg (one-time per environment):
    ```julia
    pkg> conda pip_add pyabc
    ```
    This takes a few minutes; subsequent loads are instant.

## Activating the extension

`runABC` and `posterior` are provided by a [package extension](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions))
that is activated whenever **both** PythonCall and PhysiCellModelManager.jl are loaded in the
same Julia session. The order does not matter:

```julia
using PythonCall
using PhysiCellModelManager
```

or equivalently:

```julia
using PhysiCellModelManager
using PythonCall
```

As long as both are loaded, the extension is active and `runABC` / `posterior` are available.

## Worked example

The example below calibrates two parameters — a cell apoptosis rate and a cell cycle duration — against observed endpoint population counts.

```julia
using PythonCall
using PhysiCellModelManager
using Distributions

# 1. Define inputs pointing to your model's configuration and custom codes.
inputs = InputFolders("default", "default")

# 2. Define the parameters to infer, each with a prior distribution.
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

# 3. Provide observed data that the summary statistic will be compared against.
#    Here, a Dict of observed endpoint cell counts by cell type.
observed_data = Dict("cancer" => 3500.0, "immune" => 800.0)

# 4. Choose a summary statistic.
#    endpointPopulationCounts returns a Dict{String,Float64} of live cell counts
#    at the end of the simulation for each cell type.
summary_stat = endpointPopulationCounts

# 5. Choose a distance function.
#    mseDistance computes the mean squared error between simulated and observed values.
distance = mseDistance

# 6. Construct the CalibrationProblem.
problem = CalibrationProblem(
    inputs,
    parameters,
    observed_data,
    summary_stat,
    distance;
    n_replicates = 3,           # number of simulation replicates per particle
)

# 7. Run ABC-SMC.
result = runABC(
    problem;
    population_size    = 200,
    max_nr_populations = 15,
    minimum_epsilon    = 0.05,
    description        = "apoptosis-cycle calibration",
)

# 8. Extract the posterior.
df, weights = posterior(result)          # final generation by default
println(df)                              # DataFrame with one column per parameter

# Extract a specific earlier generation (1-indexed).
df_gen3, weights_gen3 = posterior(result; generation = 3)
```

## Built-in summary statistics

PhysiCellModelManager.jl provides three built-in summary statistics that accept a monad ID and return a summary of simulation output.
They are designed to be passed directly as the `summary_statistic` argument of [`CalibrationProblem`](@ref).

### `endpointPopulationCounts`

```julia
endpointPopulationCounts(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type name to its population count at the final simulation time point.

- `cell_types`: restrict output to a subset of cell type names; `nothing` includes all cell types.
- `include_dead`: if `true`, dead cells are included in the count.

### `endpointPopulationFractions`

```julia
endpointPopulationFractions(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Float64}` mapping each cell type name to its **fraction** of the total cell population at the final time point.
Keyword arguments have the same meaning as for `endpointPopulationCounts`.

### `meanPopulationTimeSeries`

```julia
meanPopulationTimeSeries(monad_id; cell_types=nothing, include_dead=false)
```

Returns a `Dict{String,Vector{Float64}}` mapping each cell type name to a vector of mean population counts across all output time points.
This is useful when the observed data is a time series rather than a single endpoint value.

## Built-in distance functions

### `mseDistance`

```julia
mseDistance(simulated, observed)
```

Computes the mean squared error (MSE) between `simulated` and `observed`.
Both scalar and vector (time series) values are supported.
When `simulated` and `observed` are `Dict`s (as produced by the built-in summary statistics), `mseDistance` computes the MSE across all key–value pairs.

