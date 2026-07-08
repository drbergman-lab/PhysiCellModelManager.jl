```@meta
CollapsedDocStrings = true
```

# Analysis

Analyze output from a PCMM project.
It is anticipated that this will eventually be split off into its own module or even package.
Possibly with loader.jl.

## Public API
```@autodocs
Modules = [PhysiCellModelManager]
Pages = ["graphs.jl", "motility.jl", "pcf.jl", "population.jl", "preprocessing.jl", "runtime.jl", "substrate.jl"]
Private = false
```

### Ready-made `post_processor` builders

Functions that return a `post_processor` (see [`run`](@ref ModelManager.run)) ready to pass
straight to `run(T; post_processor=...)`.

```@docs
populationCountQoI
```

## Private API
```@autodocs
Modules = [PhysiCellModelManager]
Pages = ["graphs.jl", "motility.jl", "pcf.jl", "population.jl", "preprocessing.jl", "runtime.jl", "substrate.jl"]
Public = false
```