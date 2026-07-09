# [Examples](@id examples_cookbook)

A task-oriented catalog of common recipes. Each entry shows the minimal code and links to the full how-to page. All assume you have a project set up (see [Your first project](@ref)) and a defined `inputs::InputFolders`.

## Vary one parameter over a few values

Use [`DiscreteVariation`](@ref) to sweep a finite set of values. → [Varying parameters](@ref)

```julia
dv = DiscreteVariation(configPath("max_time"), [1440.0, 2880.0])
run(inputs, dv)
```

## Sweep a grid of parameters

Pass multiple variations; by default they combine on a grid (all combinations). → [Varying parameters](@ref)

```julia
dv_g1 = DiscreteVariation(configPath("cd8", "cycle", "rate", 0), [0.001, 0.002])
dv_s  = DiscreteVariation(configPath("cd8", "cycle", "rate", 1), [0.001, 0.002, 0.003])
sampling = createTrial(inputs, dv_g1, dv_s; n_replicates=4) # 2×3 monads, 4 replicates each
```

## Vary a parameter over a continuous range

Use [`DistributedVariation`](@ref) with a distribution from `Distributions.jl`. → [Varying parameters](@ref)

```julia
using Distributions
dv = DistributedVariation(configPath("cd8", "apoptosis", "rate"), Uniform(0, 0.001))
```

## Co-vary linked parameters

Use [`CoVariation`](@ref) when parameters must move together (e.g. a rule's base value and its max response). → [CoVariations](@ref)

```julia
covariation = CoVariation(
    (configPath("default", "cycle", "duration", 0), [300.0, 400.0]),
    (configPath("default", "cycle", "duration", 1), [200.0, 100.0]); # conserved cycle time
    name="Conserved cycle time")
```

## Impose a constraint between parameters

Use [`LatentVariation`](@ref) when target parameters are derived from latent parameters through a mapping (e.g. enforcing high > low thresholds). → [LatentVariations](@ref)

```julia
using Distributions
lv = LatentVariation(
    [Uniform(0.0, 1.0)],
    [configPath("cancer", "apoptosis", "rate"), configPath("immune", "apoptosis", "rate")],
    [u -> 1e-4 * exp(5*u[1]), u -> 5e-5 * exp(5*u[1])]; name="apoptosis_scale")
```

## Add an intracellular (ODE) model

Reference an SBML file in `data/components/roadrunner` and assemble the intracellular XML. → [Intracellular inputs](@ref)

```julia
component = PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml")
cell_type_to_component = Dict("default" => component)
intracellular_folder = assembleIntracellular!(cell_type_to_component; name="toy_metabolic")
```

## Batch pre-built trials into one run

If you've built several trials separately (e.g. across a loop over input folders or parameter sets), pass them all to `run` (or `createTrial`) as a vector to launch them together in a single parallelized batch, rather than calling `run` once per trial. → [Your first project](@ref)

```julia
trials = [createTrial(inputs, dv1), createTrial(inputs, dv2)]
run(trials)   # one parallel pool across every simulation in both trials
```

Elements can be any mix of `Simulation`, `Monad`, `Sampling`, or `Trial`. The parallel-sims limit (`PCMM_NUM_PARALLEL_SIMS`) applies across the whole batch, so this launches more efficiently than running each trial separately.

## Run a sensitivity analysis

Pick a method ([`MOAT`](@ref), [`SobolMM`](@ref), or RBD) and pass continuous variations. → [Sensitivity analysis](@ref)

```julia
method = MOAT(8) # 8 base points
sensitivity_sampling = run(method, inputs, evs; n_replicates=n_replicates, functions=[f])
```

## Calibrate to data

Define a [`CalibrationProblem`](@ref) and run ABC-SMC with [`runABC`](@ref). → [Calibration](@ref calibration_section_man)

```julia
problem = CalibrationProblem(inputs, parameters, observed_data, summary_statistic, distance)
result  = runABC(problem)
```

## Record quantities of interest as simulations run

Pass a `post_processor` to `run` to compute and store per-simulation quantities while output is still intact, instead of loading everything again afterward. → [Analyzing output](@ref)

```julia
run(sampling; post_processor = populationCountQoI())   # one count_<cell_type> quantity per cell type
postProcessingTable(sampling)                          # read the stored quantities back
```

## Query the parameters of past runs

Use [`simulationsTable`](@ref) for a readable table, or [`getAllParameterValues`](@ref) for programmatic access. → [Querying parameters](@ref)

```julia
printSimulationsTable(sampling)          # human-readable, varied values only
df = getAllParameterValues(sampling)     # every terminal XML value, columns = XML paths
```

## Plot population over time

Call `plot` directly on a `Simulation`, `Monad`, `Sampling`, or a `run` result for a population panel (mean ± SD per cell type). → [Analyzing output](@ref)

```julia
using Plots
plot(Simulation(1); include_cell_type_names=["cd8", "cancer"])
```

## Make a movie from a simulation's snapshots

Use `makeMovie` to render a simulation's SVG snapshots into `out.mp4` via the PhysiCell Makefile. Override `framerate`, `magick_density`, `magick_resize_x`, or `magick_resize_y` to change frame rate or JPEG resolution/density; omit any to keep the Makefile's default. → [Analyzing output](@ref)

```julia
makeMovie(1; framerate=10, magick_resize_x=512, magick_resize_y=512)
```

## Extract per-cell time series

Use `cellDataSequence` to pull a labeled quantity for every cell across time. → [Analyzing output](@ref)

```julia
data = cellDataSequence(1, "position")
positions = data[78].position    # Nx3 matrix for cell ID 78
```
