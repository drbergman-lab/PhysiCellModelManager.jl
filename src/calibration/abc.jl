export runABC

"""
    runABC(problem::CalibrationProblem; kwargs...) → ABCResult

Run ABC-SMC parameter calibration using `pyabc` (Python) via PythonCall.

Each pyabc particle evaluation:
1. Creates a `Monad` with `problem.n_replicates` simulations at the proposed parameter values.
2. Runs any pending simulations (previously proposed identical parameter sets are reused).
3. Passes the monad ID to `problem.summary_statistic` to obtain simulated summary statistics.
4. Returns the distance between simulated and `problem.observed_data` to pyabc.

The calibration is tracked in the PCMM database (`calibrations` table) and all monads
created during the run appear in `data/outputs/monads/` as normal.

# Arguments
- `problem::CalibrationProblem`: The calibration problem definition.

# Keyword Arguments
- `population_size::Int=100`: Number of particles per ABC-SMC generation.
- `max_nr_populations::Int=10`: Maximum number of generations (stopping criterion).
- `minimum_epsilon::Float64=0.01`: Stop when the acceptance threshold drops below this value.
- `description::String=""`: Optional description stored in the `calibrations` DB table.

# Returns
An [`ABCResult`](@ref). Use [`posterior`](@ref) to extract weighted parameter samples.

# Python Environment
Requires `pyabc` to be installed in the Python environment pointed to by
`PCMM_UQ_PYTHON_PATH`. See the calibration documentation for setup instructions.

!!! note "Requires PythonCall extension"
    Both `PythonCall` and `PhysiCellModelManager` must be loaded (in any order) for this
    function to be available.

# Examples
```julia
using PythonCall
using PhysiCellModelManager

result = runABC(problem; population_size=200, max_nr_populations=5)
df, weights = posterior(result)
println("Posterior mean death_rate: ", sum(df.death_rate .* weights))
```
"""
function runABC end
