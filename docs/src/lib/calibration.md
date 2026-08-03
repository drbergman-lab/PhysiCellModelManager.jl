```@meta
CollapsedDocStrings = true
```

# [Calibration](@id calibration_section_lib)

Native Julia ABC-SMC parameter calibration.

## Problem definition

```@docs
CalibrationProblem
CalibrationParameter
```

## Calibration methods

```@docs
AbstractCalibrationMethod
ABCSMC
GaussianKernel
ComponentwiseKernel
LocalNNKernel
LocalNNCovKernel
```

## Result types

```@docs
Calibration
GenerationResult
ABCResult
ConvergenceSummary
```

## Running calibration

```@docs
runCalibration
runABC
resumeABC
posterior
```

## Built-in summary statistics

```@docs
endpointPopulationCounts
endpointPopulationFractions
meanPopulationTimeSeries
```

## Built-in distance functions

```@docs
mseDistance
```

