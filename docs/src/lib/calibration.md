```@meta
CollapsedDocStrings = true
```

# Calibration

Run ABC-SMC calibration on a model using pyabc (via PyCall.jl).

## Public API

### Problem definition

```@docs
CalibrationParameter
CalibrationProblem
```

### Result types

```@docs
Calibration
ABCResult
```

### Running calibration

```@docs
runABC
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

<!--
  Add new exported calibration symbols here as they are introduced.
  All symbols listed above must be either `export`ed or declared `public` in src/calibration/.
-->
