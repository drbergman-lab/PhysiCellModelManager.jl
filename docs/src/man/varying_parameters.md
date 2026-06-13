# Varying parameters
PhysiCellModelManager.jl stores all varied inputs in XML files and uses a standard representation for the paths to their parameters.

## XML paths
An XML path is a vector of strings, one per tag. To select among identically tagged children by attribute, format the string as
```julia
"<tag>:<attribute>:<value>"
```

To select by the content of a child element, use `::` to separate the tag from the child tag:
```julia
"<tag>::<child_tag>:<value>"
```
This is needed, e.g., for `initial_parameter_distributions`, where `behavior` is a child of the `distribution` element:
```julia
["cell_definitions", "cell_definition:name:T_cell", "initial_parameter_distributions", "distribution::behavior:cycle entry"]
```

See [XML path helpers](@ref) for helper functions that build these paths easily for all varied input types.

## Discrete variations
With an XML path defined, create a discrete variation (a finite set of values) with [`DiscreteVariation`](@ref):

```julia
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0])
```

Optionally set a user-facing `name`, used in reporting outputs (e.g. sensitivity scheme headers):

```jldoctest
using PhysiCellModelManager
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0]; name="max time")
variationName(dv)
# output
"max time"
```

If `name` is omitted, PhysiCellModelManager.jl assigns a default based on the target/location naming conventions used by [`shortVariationName`](@ref PhysiCellModelManager.shortVariationName).

Pass variations to [`createTrial`](@ref) or [`run`](@ref) to create (or run) simulations with those parameters, automatically recording them in the database. Multiple variations are combined on a grid by default (all combinations).

```julia
xml_path = configPath("cd8", "cycle", "rate", 0)
dv_g1 = DiscreteVariation(xml_path, [0.001, 0.002]) #! vary g1 duration

xml_path2 = configPath("cd8", "cycle", "rate", 1)
dv_s = DiscreteVariation(xml_path2, [0.001, 0.002, 0.003]) #! vary s duration

sampling = createTrial(inputs, dv_g1, dv_s; n_replicates=4) #! will run 2x3=6 monads (identical parameters) 4 times each for a total of 24 simulations
```

## Distributed variations
Distributed variations vary a parameter over a continuous range, defined with [`DistributedVariation`](@ref):

```julia
using Distributions
xml_path = configPath("cd8", "apoptosis", "rate")
d = Uniform(0, 0.001)
dv = DistributedVariation(xml_path, d)
```

Like discrete variations, distributed variations also support optional naming:

```julia
dv = DistributedVariation(xml_path, d; name="apoptosis rate")
```

These variations are useful for doing [Sensitivity analysis](@ref).