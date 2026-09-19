# [Examples](@id examples_cookbook)

A task-oriented catalog of common recipes, each the minimal code plus a link to the page that
covers it; all assume a project set up as in [Your first project](@ref getting_started_man) and a
defined `inputs::InputFolders`.

## Vary one parameter over a few values

!!! tiergloss
    [`DiscreteVariation`](@ref) sweeps a finite set of values. →
    [Varying parameters](@ref varying_parameters_man)

```julia
dv = DiscreteVariation(configPath("max_time"), [1440.0, 2880.0])
run(inputs, dv)
```

## Sweep a grid of parameters

!!! tiergloss
    Pass multiple variations; by default they combine on a grid (all combinations). →
    [Varying parameters](@ref varying_parameters_man)

```julia
dv_g1 = DiscreteVariation(configPath("cd8", "cycle", "rate", 0), [0.001, 0.002])
dv_s  = DiscreteVariation(configPath("cd8", "cycle", "rate", 1), [0.001, 0.002, 0.003])
sampling = createTrial(inputs, dv_g1, dv_s; n_replicates=4) # 2×3 monads, 4 replicates each
```

## Vary a parameter over a continuous range

!!! tiergloss
    [`DistributedVariation`](@ref) takes a distribution from `Distributions.jl`. →
    [Varying parameters](@ref varying_parameters_man)

```julia
using Distributions
dv = DistributedVariation(configPath("cd8", "apoptosis", "rate"), Uniform(0, 0.001))
```

## Co-vary linked parameters

!!! tiergloss
    [`CoVariation`](@ref) is for parameters that must move together, such as a rule's base value and
    its max response. → [CoVariations](@ref covariations_man)

```julia
covariation = CoVariation(
    (configPath("default", "cycle", "duration", 0), [300.0, 400.0]),
    (configPath("default", "cycle", "duration", 1), [200.0, 100.0]); # conserved cycle time
    name="Conserved cycle time")
```

## Impose a constraint between parameters

!!! tiergloss
    [`LatentVariation`](@ref) derives target parameters from latent ones through a mapping, which is
    how a constraint like high > low is enforced. → [LatentVariations](@ref latent_variations_man)

```julia
using Distributions
lv = LatentVariation(
    [Uniform(0.0, 1.0)],
    [configPath("cancer", "apoptosis", "rate"), configPath("immune", "apoptosis", "rate")],
    [u -> 1e-4 * exp(5*u[1]), u -> 5e-5 * exp(5*u[1])]; name="apoptosis_scale")
```

## Add an intracellular (ODE) model

!!! tiergloss
    Reference an SBML file in `data/components/roadrunner` and assemble the intracellular XML. →
    [Intracellular inputs](@ref intracellular_inputs_man)

```julia
component = PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml")
cell_type_to_component = Dict("default" => component)
intracellular_folder = assembleIntracellular!(cell_type_to_component; name="toy_metabolic")
```

## Batch pre-built trials into one run

!!! tiergloss
    Trials built separately — across a loop over input folders or parameter sets — can be passed to
    `run` (or `createTrial`) as a vector, launching them in one batch. Elements can be any mix of
    `Simulation`, `Monad`, `Sampling`, or `Trial`. → [Your first project](@ref getting_started_man)

```julia
trials = [createTrial(inputs, dv1), createTrial(inputs, dv2)]
run(trials)   # one parallel pool across every simulation in both trials
```

!!! tierwhy
    The parallel-sims limit (`PCMM_NUM_PARALLEL_SIMS`) applies across the whole batch, so one
    `run` over a vector keeps the pool full where a `run` per trial drains and refills it.

## Run a sensitivity analysis

!!! tiergloss
    Pick a method — [`MOAT`](@ref), [`SobolMM`](@ref), or RBD — and pass continuous variations. →
    [Sensitivity analysis](@ref sensitivity_analysis_man)

```julia
method = MOAT(8) # 8 base points
sensitivity_sampling = run(method, inputs, evs; n_replicates=n_replicates, functions=[f])
```

## Calibrate to data

!!! tiergloss
    Define a [`CalibrationProblem`](@ref) and run it with a method, as for a sensitivity analysis. →
    [Calibration](@ref calibration_section_man)

```julia
problem = CalibrationProblem(inputs, parameters, observed_data, summary_statistic, distance)
result  = run(ABCSMC(population_size = 200), problem)
```

## Record quantities of interest as simulations run

!!! tiergloss
    A `post_processor` computes and stores per-simulation quantities while the output is still
    intact, instead of loading everything again afterward. →
    [Post-processing and quantities of interest](@ref post_processing_man)

```julia
run(sampling; post_processor = populationCountQoI())   # one population_count.<cell_type> column per cell type
postProcessingTable(sampling)                          # read the stored quantities back
```

## Query the parameters of past runs

!!! tiergloss
    [`simulationsTable`](@ref) gives a readable table; [`getAllParameterValues`](@ref) gives
    programmatic access. → [Querying parameters](@ref querying_parameters_man)

```julia
printSimulationsTable(sampling)          # human-readable, varied values only
df = getAllParameterValues(sampling)     # every terminal XML value, columns = XML paths
```

## Plot population over time

!!! tiergloss
    Call `plot` directly on a `Simulation`, `Monad`, `Sampling`, or a `run` result for a population
    panel (mean ± SD per cell type). → [Analyzing output](@ref analyzing_output_man)

```julia
using Plots
plot(Simulation(1); include_cell_type_names=["cd8", "cancer"])
```

## Make a movie from a simulation's snapshots

!!! tiergloss
    `makeMovie` renders a simulation's SVG snapshots into `out.mp4` via the PhysiCell Makefile.
    Override `framerate`, `magick_density`, `magick_resize_x`, or `magick_resize_y` to change the
    frame rate or the JPEG resolution and density; omit any to keep the Makefile's default. →
    [Movies](@ref movies_man)

```julia
makeMovie(1; framerate=10, magick_resize_x=512, magick_resize_y=512)
```

## Extract per-cell time series

!!! tiergloss
    `cellDataSequence` pulls a labeled quantity for every cell across time. →
    [Analyzing output](@ref analyzing_output_man)

```julia
data = cellDataSequence(1, "position")
positions = data[78].position    # Nx3 matrix for cell ID 78
```
