# [CoVariations](@id covariations_man)
A [`CoVariation`](@ref) varies several parameters in lockstep instead of crossing them on a grid.

!!! tiergloss
    A `CoVariation` wraps a vector of `ElementaryVariation`s that must all be the same type, giving
    two forms: `CoVariation{DiscreteVariation}` and `CoVariation{DistributedVariation}`. Build one
    from variations you already have, or from `(xml_path, values)` / `(xml_path, distribution)`
    tuples. The optional `name` keyword names the combination.

!!! tierwhy
    The motivating case is a pair PhysiCell requires to stay ordered — a rule's base value and its
    max response, where an increasing signal needs base ≤ max and a decreasing one base ≥ max. On a
    grid, half the combinations would violate that; co-varying the two keeps every point legal.
    Without a `name`, the combination reports under its members' names joined by `" AND "`; see
    [Varying parameters](@ref varying_parameters_man) for what a variation name is used for.

## [`CoVariation{DiscreteVariation}`](@id co_variation_discrete_variation_section)

!!! tiergloss
    Every member `DiscreteVariation` must supply the same number of values; the constructor rejects
    mismatched lengths outright, whichever design method you use later. Values sharing an index are
    used together.

!!! tierwhy
    How you line the values up is otherwise unrestricted, which is what makes the second example
    below work: the two cycle phase durations compensate for each other, so every point keeps the
    mean time through both phases at 500 min. A grid over the same two vectors would have produced
    four points, three of them with a different total.

```julia
# a rule's base value and its max response, kept ordered
base_xml_path = configPath("default", "custom:sample")
max_xml_path = rulePath("default", "custom:sample", "increasing_signals", "max_response")
ev1 = DiscreteVariation(base_xml_path, [1, 2, 3])
ev2 = DiscreteVariation(max_xml_path, [2, 3, 4])
covariation = CoVariation(ev1, ev2)          # CoVariation([ev1, ev2]) also works

# or skip the ElementaryVariations: any number of (xml_path, values) tuples
phase_0_xml_path = configPath("default", "cycle", "duration", 0)
phase_1_xml_path = configPath("default", "cycle", "duration", 1)
covariation = CoVariation((phase_0_xml_path, [300.0, 400.0]),
                          (phase_1_xml_path, [200.0, 100.0]);
                          name="Conserved cycle time")
```

## [`CoVariation{DistributedVariation}`](@id co_variation_distributed_variation_section)

!!! tiergloss
    Members given as distributions share one CDF value $x \in [0, 1]$, which each distribution
    converts independently. Pass `flip=true` to a [`DistributedVariation`](@ref) to have it return
    the value at CDF $1 - x$ instead, so that parameter moves opposite to the others.

!!! tierwhy
    Sharing the CDF restricts sampling, in the joint probability space, to the line connecting
    $\mathbf{0}$ to $\mathbf{1}$ — which is the point: one sample index moves every member together.
    `flip` is the only way to co-vary parameters inversely, and it is a field of the member
    variation, so the `(xml_path, distribution)` tuple shorthand cannot express it. As in the
    discrete case, this constructor also takes an optional `name`.

```jldoctest
using PhysiCellModelManager
timing_1_path = configPath("user_parameters", "event_1_time")
timing_2_path = configPath("user_parameters", "event_2_time")
dv1 = UniformDistributedVariation(timing_1_path, 100.0, 200.0)
dv2 = UniformDistributedVariation(timing_2_path, 100.0, 200.0; flip=true)
covariation = CoVariation(dv1, dv2)
cdf = 0.1
PhysiCellModelManager.ModelManager.variationValues.(covariation.variations, cdf) # ModelManager.jl internal for getting values for an ElementaryVariation
# output
2-element Vector{Vector{Float64}}:
 [110.0]
 [190.0]
```

```julia
# tuple shorthand: (xml_path, distribution), no flipping
apop_xml_path = configPath("default", "apoptosis", "death_rate")
cycle_entry_path = configPath("default", "cycle", "rate", 0)
covariation = CoVariation((apop_xml_path, Uniform(0, 0.001)),
                          (cycle_entry_path, Uniform(0.00001, 0.0001)))
```

!!! tierjournal "2026-03-31 — A co-variation carries one name, its members keep theirs"
    **Decided:** `name` is a keyword, so the positional constructors are unchanged, and
    [`variationName`](@ref) is the single accessor. A `CoVariation` stores one name for the
    combination while its member variations keep their own, which is why the generated default
    joins the members' names rather than replacing them.
