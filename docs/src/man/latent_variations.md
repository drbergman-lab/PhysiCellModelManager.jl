# LatentVariations
[`LatentVariation`](@ref) extends [CoVariations](@ref) to vary parameters together under a constraint. The motivating case is varying low/high thresholds to create low-medium-high regimes, where the high threshold must always exceed the low one. A `LatentVariation` enforces this by introducing **latent parameters** that map to the **target parameters**.

To construct one, provide:
- **Latent parameters** — each a vector of discrete values or a probability distribution.
- **Target parameters** — a vector of XML paths, as for other `ElementaryVariation`s.
- **Mapping functions** — one per target parameter (see below).
- **(Optional)** human-interpretable latent-parameter names, and a `name=...` for the variation itself.

## Mappings
Each target parameter needs a mapping function that takes **a vector of latent parameter values** (even with a single latent parameter) and returns one target value. The input vector is ordered as the latent parameters were given at construction. Mappings can be arbitrarily simple or complex.

## Latent Parameter Names
Optionally name the latent parameters; the names appear in the `LatentVariation` display, which helps when reading sensitivity-analysis or optimization results. If omitted, names default from the target parameters and their index (the target portion follows PhysiCellModelManager.jl short variation naming). See [`defaultLatentParameterNames`](@ref PhysiCellModelManager.ModelManager.defaultLatentParameterNames).

## Variation Names
You can optionally name a `LatentVariation` using the `name` keyword argument:

```julia
lv = LatentVariation(latent_parameters, targets, maps, latent_parameter_names; name="Threshold regime")
```

When latent variations are constructed automatically from [`DiscreteVariation`](@ref), [`DistributedVariation`](@ref), or [`CoVariation`](@ref), those variation names are propagated into latent parameter names used by sensitivity sampling outputs.

## `LatentVariation{Vector{<:Real}}`
Latent parameters given as vectors of discrete values produce a `LatentVariation{Vector{<:Real}}`. The vectors need not be the same length; requesting values uses all combinations of the latent values to compute the target values.

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
  Name: default: signal threshold low | default: signal threshold high
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
Latent parameters given as probability distributions produce a `LatentVariation{Distribution}`. Requesting values draws a sample from each distribution and computes the target values.

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
  Name: default: signal threshold low | default: signal threshold high
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