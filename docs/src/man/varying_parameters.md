# Varying parameters
All inputs that are varied by PhysiCellModelManager.jl are stored in XML files, and PhysiCellModelManager.jl has a standard representation of the paths to these parameters.

## XML paths
XML paths are represented as a vector of strings, where each string corresponds to a tag in the XML file.
When an attribute is needed to identify which of the identically tagged children to select, the string is formatted as
```julia
"<tag>:<attribute>:<value>"
```

If the content of a child element is needed to identify which tag to select, the string is formatted as
```julia
"<tag>::<child_tag>:<value>"
```
where `::` is used to separate the tag from the child tag.
This is necessary, e.g., for the `initial_parameter_distributions` as the `behavior` is a child element of the `distribution` element:
```julia
["cell_definitions", "cell_definition:name:T_cell", "initial_parameter_distributions", "distribution::behavior:cycle entry"]
```

See [Helper functions to define targets](@ref) for helper functions that can be used to create these paths easily for all the varied input types.

## Discrete variations
Once the XML path is defined, a discrete variation (selecting a finite set of values) can be defined using [`DiscreteVariation`](@ref):

```julia
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0])
```

These can then be passed into either [`createTrial`](@ref) or ([`run`](@ref)) to create (or run) simulations with the specific paramater variations, automatically adding them to the database for future reference.
If multiple variations are used, they are by default combined on a grid, i.e., all combinations of the variations are used.

```julia
xml_path = configPath("cd8", "cycle", "rate", 0)
dv_g1 = DiscreteVariation(xml_path, [0.001, 0.002]) #! vary g1 duration

xml_path2 = configPath("cd8", "cycle", "rate", 1)
dv_s = DiscreteVariation(xml_path2, [0.001, 0.002, 0.003]) #! vary s duration

sampling = createTrial(inputs, dv_g1, dv_s; n_replicates=4) #! will run 2x3=6 monads (identical parameters) 4 times each for a total of 24 simulations
```

## Distributed variations
Distributed variations are used to vary a parameter over a continuous range, e.g., a range of values for a parameter.
These are defined using [`DistributedVariation`](@ref):

```julia
using Distributions
xml_path = configPath("cd8", "apoptosis", "rate")
d = Uniform(0, 0.001)
dv = DistributedVariation(xml_path, d)
```

These variations are useful for doing [Sensitivity analysis](@ref).