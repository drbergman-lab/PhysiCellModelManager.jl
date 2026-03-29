# Calibration

PhysiCellModelManager.jl supports Bayesian parameter calibration via the Approximate Bayesian Computation Sequential Monte Carlo (ABC-SMC) algorithm.
ABC-SMC is a likelihood-free inference method that iteratively refines a population of parameter samples (particles) by accepting only those whose simulated outputs are within a shrinking tolerance (epsilon) of the observed data.
It is well-suited to agent-based models where an explicit likelihood function is unavailable or intractable.

## Python environment setup

The ABC-SMC backend is provided by [pyabc](https://pyabc.readthedocs.io/), a Python library.
PhysiCellModelManager.jl calls pyabc through [PyCall.jl](https://github.com/JuliaPy/PyCall.jl).
You must set up a Python environment with pyabc before using the calibration features.

### 1. Create a conda environment

```bash
conda create -n pcmm-uq python=3.10
conda activate pcmm-uq
pip install pyabc
```

### 2. Point PyCall at that environment

Run the following **once per machine** from within your Julia session:

```julia
ENV["PYTHON"] = "/path/to/conda/envs/pcmm-uq/bin/python"
import Pkg; Pkg.build("PyCall")
```

Replace `/path/to/conda/envs/pcmm-uq/bin/python` with the actual path on your machine.
You can find it by running `which python` after activating the `pcmm-uq` environment.

!!! warning "Global side-effect"
    `Pkg.build("PyCall")` modifies the PyCall configuration stored in your **Julia depot** (`~/.julia`), not just the current project.
    This means it affects every Julia project on the machine that uses PyCall.
    If you share a machine or have other projects that rely on a different Python interpreter, take care before rebuilding.
    See the [note on PythonCall.jl](@ref pythoncall-upgrade) below for the planned project-local alternative.

### 3. Optional: set `PCMM_UQ_PYTHON_PATH`

Set the environment variable `PCMM_UQ_PYTHON_PATH` to the path of your conda environment's Python binary.
PhysiCellModelManager.jl will emit a warning at load time if PyCall is using a different interpreter, helping you catch misconfiguration early.

```bash
export PCMM_UQ_PYTHON_PATH="/path/to/conda/envs/pcmm-uq/bin/python"
```

## Activating the extension

`runABC` and `posterior` are provided by a [package extension](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions)) that is activated whenever **both** PyCall and PhysiCellModelManager.jl are loaded in the same Julia session.
The order does not matter:

```julia
using PyCall
using PhysiCellModelManager
```

or equivalently:

```julia
using PhysiCellModelManager
using PyCall
```

As long as both are loaded, the extension is active and `runABC` / `posterior` are available.

## Worked example

The example below calibrates two parameters — a cell apoptosis rate and a cell cycle duration — against observed endpoint population counts.

```julia
using PyCall
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

## [Future upgrade: PythonCall.jl](@id pythoncall-upgrade)

The current PyCall.jl integration has a known limitation: `Pkg.build("PyCall")` is a machine-wide setting that affects all Julia projects.
The planned upgrade is to replace PyCall.jl with [PythonCall.jl](https://github.com/cjdoris/PythonCall.jl), which manages its Python environment on a per-project basis via [CondaPkg.jl](https://github.com/cjdoris/CondaPkg.jl).
This will eliminate the global side-effect and make it possible to specify the exact Python and pyabc versions inside the PCMM project itself.
Until that migration is complete, the conda + PyCall workflow described above is the supported approach.
