```@meta
CollapsedDocStrings = true
```

# Calibration(@id calibration_section_lib)

Run ABC-SMC calibration on a model using pyabc (via PythonCall.jl).

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

## Private API
```@autodocs
Modules = [PhysiCellModelManager]
Pages = ["calibration.jl"]
Public = false
```