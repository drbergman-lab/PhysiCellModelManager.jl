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
samplePosterior
createTrial(::ABCResult, ::ModelManager.DataFrames.DataFrame)
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

One [`QoI`](@ref ModelManager.QoI) builder per quantity, each measuring a single `Simulation` — what
every consumer of a measurement asks for — and reduced across a monad's replicates by ModelManager.
Each value is a `Dict` keyed by cell type, so `observed_data` is keyed by cell type too. Pass
`cell_types` to restrict the measurement; omit it and every cell type in the output is measured.
[`populationCountQoI`](@ref) is documented with the other `post_processor` builders under
[Analysis](@ref).

```@docs
populationFractionQoI
meanPopulationTimeSeriesQoI
```

To analyze a finished monad directly, without a `QoI`, use [`finalPopulationCount`](@ref) on a
`Monad` or `MonadPopulationTimeSeries`.

## Built-in distance functions

```@docs
mseDistance
```

