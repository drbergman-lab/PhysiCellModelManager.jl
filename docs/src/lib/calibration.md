```@meta
CollapsedDocStrings = true
```

# [Calibration](@id calibration_section_lib)

Native Julia ABC-SMC parameter calibration.

## Public API

### Problem definition

```@docs
CalibrationProblem
CalibrationParameter
```

### Calibration methods

```@docs
AbstractCalibrationMethod
ABCSMC
GaussianKernel
ComponentwiseKernel
LocalNNKernel
LocalNNCovKernel
```

### Result types

```@docs
Calibration
GenerationResult
ABCResult
ConvergenceSummary
```

### Running calibration

```@docs
runCalibration
runABC
resumeABC
posterior
```

### Built-in summary statistics

```@docs
endpointPopulationCounts
endpointPopulationFractions
meanPopulationTimeSeries
```

### Built-in distance functions

```@docs
mseDistance
```

### Supporting types

Internal source types stored on [`CalibrationParameter`](@ref) for provenance and JLD2
serialization. Users do not construct these directly.

```@docs
ModelManager.DVSource
ModelManager.CVSource
ModelManager.LVSource
```

### Progress reporting

Internal helper resolving the `progress` keyword of [`runCalibration`](@ref)/[`runABC`](@ref)
into a console-feedback level.

```@docs
ModelManager._resolveVerbosity
```

## Private API
```@autodocs
Modules = [PhysiCellModelManager]
Pages = ["calibration.jl"]
Public = false
```