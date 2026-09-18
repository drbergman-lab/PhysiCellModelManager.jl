# [LatentVariations](@id latent_variations_man)
A [`LatentVariation`](@ref) varies target parameters through **latent parameters** and mapping functions, so a constraint between the targets holds at every sampled point.

!!! tiergloss
    Construct one from four pieces: the **latent parameters** (each a vector of discrete values or a
    probability distribution), the **target parameters** (a vector of XML paths, as for any
    `ElementaryVariation`), one **mapping function** per target, and optionally the latent-parameter
    names plus a `name` for the variation itself. Each mapping takes the vector of latent values —
    ordered as the latent parameters were given, even when there is only one — and returns one
    target value.

!!! tierwhy
    This extends [CoVariations](@ref covariations_man) from lockstep to an arbitrary relation. The
    motivating case is a low/high threshold pair defining low-medium-high regimes: vary the low
    threshold and the *gap* rather than the two thresholds, and high > low is true by construction
    instead of being a constraint you have to filter for afterwards. Mappings can be arbitrarily
    simple or complex, so any relation you can write as a function is available.

    **Names.** The latent-parameter names appear in the `LatentVariation` display and in
    sensitivity-analysis and optimization results, which is the reason to supply them. Omitted, they
    fall back to
    [`defaultLatentParameterNames`](@ref PhysiCellModelManager.ModelManager.defaultLatentParameterNames),
    which builds `"<target_1> | <target_2> | … | lp#<i>"` — every target's column name, in
    PhysiCellModelManager.jl's short variation naming, then the latent parameter's index. When a
    `LatentVariation` is built automatically from a [`DiscreteVariation`](@ref),
    [`DistributedVariation`](@ref), or [`CoVariation`](@ref), those variations' names are used
    instead, so a name you set once follows through to the sensitivity sampling output.

```julia
lv = LatentVariation(latent_parameters, targets, maps, latent_parameter_names; name="Threshold regime")
```

!!! tierjournal "2026-03-31 — Latent parameter names come from the variations, not a new convention"
    **Decided:** sensitivity scheme headers inherit variation names because a `LatentVariation`
    built from a variation passes [`variationName`](@ref) through as its latent parameter names, so
    a name set once follows all the way to the sampling output. Overriding the convention therefore
    means passing `lp_names` in at construction, not extending the function that generates the
    defaults.

## [`LatentVariation{Vector{<:Real}}`](@id latent_variation_vector_real_section)

!!! tiergloss
    Latent parameters given as vectors of discrete values produce a `LatentVariation{Vector{<:Real}}`.
    The vectors need not be the same length; requesting values uses all combinations of the latent
    values to compute the target values.

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

## [`LatentVariation{Distribution}`](@id latent_variation_distribution_section)

!!! tiergloss
    Latent parameters given as probability distributions produce a `LatentVariation{Distribution}`.
    Requesting values draws a sample from each distribution and computes the target values.

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
