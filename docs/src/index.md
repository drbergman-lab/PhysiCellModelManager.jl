```@meta
CurrentModule = PhysiCellModelManager
```

```@raw html
<p align="center"><img src="assets/logo-hero.svg" width="200" alt="PhysiCellModelManager.jl"></p>
```

# PhysiCellModelManager.jl

[PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) (PCMM) is a Julia package for running large [PhysiCell](https://github.com/MathCancer/PhysiCell) simulation campaigns. It manages the inputs, variations, and databases so you can define a parameter sweep, sensitivity analysis, or calibration once and let PCMM organize, deduplicate, and reproduce the runs.

New here? Start with [Installation](@ref), then [Your first project](@ref).

## Where do I look?

| I want to… | Go to |
| --- | --- |
| Install the package and run my first simulations | [Installation](@ref), [Your first project](@ref) |
| Set up a reproducible Julia environment | [Julia environments](@ref) |
| Bring in an existing PhysiCell project | [Importing a project](@ref) |
| Change parameter values across runs | [Varying parameters](@ref), [XML path helpers](@ref) |
| Vary parameters together or under constraints | [CoVariations](@ref), [LatentVariations](@ref) |
| Run a sensitivity analysis or calibrate to data | [Sensitivity analysis](@ref), [Calibration](@ref calibration_section_man) |
| Plot or query results | [Analyzing output](@ref), [Querying parameters](@ref) |
| Copy-paste a recipe | [Examples](@ref examples_cookbook) |
| Look up a function's signature | the [Index](@ref) (all exported symbols) |
| Troubleshoot something | [Known limitations](@ref), [Best practices](@ref) |

## Issues

Have a problem? First check [Known limitations](@ref) and [Best practices](@ref). If it persists, please open an issue [here](https://github.com/drbergman-lab/PhysiCellModelManager.jl/issues).
