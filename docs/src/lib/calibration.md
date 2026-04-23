```@meta
CollapsedDocStrings = true
```

# Calibration(@id calibration_section_lib)

Native Julia ABC-SMC parameter calibration.

## Public API

### Problem definition

```@docs
CalibrationParameter
CalibrationProblem
```

### Calibration methods

```@docs
AbstractCalibrationMethod
ABCSMC
```

### Result types

```@docs
Calibration
GenerationResult
ABCResult
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

## Private API
```@autodocs
Modules = [PhysiCellModelManager]
Pages = ["calibration.jl"]
Public = false
```