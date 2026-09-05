# [Tagging and recovery](@id tagging_man)

A PhysiCell campaign accumulates simulations faster than you can name them. Three months later
you know you ran a dose sweep for figure 3, but not which simulation IDs it produced. Tags fix
that: attach a few labels when you launch a run, then recover it by what it was *for* rather
than by remembering a number.

Tagging is provided by ModelManager and works on any trial object — `Simulation`, `Monad`,
`Sampling`, or `Trial` — and on a `Calibration`. See the
[Tags](@ref tags_lib) API reference for full signatures.

## Tag a run when you launch it

```julia
sampling = createTrial(inputs, dose_variation)
tag!(sampling, "project" => "immune-escape", "figure" => "3", "purpose" => "dose sweep")
run(sampling)
```

A tag is a `Pair` like `"arm" => "high_dose"`, or a bare key like `"baseline"` which is stored
with an empty value. Keys are lowercased and must match `[a-z0-9][a-z0-9_.-]*`; values are
stored as given.

[`recommendedTagKeys`](@ref) returns a small starting vocabulary — `project`, `purpose`,
`figure`, `arm`, `verdict`, `note`. Any valid key is accepted, but sticking to a shared set is
what makes a script you write in November find the runs you launched in August.

## Find them again

```julia
findSimulations(tags = ("project" => "immune-escape",))            # Simulation objects
findSimulationIDs(tags = ("figure" => "3",), status = "Completed") # just the IDs
findMonads(tags = ("project" => "immune-escape",))                 # one level up
findTrials(Sampling; tags = ("purpose" => "dose sweep",))          # by trial type
```

Filters in `tags` must **all** match. Pass `any_of` for an `OR` instead. A bare key means "has
this key with any value".

Tags **inherit downward**: a tag on a `Sampling` matches its constituent monads and
simulations, so you tag the sweep once rather than every replicate. Tags on an individual
simulation never propagate upward. Pass `inherit=false` to match only direct tags.

[`findSimulations`](@ref) and [`findMonads`](@ref) build objects, which is expensive for a large
result set — they throw above `limit` rather than materialising it. Use
[`findSimulationIDs`](@ref) when you only need the numbers.

## Inspect what is there

```julia
tags(sampling)          # this object's own tags, key => sorted values
hasTag(sim, "arm" => "high_dose")
tagsTable()             # the whole store as a long DataFrame
printTagsTable(sim)
tagKeys(); tagValues("arm")
```

[`tags`](@ref) returns only tags placed on that exact object — inheritance is resolved at query
time, not stored.

## Provenance you get for free

Every trial is automatically tagged with `mm:`-prefixed keys recording where it came from:
`mm:created`, `mm:session`, `mm:script` and `mm:interactive` (both are recorded, not one or the
other), and `mm:git` / `mm:git.branch` / `mm:git.dirty`. [`gitState`](@ref) is the function behind the git half, and returns
empty strings outside a repository.

The dirty flag matters: a commit hash on its own is a false promise of reproducibility if the
tree had uncommitted changes when the run launched.

```julia
tags(sim)                        # includes the mm: keys
tags(sim; include_auto = false)  # just your own
```

Pass `include_auto=false` to [`tagsTable`](@ref) as well to keep them out of a table.

## Joining tags onto a results table

Ask for them when you build the table, so you can group results by experimental arm without a
manual join:

```julia
simulationsTable(sampling; tags = true)   # adds tag:<key> columns
```

[`appendTags!`](@ref) does the pivot underneath; call it directly only to add tag columns to a
`DataFrame` you assembled yourself.

Column names are prefixed with `tag:`, so they cannot collide with the folder, parameter, or ID
columns [`simulationsTable`](@ref) already produces.

## Removing tags and housekeeping

```julia
untag!(sim, "verdict" => "suspect")   # drop one exact pair
untag!(sim, "verdict")                # drop every value under that key
```

Removing a tag that is not present is a no-op.

[`orphanedTagCounts`](@ref) reports, per trial class, how many tag rows point at objects that no
longer exist. A healthy database returns zeros; non-zero counts usually mean an interrupted
deletion.

## Silencing the hint

If a trial is created with no user tags, PCMM prints a one-time-per-session hint. Pass `false`
to [`setTagHints!`](@ref) to turn it off, or set the `MODELMANAGER_TAG_HINTS` environment
variable — the better option in a job script, since it needs no code change.
