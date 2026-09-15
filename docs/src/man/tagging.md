# [Tagging and recovery](@id tagging_man)

Attach a few labels to a run when you launch it, then recover it later by what it was *for* rather
than by remembering a simulation ID.

!!! tierwhy
    A PhysiCell campaign accumulates simulations faster than you can name them. Three months later
    you know you ran a dose sweep for figure 3, but not which simulation IDs it produced. Nothing in
    the database records intent, so without tags the only handle on a past run is the number it
    happened to get.

!!! tiergloss
    Tagging is provided by ModelManager and works on any trial object — `Simulation`, `Monad`,
    `Sampling`, or `Trial` — and on a `Calibration`. See the [Tags](@ref tags_lib) API reference for
    full signatures.

## Tag a run when you launch it

!!! tiergloss
    A tag is a `Pair` like `"arm" => "high_dose"`, or a bare key like `"baseline"` which is stored
    with an empty value. Keys are lowercased and must match `[a-z0-9][a-z0-9_.-]*`; values are
    stored as given. [`tag!`](@ref) accepts any number of them and returns its target, so it chains.

```julia
sampling = createTrial(inputs, dose_variation)
tag!(sampling, "project" => "immune-escape", "figure" => "3", "purpose" => "dose sweep")
run(sampling)
```

!!! tierdev
    [`recommendedTagKeys`](@ref) returns the small starting vocabulary ModelManager suggests —
    `project`, `purpose`, `figure`, `arm`, `verdict`, `note`. It is advisory only: any key matching
    the rules above is accepted, and nothing validates against this list. It exists so that a script
    you write in November finds the runs you launched in August.

## Find them again

!!! tiergloss
    Each finder takes `tags` (and the other filters a trial query accepts, such as `status`) and
    returns the matching objects or IDs.

```julia
findSimulations(tags = ("project" => "immune-escape",))            # Simulation objects
findSimulationIDs(tags = ("figure" => "3",), status = "Completed") # just the IDs
findMonads(tags = ("project" => "immune-escape",))                 # one level up
findTrials(Sampling; tags = ("purpose" => "dose sweep",))          # by trial type
```

!!! tierwhy
    Filters in `tags` must **all** match. Pass `any_of` for an `OR` instead. A bare key means "has
    this key with any value".

    Tags **inherit downward**: a tag on a `Sampling` matches its constituent monads and
    simulations, so you tag the sweep once rather than every replicate. Tags on an individual
    simulation never propagate upward — a note about one bad replicate should not relabel the sweep
    that contains it. Pass `inherit=false` to match only direct tags.

!!! tierdev
    [`findSimulations`](@ref) and [`findMonads`](@ref) build objects, which is expensive for a large
    result set — they throw above `limit` rather than materialising it. Use
    [`findSimulationIDs`](@ref) when you only need the numbers.

## Inspect what is there

!!! tiergloss
    [`tags`](@ref) reports one object's tags as `key => sorted values`; [`tagsTable`](@ref) returns
    the whole store as a long `DataFrame` and [`printTagsTable`](@ref) prints it. [`tagKeys`](@ref)
    and [`tagValues`](@ref) list the vocabulary actually in use.

```julia
tags(sampling)          # this object's own tags, key => sorted values
hasTag(sim, "arm" => "high_dose")
tagsTable()             # the whole store as a long DataFrame
printTagsTable(sim)
tagKeys(); tagValues("arm")
```

!!! tierdev
    [`tags`](@ref) and [`hasTag`](@ref) return only tags placed on that exact object — inheritance
    is resolved at query time by the finders, not stored. Do not expect a `tags(sim)` round-trip to
    show what `findSimulations` matched on.

## Provenance you get for free

!!! tiergloss
    Every trial is automatically tagged with `mm:`-prefixed keys recording where it came from:
    `mm:created`, `mm:session`, `mm:script` and `mm:interactive` (both are recorded, not one or the
    other), and `mm:git` / `mm:git.branch` / `mm:git.dirty`. Pass `include_auto=false` to keep them
    out of a result — [`tagsTable`](@ref) accepts it too.

```julia
tags(sim)                        # includes the mm: keys
tags(sim; include_auto = false)  # just your own
```

!!! tierwhy
    The dirty flag matters: a commit hash on its own is a false promise of reproducibility if the
    tree had uncommitted changes when the run launched.

!!! tierdev
    [`gitState`](@ref) is the function behind the git half, and returns empty strings outside a
    repository — so the `mm:git*` keys being blank means "not in a repo", not "clean".

## Joining tags onto a results table

!!! tierwhy
    Ask for the tags when you build the table rather than afterwards, so you can group results by
    experimental arm without a manual join.

```julia
simulationsTable(sampling; tags = true)   # adds tag:<key> columns
```

!!! tierdev
    [`appendTags!`](@ref) does the pivot underneath; call it directly only to add tag columns to a
    `DataFrame` you assembled yourself. Column names are prefixed with `tag:`, so they cannot
    collide with the folder, parameter, or ID columns [`simulationsTable`](@ref) already produces.

## Removing tags and housekeeping

```julia
untag!(sim, "verdict" => "suspect")   # drop one exact pair
untag!(sim, "verdict")                # drop every value under that key
```

!!! tiergloss
    Removing a tag that is not present is a no-op.

!!! tierdev
    [`orphanedTagCounts`](@ref) reports, per trial class, how many tag rows point at objects that no
    longer exist. A healthy database returns zeros; non-zero counts usually mean an interrupted
    deletion.

## Silencing the hint

```julia
setTagHints!(false)   # or set MODELMANAGER_TAG_HINTS in the environment
```

!!! tiergloss
    If a trial is created with no user tags, PCMM prints a one-time-per-session hint.
    [`setTagHints!`](@ref) turns it off for the session; the `MODELMANAGER_TAG_HINTS` environment
    variable is the better option in a job script, since it needs no code change.
