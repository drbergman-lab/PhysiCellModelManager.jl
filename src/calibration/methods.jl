export AbstractCalibrationMethod, ABCSMC, runCalibration

"""
    AbstractCalibrationMethod

Abstract supertype for calibration methods. Concrete subtypes define the algorithm
and its settings.

Current implementations:
- [`ABCSMC`](@ref): Approximate Bayesian Computation — Sequential Monte Carlo

Future implementations may include GP-accelerated ABC, Bayesian optimization, etc.
"""
abstract type AbstractCalibrationMethod end

"""
    ABCSMC

Settings for ABC-SMC (Approximate Bayesian Computation — Sequential Monte Carlo)
calibration (Toni et al. 2009, Beaumont et al. 2009).

# Fields
- `population_size::Int`: Number of accepted particles per generation (default `100`).
- `max_nr_populations::Int`: Maximum number of SMC generations (default `10`).
- `minimum_epsilon::Float64`: Stop when the acceptance threshold drops below this (default `0.01`).
- `epsilon_quantile::Float64`: Quantile of accepted distances used to adapt epsilon between
  generations (default `0.5`, i.e. median).
- `perturbation_kernel::Symbol`: Kernel for perturbing resampled particles. Currently
  only `:gaussian` is supported (default `:gaussian`).

# Examples
```julia
method = ABCSMC(population_size=200, max_nr_populations=15, minimum_epsilon=0.005)
result = runCalibration(problem, method)
```
"""
struct ABCSMC <: AbstractCalibrationMethod
    population_size::Int
    max_nr_populations::Int
    minimum_epsilon::Float64
    epsilon_quantile::Float64
    perturbation_kernel::Symbol
end

function ABCSMC(; population_size::Int=100, max_nr_populations::Int=10,
                  minimum_epsilon::Float64=0.01, epsilon_quantile::Float64=0.5,
                  perturbation_kernel::Symbol=:gaussian)
    population_size > 0 || throw(ArgumentError("population_size must be positive, got $population_size"))
    max_nr_populations > 0 || throw(ArgumentError("max_nr_populations must be positive, got $max_nr_populations"))
    minimum_epsilon >= 0 || throw(ArgumentError("minimum_epsilon must be non-negative, got $minimum_epsilon"))
    0 < epsilon_quantile < 1 || throw(ArgumentError("epsilon_quantile must be in (0, 1), got $epsilon_quantile"))
    perturbation_kernel === :gaussian || throw(ArgumentError("Only :gaussian perturbation kernel is supported, got :$perturbation_kernel"))
    return ABCSMC(population_size, max_nr_populations, minimum_epsilon, epsilon_quantile, perturbation_kernel)
end

"""
    runCalibration(problem::CalibrationProblem, method::AbstractCalibrationMethod; description="") → ABCResult

Run calibration using the specified method. Dispatches to the method-specific implementation.

See [`ABCSMC`](@ref) for the ABC-SMC method and its keyword arguments.

# Examples
```julia
method = ABCSMC(population_size=200, max_nr_populations=5)
result = runCalibration(problem, method; description="my calibration run")
df, weights = posterior(result)
```
"""
function runCalibration end
