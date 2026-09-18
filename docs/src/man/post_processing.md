# [Post-processing and quantities of interest](@id post_processing_man)

Compute and store a per-simulation number *while* a run is in flight, so it survives whatever the
run deletes afterwards.

!!! tiergloss
    `run` accepts a `post_processor` keyword: a callback invoked once per successful simulation,
    right after it finishes and before PhysiCellModelManager.jl prunes any output. Inside it, `sim`
    is a `Simulation` — the same argument a [`QoI`](@ref ModelManager.QoI)'s `compute` receives, so
    one measurement can serve both. Most loader and analysis functions accept it directly;
    `simulationID(sim)` and `pathToOutputFolder(sim)` are there when you need the ID or the folder
    itself.

!!! tierwhy
    [Analyzing output](@ref analyzing_output_man) covers analysis *after* a run finishes, which
    works only as long as the output files are still there. The callback always sees the intact
    output folder, however aggressive your `prune_options` are: pruning is the last of the steps
    that follow a simulation, and has [its own section below](@ref prune_output_pp).

    **A callback that stores something needs a name.** Every sink column is named after the QoI that
    wrote it, and a bare `sim -> ...` has only the name Julia derives for an anonymous function —
    `anon_9`, `anon_14`, whatever that session happens to produce. The number is not stable, so the
    same script would write a second, half-empty set of columns next time; such a callback is
    refused rather than stored. Wrap it in a [`QoI`](@ref ModelManager.QoI), as below, or pass a
    named function. A callback returning `missing` stores nothing and is unaffected.

```julia
run(sampling; post_processor = QoI("final_count", sim -> finalPopulationCount(sim)["default"]))
```

## Returning quantities of interest

!!! tiergloss
    What the callback returns determines what gets stored. A single scalar (`Real`, `Bool`, or
    `String`) goes into one column named after the QoI — `QoI("final_count", …)` writes
    `final_count`. A `NamedTuple` or `Dict` of `name => scalar` is stored one column per key, named
    `<qoi name>.<key>`, so `QoI("counts", …)` returning `(; final_count = …)` writes
    `counts.final_count`. `missing` stores nothing and marks the callback as side-effects-only.

```julia
#! side effects only: return `missing` explicitly — a block's accidental `nothing` is refused
run(sampling; post_processor = function (sim)
    exportSimulation(simulationID(sim), "results/$(simulationID(sim))")
    return missing
end)

#! one scalar column, named after the QoI
run(sampling; post_processor = QoI("final_count", sim -> finalPopulationCount(sim)["default"]))

#! one column per key: writes `counts.final_count`
run(sampling; post_processor = QoI("counts", sim -> (; final_count = finalPopulationCount(sim)["default"])))
```

!!! tierwhy
    Namespacing the columns with the QoI's name is what lets two QoIs each report a `tumor` without
    landing in one column. A time series or other vector-valued quantity must be reduced to a scalar
    (e.g. a final or mean value) or written to a file by the callback — a non-scalar return raises an
    error rather than being flattened into columns you did not ask for.

## [Ready-made builder: `populationCountQoI`](@id population_count_qoi_builder)

!!! tiergloss
    [`populationCountQoI`](@ref) builds the measurement for you as a
    [`QoI`](@ref ModelManager.QoI), recording one `population_count.<cell_type>` column per cell
    type. If the requested snapshot doesn't exist for a given simulation (e.g. it was pruned by an
    earlier run), it returns `missing` for that simulation, so nothing is recorded for it rather
    than erroring.

```julia
run(sampling; post_processor = populationCountQoI())                       # final-snapshot counts
run(sampling; post_processor = populationCountQoI(; index=0))              # counts at snapshot 0 instead
run(sampling; post_processor = populationCountQoI(; cell_types=["cd8"]))   # only the "cd8" cell type
```

!!! tiergloss
    [`populationFractionQoI`](@ref) is the same builder for each cell type's share of the
    population, and works here as well as in calibration and sensitivity analysis. See
    [Using the builders in sensitivity analysis](@ref qoi_form_ss).

!!! tierjournal "2026-07-08 — A ready-made builder rather than a recipe to copy"
    **Decided.** Counting the final population is what almost every campaign wants stored, so it
    ships as a builder instead of a snippet each user rewrites; it returns a `Dict` rather than a
    `NamedTuple` because cell type names may contain spaces, which are not valid field names.
    **Decided.** A snapshot that is missing — pruned by an earlier run — records nothing for that
    simulation rather than raising.

!!! tierjournal "2026-09-14 — One builder per quantity"
    **Decided.** `populationCountQoI(; index)` and `populationFractionQoI(; index)` are the single
    builders for their quantities, `index` defaulting to `:final`; the separate endpoint-only names
    are gone, and the sink columns they write are `population_count.<cell_type>` and
    `population_fraction.<cell_type>`.
    **Rejected.** Keeping both spellings for compatibility: once they reduced identically, the
    second name bought nothing but a second family of columns in the same database.

## Reading the stored quantities back

```julia
postProcessingTable(sampling)                     # just the stored quantities, one row per simulation
printPostProcessingTable(sampling)                # the same table, printed
using CSV
printPostProcessingTable(sampling; sink = df -> CSV.write("qois.csv", df))  # ...or sent somewhere else
simulationsTable(sampling; post_processing=true)  # joined with the varied parameter values
```

!!! tiergloss
    [`postProcessingTable`](@ref) returns a `DataFrame` keyed by `:SimID`;
    [`printPostProcessingTable`](@ref) prints it, and its `sink` keyword takes any function that
    accepts a `DataFrame` (default `println`). See
    [Querying parameters](@ref querying_parameters_man) for more on those tables.

!!! tierdev
    Nothing about a stored value records which `compute` produced it, so a stored number is only as
    trustworthy as the assumption that the code has not changed since.
    [`verifyStoredValues`](@ref)`(q, T)` recomputes a `QoI` for the simulations of `T` and compares:
    it returns `(; n_checked, n_agreed, n_mismatched, n_unverifiable, n_missing, mismatches)`,
    comparing numbers with `isapprox` at `rtol` and keyed values key by key. Run it before trusting
    `stored=:prefer` or `stored=:require` on a result you care about — and check `n_agreed > 0`
    rather than `n_mismatched == 0`, since a run where every simulation was skipped (output folder
    gone, or `compute` returned `missing`) also reports zero mismatches.

## [Pruning output after the callback](@id prune_output_pp)

!!! tierwhy
    Every save interval PhysiCell writes an XML/MAT snapshot pair and an SVG, so a campaign of
    thousands of simulations is tens of gigabytes most analyses never open. Name the file types to
    drop in `prune_options`, and [`PruneOptions`](@ref) deletes them from each simulation's folder as
    the last step after it finishes — after your `post_processor` has run, which is why the callback
    is the place to compute what you need from the files.

```julia
run(sampling; prune_options = PruneOptions(prune_svg = true))    # keep the data, drop the pictures
run(sampling; prune_options = PruneOptions(prune_svg = true, prune_mat = true, prune_txt = true,
                                           prune_initial = true, prune_final = true))
```

!!! tiergloss
    `prune_svg`, `prune_mat`, `prune_txt` and `prune_xml` pick the types; the `initial*` and `final*`
    files of each type survive unless `prune_initial` and `prune_final` say otherwise, so a pruned
    simulation can still be loaded at its first and last snapshot.

!!! tierwhy
    Know what stops working: [`makeMovie`](@ref) needs the SVGs; loading a snapshot or plotting a
    population time series needs that snapshot's XML and MAT files; a replicate whose files are gone
    is excluded from monad-level aggregates rather than zero-filled; and re-running does not bring
    the files back, since the database still holds the simulation as complete.

!!! tierjournal "2026-07-07 — Pruning runs after your callback, not before it"
    **Decided.** Pruning moved into the destructive half of the per-simulation hook, which runs
    after the user `post_processor`. It used to run in the non-destructive half, so a callback would
    have opened an output folder that had already been gutted.
    **Decided.** The whole tail — including how a simulation's error file is handled — moved with
    it, rather than pruning alone.
