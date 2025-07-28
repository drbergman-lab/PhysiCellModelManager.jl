# CoVariations
Sometimes several parameters need to be varied together.
A common use case is the varying the base value of a rule and the max response of the rule[^1]
To handle this scenario, PhysiCellModelManager.jl provides the `CoVariation` type.
A `CoVariation` is a wrapper for a vector of `ElementaryVariation`'s, and each `ElementaryVariation` must be of the same type, i.e., all `DiscreteVariation`'s or all `DistributedVariation`'s.
The type of a `CoVariation` is parameterized by the type of `ElementaryVariation`'s it contains.
Thus, there are, for now, two types of `CoVariation`'s: `CoVariation{DiscreteVariation}` and `CoVariation{DistributedVariation}`.

[^1]: PhysiCell does not allow the base value to exceed the max response. That is, the base response of a decreasing signal cannot be < the max response. Similarly, the base resposne of an increasing signal cannot be > the max response.

## `CoVariation{DiscreteVariation}`
For a `CoVariation{DiscreteVariation}`, each of the `DiscreteVariation`'s must have the same number of values.
This may be relaxed in future versions, but the primary use case anticipated is a [`GridVariation`](@ref) which requires the variations to inform the size of the grid.
No restrictions are imposed on how the values of the various variations are linked.
PhysiCellModelManager.jl will use values that share an index their respective vectors together.

```julia
base_xml_path = configPath("default", "custom:sample")
ev1 = DiscreteVariation(base_xml_path, [1, 2, 3]) # vary the `sample` custom data for cell type default
max_xml_path = rulePath("default", "custom:sample", "increasing_signals", "max_response") # the max response of the rule increasing sample (must be bigger than the base response above)
ev2 = DiscreteVariation(rule_xml_path, [2, 3, 4])
covariation = CoVariation(ev1, ev2) # CoVariation([ev1, ev2]) also works
```

It is also not necessary to create the `ElementaryVariation`'s separately and then pass them to the `CoVariation` constructor.
```julia
# have the phase durations vary by and compensate for each other
phase_0_xml_path = configPath("default", "cycle", "duration", 0)
phase_0_xml_path = configPath("default", "cycle", "duration", 1)
phase_0_durations = [300.0, 400.0] 
phase_1_durations = [200.0, 100.0] # the (mean) duration through these two phases is 500 min
# input any number of tuples (xml_path, values)
covariation = Covariation((phase_0_xml_path, phase_0_durations), (phase_1_xml_path, phase_1_durations))
```

## `CoVariation{DistributedVariation}`
For a `CoVariation{DistributedVariation}`, the conversion of a CDF value, $x \in [0, 1]$, is done independently for each distribution.
That is, in the joint probability space, a `CoVariation{DistributedVariation}` restricts us to the one-dimensional line connecting $\mathbf{0}$ to $\mathbf{1}$.
To allow for the parameters to vary inversely with one another, the `DistributedVariation` type accepts an optional `flip::Bool` argument (not a keyword argument!).
For a distribution `dv` with `dv.flip=true`, when a value is requested with a CDF $x$, PhysiCellModelManager.jl will "flip" the CDF to give the value with CDF $1 - x$.

```jldoctest
using PhysiCellModelManager
timing_1_path = configPath("user_parameters", "event_1_time")
timing_2_path = configPath("user_parameters", "event_2_time")
dv1 = UniformDistributedVariation(timing_1_path, 100.0, 200.0)
dv2 = UniformDistributedVariation(timing_2_path, 100.0, 200.0; flip=true)
covariation = CoVariation(dv1, dv2)
cdf = 0.1
PhysiCellModelManager.variationValues.(covariation.variations, cdf) # PhysiCellModelManager.jl internal for getting values for an ElementaryVariation
# output
2-element Vector{Vector{Float64}}:
 [110.0]
 [190.0]
```

As with `CoVariation{DiscreteVariation}`, it is not necessary to create the `ElementaryVariation`'s separately and then pass them to the `CoVariation` constructor. It is not possible to `flip` a `DistributedVariation` with this syntax, however.

```julia
apop_xml_path = configPath("default", "apoptosis", "death_rate")
apop_dist = Uniform(0, 0.001)
cycle_entry_path = configPath("default", "cycle", "rate", 0)
cycle_dist = Uniform(0.00001, 0.0001)
covariation = CoVariation((apop_xml_path, apop_dist), (cycle_entry_path, cycle_dist))
```