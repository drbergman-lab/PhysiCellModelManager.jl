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
resumeCalibration
run(::ABCSMC, ::CalibrationProblem)
posterior
```

## Calibration records

A calibration run is addressable like any other trial, and its rows are queryable the same way.

```@docs
calibrationsTable
printCalibrationsTable
simulationIDs(::Calibration)
monadIDs(::Calibration)
deleteCalibration
```

Simulations are reused across calibration runs through the bank, so a calibration's constituents can
predate it and outlive it.

```@docs
ModelManager.SimulationBank
```

## Built-in summary statistics

Monad-level, taking a monad ID. Since ModelManager 0.9 these are **not** valid `summary_statistic`
arguments — a measurement function receives a `Simulation` — so use the `QoI` builders below for
calibration and keep these for direct monad-level analysis.

```@docs
endpointPopulationCounts
endpointPopulationFractions
meanPopulationTimeSeries
```

### QoI builders

One [`QoI`](@ref ModelManager.QoI) per cell type, named for the cell type, so the value reaching
`distance` has the same shape as the monad-level statistic above.

```@docs
endpointPopulationCountQoIs
endpointPopulationFractionQoIs
meanPopulationTimeSeriesQoIs
```

## Built-in distance functions

```@docs
mseDistance
```

