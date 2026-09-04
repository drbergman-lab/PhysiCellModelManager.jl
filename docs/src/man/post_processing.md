# [Post-processing and quantities of interest](@id post_processing_man)

[Analyzing output](@ref analyzing_output_man) covers analysis *after* a run finishes. `run` also
accepts a `post_processor` keyword: a callback invoked once per successful simulation, right
after it finishes and before PhysiCellModelManager.jl prunes any output — so the callback always
sees the intact output folder, however aggressive your `prune_options` are.

```julia
run(sampling; post_processor = sim -> (; final_count = finalPopulationCount(sim)["default"]))
```

Inside the callback, `sim` is a `Simulation` — the same argument a [`QoI`](@ref ModelManager.QoI)'s
`compute` receives, so one measurement can serve both. Most loader and analysis functions accept it
directly; `simulationID(sim)` and `pathToOutputFolder(sim)` are there when you need the ID or the
folder itself.

## Returning quantities of interest

What the callback returns determines what gets stored:

- **`nothing`** — side effects only (e.g. writing your own file, or an external log). Return it
  explicitly, or PCMM will store whatever the callback's last expression evaluated to instead:
  ```julia
  run(sampling; post_processor = function (sp)
      exportSimulation(simulationID(sp), "results/$(simulationID(sp))")
      return nothing
  end)
  ```
- **A `NamedTuple` or `Dict`** of `name => scalar` (`Real`, `Bool`, or `String`) — stored as
  quantities of interest, one row per simulation:
  ```julia
  run(sampling; post_processor = sp -> (; final_count = finalPopulationCount(simulationID(sp))["default"]))
  ```
  A time series or other vector-valued quantity must be reduced to a scalar (e.g. a final or
  mean value) or written to a file by the callback — a non-scalar return raises an error.

## Ready-made builder: [`populationCountQoI`](@ref)

Writing the measurement by hand works, but [`populationCountQoI`](@ref) builds it for you as a
[`QoI`](@ref ModelManager.QoI), recording one `count_<cell_type>` quantity per cell type:

```julia
run(sampling; post_processor = populationCountQoI())                       # final-snapshot counts
run(sampling; post_processor = populationCountQoI(; index=0))              # counts at snapshot 0 instead
run(sampling; post_processor = populationCountQoI(; cell_types=["cd8"]))   # only the "cd8" cell type
```

If the requested snapshot doesn't exist for a given simulation (e.g. it was pruned by an
*earlier* run before this feature's ordering guarantee applied to it), the builder returns
`nothing` for that simulation rather than erroring.

The population summary statistics have `QoI`-returning builders too — [`endpointPopulationCountQoIs`](@ref) and [`endpointPopulationFractionQoIs`](@ref) — which work here as well as in calibration and sensitivity analysis. See [QoI form](@ref qoi_form_ss).

## Reading the stored quantities back

```julia
postProcessingTable(sampling)                     # just the stored quantities, one row per simulation
simulationsTable(sampling; post_processing=true)  # joined with the varied parameter values
```

See [Querying parameters](@ref querying_parameters_man) for more on those tables.
