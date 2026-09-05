# [Post-processing and quantities of interest](@id post_processing_man)

[Analyzing output](@ref analyzing_output_man) covers analysis *after* a run finishes. `run` also
accepts a `post_processor` keyword: a callback invoked once per successful simulation, right
after it finishes and before PhysiCellModelManager.jl prunes any output — so the callback always
sees the intact output folder, however aggressive your `prune_options` are.

```julia
run(sampling; post_processor = QoI("final_count", sim -> finalPopulationCount(sim)["default"]))
```

Inside the callback, `sim` is a `Simulation` — the same argument a [`QoI`](@ref ModelManager.QoI)'s
`compute` receives, so one measurement can serve both. Most loader and analysis functions accept it
directly; `simulationID(sim)` and `pathToOutputFolder(sim)` are there when you need the ID or the
folder itself.

!!! note "A callback that stores something needs a name"
    Every sink column is named after the QoI that wrote it, and a bare `sim -> ...` has only the
    name Julia derives for an anonymous function — `anon_9`, `anon_14`, whatever that session
    happens to produce. The number is not stable, so the same script would write a second,
    half-empty set of columns next time. From ModelManager 0.9.1 that is refused rather
    than stored. Wrap it in a [`QoI`](@ref ModelManager.QoI) as above, or pass a named function.
    A callback returning `nothing` stores nothing and is unaffected.

## Returning quantities of interest

What the callback returns determines what gets stored:

- **`nothing`** — side effects only (e.g. writing your own file, or an external log). Return it
  explicitly, or PCMM will store whatever the callback's last expression evaluated to instead:
  ```julia
  run(sampling; post_processor = function (sim)
      exportSimulation(simulationID(sim), "results/$(simulationID(sim))")
      return nothing
  end)
  ```
- **A single scalar** (`Real`, `Bool`, or `String`) — stored in one column named after the QoI,
  which is the shape of the opening example above: `QoI("final_count", …)` writes `final_count`.
- **A `NamedTuple` or `Dict`** of `name => scalar` (`Real`, `Bool`, or `String`) — stored as
  quantities of interest, one row per simulation, one column per key named `<qoi name>.<key>`:
  ```julia
  run(sampling; post_processor = QoI("counts", sim -> (; final_count = finalPopulationCount(sim)["default"])))
  ```
  writes the column `counts.final_count`. Namespacing the columns is what lets two QoIs each
  report a `tumor` without landing in one column.

  A time series or other vector-valued quantity must be reduced to a scalar (e.g. a final or
  mean value) or written to a file by the callback — a non-scalar return raises an error.

## [Ready-made builder: `populationCountQoI`](@id population_count_qoi_builder)

Writing the measurement by hand works, but [`populationCountQoI`](@ref) builds it for you as a
[`QoI`](@ref ModelManager.QoI), recording one `population_count.<cell_type>` column per cell type:

```julia
run(sampling; post_processor = populationCountQoI())                       # final-snapshot counts
run(sampling; post_processor = populationCountQoI(; index=0))              # counts at snapshot 0 instead
run(sampling; post_processor = populationCountQoI(; cell_types=["cd8"]))   # only the "cd8" cell type
```

If the requested snapshot doesn't exist for a given simulation (e.g. it was pruned by an
*earlier* run before this feature's ordering guarantee applied to it), the builder returns
`nothing` for that simulation rather than erroring.

!!! warning "Upgrading from v0.3.3"
    This builder wrote `count_<cell_type>` columns in v0.3.3, when the sink was one flat namespace
    and the prefix was all that kept two measurements apart. It now writes
    `population_count.<cell_type>`. Runs from before the upgrade keep their old columns and are not
    rewritten, so a project that spans the change has both families in
    [`postProcessingTable`](@ref), each populated only for the runs that produced it.

The population summary statistics have `QoI`-returning builders too — [`endpointPopulationCountQoI`](@ref) and [`endpointPopulationFractionQoI`](@ref) — which work here as well as in calibration and, from ModelManager 0.9.1, sensitivity analysis. See [QoI form](@ref qoi_form_ss).

## Reading the stored quantities back

```julia
postProcessingTable(sampling)                     # just the stored quantities, one row per simulation
simulationsTable(sampling; post_processing=true)  # joined with the varied parameter values
```

See [Querying parameters](@ref querying_parameters_man) for more on those tables.
