# [Post-processing and quantities of interest](@id post_processing_man)

Run your own code on each simulation while its output folder is still intact: compute a quantity
once and store it, so it survives pruning and never has to be recomputed, or do anything else the
intact folder allows — custom clean-up, exporting files, whatever your campaign needs.

!!! tiergloss
    `run` accepts a `post_processor` keyword: a callback invoked once per successful simulation,
    right after it finishes and before PhysiCellModelManager.jl prunes any output. Inside it, `sim`
    is a `Simulation` — the same argument a [`QoI`](@ref ModelManager.QoI)'s `compute` receives, so
    one measurement can serve both. The loaders and per-simulation analyses on
    [Analyzing output](@ref analyzing_output_man) take that `Simulation` directly
    (`PhysiCellSnapshot(sim, :final)`, `finalPopulationCount(sim)`) or its ID, `simulationID(sim)`;
    `pathToOutputFolder(sim)` gives the folder itself.

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

!!! tierwhy
    Namespacing the columns with the QoI's name is what lets two QoIs report the same key without
    landing in one column: if `QoI("counts", …)` and `QoI("fractions", …)` both return a key named,
    say, `tumor`, they write `counts.tumor` and `fractions.tumor`. A time series or other
    vector-valued quantity must be reduced to a scalar (e.g. a final or mean value) or written to a
    file by the callback — a non-scalar return raises an error rather than being flattened into
    columns you did not ask for.

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

## [Ready-made QoI builders](@id population_count_qoi_builder)

!!! tiergloss
    [`populationCountQoI`](@ref) and [`populationFractionQoI`](@ref) build the measurement for you
    as a [`QoI`](@ref ModelManager.QoI): one `population_count.<cell_type>` column per cell type
    holding its count, or one `population_fraction.<cell_type>` column holding its share of the
    whole population. Both take the same keywords. If the requested snapshot doesn't exist for a
    given simulation (e.g. it was pruned by an earlier run), they return `missing` for that
    simulation, so nothing is recorded for it rather than erroring. The same builders work in
    calibration and sensitivity analysis; see
    [Using the builders in sensitivity analysis](@ref qoi_form_ss).

```julia
run(sampling; post_processor = populationCountQoI())                       # final-snapshot counts
run(sampling; post_processor = populationCountQoI(; index=0))              # counts at snapshot 0 instead
run(sampling; post_processor = populationCountQoI(; cell_types=["cd8"]))   # only the "cd8" cell type
run(sampling; post_processor = populationFractionQoI())                    # each cell type's share, final snapshot
```

!!! tierjournal "2026-07-08 — A ready-made builder rather than a recipe to copy"
    **Decided.** Counting the final population is what almost every campaign wants stored, so it
    ships as a builder instead of a snippet each user rewrites; it returns a `Dict` rather than a
    `NamedTuple` because cell type names may contain spaces, which are not valid field names.
    **Decided.** A snapshot that is missing — pruned by an earlier run — records nothing for that
    simulation rather than raising.

!!! tierjournal "2026-09-14 — One builder per quantity"
    **Decided.** One builder per quantity — `populationCountQoI` and `populationFractionQoI` — each
    measuring one simulation at the snapshot `index` (`:final` by default) and reduced across a
    monad's replicates by ModelManager's default per-key mean, so the sink, sensitivity analysis and
    calibration use it identically. They write `population_count.<cell_type>` and
    `population_fraction.<cell_type>` columns.
    **Rejected.** A second, endpoint-only builder beside each. Once no builder had a reducer of its
    own, it was the same measurement under another name, and it only added a second family of sink
    columns.

## Reading the stored quantities back

!!! tiergloss
    [`postProcessingTable`](@ref) returns a `DataFrame` keyed by `:SimID`;
    [`printPostProcessingTable`](@ref) prints it, and its `sink` keyword takes any function that
    accepts a `DataFrame` (default `println`). See
    [Querying parameters](@ref querying_parameters_man) for more on those tables.

```julia
postProcessingTable(sampling)                     # just the stored quantities, one row per simulation
printPostProcessingTable(sampling)                # the same table, printed
using CSV
printPostProcessingTable(sampling; sink = CSV.write("qois.csv"))  # ...or sent somewhere else
simulationsTable(sampling; post_processing=true)  # joined with the varied parameter values
```

### Checking stored values against a fresh computation

!!! tiergloss
    [`verifyStoredValues`](@ref)`(q, T)` recomputes the `QoI` `q` for the simulations of `T` and
    compares each result with the value stored for it.

!!! tierwhy
    A stored value does not record which `compute` produced it, so this is the check to run before
    relying on a `QoI` built with `stored=:prefer` or `stored=:require`, which read stored values
    instead of recomputing them. It returns a `NamedTuple` whose counts partition the simulations it
    looked at:

    - `n_checked` — every simulation of `T` (or the first `limit` of them).
    - `n_missing` — no value stored for `q`, so nothing to compare.
    - `n_unverifiable` — a stored value, but its output folder is gone or `compute` returned
      `missing`, so nothing to recompute.
    - `n_agreed` — stored and recomputed values match: numbers with `isapprox` at `rtol`, keyed
      values key by key.
    - `n_mismatched` — they differ; `mismatches` lists each one's simulation ID, stored value and
      recomputed value.

    `n_mismatched == 0` is therefore not a pass by itself: when every simulation is missing or
    unverifiable — nothing stored, or no output left to recompute from — nothing was compared and
    the count is still 0. Check `n_agreed > 0` as well.

```julia
report = verifyStoredValues(populationCountQoI(), sampling)
report.n_agreed > 0 && report.n_mismatched == 0   # something was compared, and all of it agreed
```

## [Pruning output after the callback](@id prune_output_pp)

!!! tiergloss
    Name the file types to drop in `prune_options`, and [`PruneOptions`](@ref) deletes them from
    each simulation's folder as the last step after it finishes — after your `post_processor` has
    run. `prune_svg`, `prune_mat`, `prune_txt` and `prune_xml` pick the types; the `initial*` and
    `final*` files of each type survive unless `prune_initial` and `prune_final` say otherwise, so a
    pruned simulation can still be loaded at its first and last snapshot.

!!! tierwhy
    Every save interval PhysiCell writes an XML/MAT snapshot pair and an SVG, so a campaign can
    easily grow to many gigabytes that most analyses never open. Because pruning waits for your
    `post_processor`, the callback is the place to compute what you need from the files — and it
    can do clean-up of its own: delete, compress or copy out files that `PruneOptions` has no
    switch for, or write whatever export you need, in a side-effects-only callback that returns
    `missing`.

    Know what stops working: [`makeMovie`](@ref) needs the SVGs; loading a snapshot or plotting a
    population time series needs that snapshot's XML and MAT files; a replicate whose files are gone
    is excluded from monad-level aggregates rather than zero-filled; and re-running does not bring
    the files back, since the database still holds the simulation as complete.

```julia
run(sampling; prune_options = PruneOptions(prune_svg = true))    # keep the data, drop the pictures
run(sampling; prune_options = PruneOptions(prune_svg = true, prune_mat = true, prune_txt = true,
                                           prune_initial = true, prune_final = true))
```

!!! tierjournal "2026-07-07 — Pruning runs after your callback, not before it"
    **Decided.** A simulation's post-run steps are split in two: non-destructive steps before the
    user `post_processor`, destructive ones after it. Pruning is destructive, so it runs after the
    callback; run before it, as it first was, it would have left the callback an output folder that
    had already been gutted.
    **Decided.** The rest of PCMM's post-simulation work — including how a simulation's error file
    is handled — moved after the callback too, rather than pruning alone.
