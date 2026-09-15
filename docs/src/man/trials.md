# [Trials, samplings, monads, simulations](@id trials_man)

PhysiCellModelManager.jl organizes runs into four nested classes; this page says what each one is,
how to get one back, and how to read what it contains.

## The hierarchy

| Class | What it is | Holds |
|---|---|---|
| [`Simulation`](@ref) | One run of the model | one parameter set, one seed |
| [`Monad`](@ref) | Replicates of one parameter set | simulations |
| [`Sampling`](@ref) | Monads on one [`InputFolders`](@ref), differing in parameters | monads |
| [`Trial`](@ref) | Samplings, which may use different [`InputFolders`](@ref) | samplings |

!!! tierwhy
    You do not choose the class; you describe the runs and the class follows. That is what lets a
    script grow a `DiscreteVariation` from one value to three without any other edit — the same
    call that returned a `Simulation` now returns a `Sampling`, and [`run`](@ref) takes either.

!!! tiergloss
    [`createTrial`](@ref) returns the narrowest class that fits what you asked for: no variations
    and one replicate gives a `Simulation`, several replicates of one parameter set a `Monad`, and
    a variation with more than one value a `Sampling`. Pass a vector of already-built trials to
    bundle them into a `Trial`.

```julia
inputs = InputFolders("0_template", "0_template")

createTrial(inputs)                                                   # Simulation
createTrial(inputs; n_replicates = 5)                                 # Monad
createTrial(inputs, DiscreteVariation(configPath("max_time"),
                                      [1440.0, 2880.0]))              # Sampling
createTrial([sampling_a, sampling_b])                                 # Trial
```

## Recover one by ID

!!! tiergloss
    Each class has a constructor taking its database ID, which retrieves the existing object
    rather than creating one. [`simulationID`](@ref) reports a single simulation's ID, and
    [`simulationIDs`](@ref) descends the whole hierarchy: a `Sampling` reports the simulations of
    all its monads, a `Trial` those of all its samplings.

```julia
sim      = Simulation(5)
monad    = Monad(3)
sampling = Sampling(2)
trial    = Trial(1)

simulationID(sim)             # 5
simulationIDs(sampling)       # every simulation under it
simulationIDs()               # every simulation in the database
pathToOutputFolder(sim)       # where this simulation's output lives
```

!!! tierdev
    **Abstract type.** All four are subtypes of [`AbstractTrial`](@ref); `AbstractSampling` and
    `AbstractMonad` sit in between. [`trialType`](@ref) gives the concrete class,
    [`trialID`](@ref) the database ID, and [`trialFolder`](@ref) the folder for a class and ID
    (also accepting an [`MMOutput`](@ref), whose trial it reports on).

    **One level versus all the way.** [`constituentIDs`](@ref) reads a trial's immediate children
    from its CSV — samplings for a `Trial`, monads for a `Sampling` — and throws for a
    `Simulation`. [`simulationIDs`](@ref) and [`monadIDs`](@ref) descend the full hierarchy
    instead. [`monadID`](@ref) is the singular form on a [`SimulationProcess`](@ref ModelManager.SimulationProcess), giving the
    monad that simulation belongs to.

    **Building many at once.** [`simulationsFromIDs`](@ref) constructs a vector of
    [`Simulation`](@ref)s in one database query, skipping missing IDs. `Simulation.(ids)` is fine
    for a one-off; it issues one query each, which is what matters at campaign scale.
    `printSimulationIDs` takes an `IO` first — `printSimulationIDs(stdout, trial)` — and prints
    the hierarchy as an indented tree.

## Read what a trial contains

!!! tierwhy
    Columns that are constant across every row are dropped by default, so the table shows only
    what actually varied. Pass `remove_constants = false` when you want the full parameterization
    — for instance when the table is going into a paper's supplement rather than onto your screen.
    Add `tags = true` to group rows by what a run was for — see
    [Tagging and recovery](@ref tagging_man) — and `post_processing = true` to join in how it
    turned out.

!!! tiergloss
    [`simulationsTable`](@ref) returns a `DataFrame` with one row per simulation and one column
    per varied parameter; [`monadsTable`](@ref) is the monad-level analogue, one row per parameter
    set. [`printSimulationsTable`](@ref) and [`printMonadsTable`](@ref) send the same table to a
    sink, `println` by default. All four accept trial objects, arrays of them, ID vectors, or
    nothing at all for the whole database.

```julia
simulationsTable(sampling)
printSimulationsTable(sampling)

monadsTable(sampling)
printMonadsTable([monad, sampling])

using CSV
printSimulationsTable(sampling; sink = CSV.write("runs.csv"))
```

!!! tierdev
    Both tables are thin wrappers over a SQL query: [`simulationsTableFromQuery`](@ref ModelManager.simulationsTableFromQuery) and
    [`monadsTableFromQuery`](@ref ModelManager.monadsTableFromQuery) take the query string and own every keyword argument
    (`remove_constants`, `sort_by`, `sort_ignore`, `short_names`, `tags`, `include_auto_tags`, and
    `post_processing` for simulations only). Reach for them when you need a `WHERE` clause the
    trial classes cannot express. [`getMonadIDDataFrame`](@ref ModelManager.getMonadIDDataFrame) is the sensitivity-analysis
    counterpart, returning the monad IDs arranged in the shape the method's design requires
    rather than as a flat set.
