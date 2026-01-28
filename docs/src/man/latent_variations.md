# LatentVariations
Extending the concept of [CoVariations`](@ref), sometimes several parameters need to be varied together according to some underlying latent parameters.
The motivating use case is varying thresholds to create low-medium-high regimes for a signal response.
In this case, the high threshold must always be greater than the low threshold.
Thus, if you want to vary both thresholds independently, you need to impose a constraint that the high threshold is always greater than the low threshold.
A [`LatentVariation`](@ref) can handle this by introducing **latent parameters** that are then mapped to the **target parameters**.
Thus, to construct a `LatentVariation`, you need to provide:
- Latent parameters with each as either
  - a vector of discrete values
  - a probability distribution from which values can be drawn
- Target parameters provided as a vector of XML paths as done for other `ElementaryVariation`'s
- Mapping functions that map the latent parameters to each target parameter
- (Optional) Human-interpretable names for the latent parameters

## Mappings
For each target parameter, you must provide a mapping function that **takes as input a vector of latent parameter values** and returns the corresponding target parameter value.
Again, the input to the mapping function **must be a vector of latent parameter values**, even if there is only one latent parameter.
The order of the latent parameter values in the input vector corresponds to the order of the latent parameters provided when constructing the `LatentVariation`.
The mapping functions can be as simple or complex as needed, as long as they return a single, value for the target parameter.

## Latent Parameter Names
You can optionally provide human-interpretable names for the latent parameters.
These names will be used in the display of the `LatentVariation` to help identify the latent parameters.
This can be especially useful when looking over results of sensitivity analyses or optimization runs that use `LatentVariation`'s.
If none are provided, the latent parameters will be named according to the target parameters and their index in the latent parameter vector.
See [`defaultLatentParameterNames`](@ref) for the default naming scheme.

## `LatentVariation{Vector{<:Real}}`
If the latent parameters are provided as vectors of discrete values, then the `LatentVariation` is parameterized as `LatentVariation{Vector{<:Real}}`.
The lengths of the latent parameter vectors do not need to be the same.
When values are requested from the `LatentVariation`, PhysiCellModelManager.jl will use all combinations of the latent parameter values to compute the corresponding target parameter values.

```jldoctest
using PhysiCellModelManager
latent_parameters = [[0.2, 0.4], [0.1, 0.2, 0.3]] # two latent parameters: one setting the bottom threshold and one setting the threshold gap
latent_parameter_names = ["bottom_threshold", "threshold_gap"] # optional, human-interpretable names for the latent parameters
targets = [configPath("default", "custom:signal_threshold_low"),
           configPath("default", "custom:signal_threshold_high")]
maps = [lp -> lp[1], # map the first latent parameter to the custom:signal_threshold_low
        lp -> lp[1] + lp[2]] # map the sum of the two latent parameters to the custom:signal_threshold_high
LatentVariation(latent_parameters, targets, maps, latent_parameter_names)
# output
LatentVariation (Discrete), 2 -> 2:
-----------------------------------
  Latent Parameters (n = 2):
    lp#1. bottom_threshold ([0.2, 0.4])
    lp#2. threshold_gap ([0.1, 0.2, 0.3])
  Target Parameters (n = 2):
    tp#1. default: signal threshold low
            Location: config
            Target: XMLPath: cell_definitions/cell_definition:name:default/custom_data/signal_threshold_low
    tp#2. default: signal threshold high
            Location: config
            Target: XMLPath: cell_definitions/cell_definition:name:default/custom_data/signal_threshold_high
```

## `LatentVariation{Distribution}`
If the latent parameters are provided as probability distributions, then the `LatentVariation` is parameterized as `LatentVariation{Distribution}`.
When values are requested from the `LatentVariation`, PhysiCellModelManager.jl will draw samples from each of the latent parameter distributions and compute the corresponding target parameter values.

```jldoctest
using PhysiCellModelManager, Distributions
latent_parameters = [Uniform(0.0, 1.0), truncated(Normal(0.5, 0.1); lower=0)] # two latent parameters: one setting the bottom threshold and one setting the threshold gap
latent_parameter_names = ["bottom_threshold", "threshold_gap"] # optional, human-interpretable names for the latent parameters
targets = [configPath("default", "custom:signal_threshold_low"),
           configPath("default", "custom:signal_threshold_high")]
maps = [lp -> lp[1], # map the first latent parameter to the custom:signal_threshold_low
        lp -> lp[1] + lp[2]] # map the sum of the two latent parameters to the custom:signal_threshold_high
LatentVariation(latent_parameters, targets, maps, latent_parameter_names)
# output
LatentVariation (Distribution), 2 -> 2:
---------------------------------------
  Latent Parameters (n = 2):
    lp#1. bottom_threshold (Distributions.Uniform{Float64}(a=0.0, b=1.0))
    lp#2. threshold_gap (Truncated(Distributions.Normal{Float64}(μ=0.5, σ=0.1); lower=0.0))
  Target Parameters (n = 2):
    tp#1. default: signal threshold low
            Location: config
            Target: XMLPath: cell_definitions/cell_definition:name:default/custom_data/signal_threshold_low
    tp#2. default: signal threshold high
            Location: config
            Target: XMLPath: cell_definitions/cell_definition:name:default/custom_data/signal_threshold_high
```