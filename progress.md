# progress.md — PCMM Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

---

## 2026-09-15 — Tiered docs and full public-API coverage

**Problem.** An audit of every name reachable through `using PhysiCellModelManager` — exported or `public`, PCMM's own or re-exported from ModelManager — found 300 names, of which 191 had no mention on any manual page (41 PCMM, 150 ModelManager). `samplePosterior` was the reported example. The manual's PCMM/ModelManager split is invisible to a reader who only ever types `using PhysiCellModelManager`.

**Decisions**
- Adopt the tiered-docs layout (Code / Brief / Full / Dev / Journal sidebar selector; `!!! tiergloss` / `tierwhy` / `tierdev` / `tierjournal` admonitions; `docs/journal.jl` collecting dated entries into `dev/journal.md`). Client-side CSS only, so the Markdown and built HTML carry every tier and an agent reading the repo sees the deepest one.
- Every public name is classified end-user or developer. The owner reviewed the classification on a checklist artifact: 117 user, 183 dev (the design-method types `GridVariation`, `LHSVariation`, `SobolVariation`, `RBDVariation` were first classed Dev, then promoted on 2026-09-16: passing one to `createTrial` is how a user runs a Latin-hypercube or Sobol' sweep). Notable calls: `run(method, problem)` is the calibration entry point and `runABC` / `runCalibration` are Dev-tier; result types users never spell (`ABCResult`, `GenerationResult`, `XMLPath`, `ElementaryVariation`, `AbstractTrial`) are Dev-tier; the thirty-one PCMM `*Path` helpers other than `configPath` / `rulePath` / `icCellsPath` / `icECMPath` are Dev-tier; `trialID`, `constituentIDs`, `simulationsFromIDs`, the `*TableFromQuery` functions, `MMOutput`, `wasSuccessful`, `dataDir`, `isInitialized`, `upgradePackage`, `databaseDiagnostics` are Dev-tier.
- Developer-facing names that are *anchored* to a user page (the return type of a call the page shows, the older name of a function) live in a `!!! tierdev` block on that page. Structural developer content — module map, the hooks PCMM implements for ModelManager, the SQL/XML/shell helpers — gets `dev/architecture.md`, `dev/simulator_interface.md`, `dev/utilities.md`.
- The coverage test checks presence on `man/` or `dev/` pages only. Rejected: enforcing that dev-classified names appear only inside tier blocks — it needs the classification list in the test and user pages legitimately name dev symbols in passing.
- `progress.md` stays the working journal (the repo workflow depends on it). Only decisions that explain user-visible behaviour are seeded as `tierjournal` blocks. Rejected: migrating `progress.md` wholesale.
- One pull request, not three: `push_preview` gives the reviewer the finished site once; three PRs would mean three partial reviews.
- New user pages: running simulations (parallelism, HPC), the trial hierarchy, managing a project (deletion, reset, renamed names). `developer_guide.md` (five lines of style guide) becomes `CONTRIBUTING.md`.
- Baseline: the docs build on `main` was green before any change.
- The audit's "exported" bucket was really exported-or-public: on Julia 1.11+ `names(m)` returns `public` names too. It matters for the pages: a bare `[`x`](@ref)` on a manual page resolves in `Main`, where only exported names exist, so every public-but-unexported name (all of the simulator-interface hooks, `HPCCompletionOptions`, `databaseDiagnostics`, …) must be written `[`x`](@ref ModelManager.x)`. Eighty-two refs on the new pages failed the first build for this reason; the rule is now in AGENTS.md and CONTRIBUTING.md.
- Attaching the orphaned `simulationRuntime` docstring (a blank line after its closing `"""` had detached it) exposed a `jldoctest` that referenced an undefined variable; it is a `julia` block now.

**Open**
- `checkdocs = :public` instead of `:exports`; deferred until the ModelManager public set is known to be fully documented.

---

## 2026-09-14 — Issue #235: the roster `plotbycelltype` trusted, and the `output.err` nobody wrote

Two gaps from the second review pass, neither a regression. Both hide a diagnosis rather than
produce a wrong number, which is why neither showed up as a failing test.

**Decisions**
- `plotbycelltype`'s cell-type roster comes from `_samplingCellTypeRoster`: the first simulation in
  the sampling whose initial XML is still on disk, not `simulationIDs(T) |> first`. Replicates share
  a config and so share a roster, so any one of them can speak for the sampling; the first is only
  the cheapest to reach, and skipping past a pruned one costs a parse of a file that is on disk anyway.
- Review: the roster is read from an `AbstractSampling`, not any `AbstractTrial`, because only a
  sampling's simulations are guaranteed to share a config; a `Trial` gathers samplings whose rosters
  may differ. The recipe therefore refuses a `Trial` with an `ArgumentError` that says what to pass
  instead, where it used to accept any `AbstractTrial` behind a bare `@assert`.
- Rejected: the union of the rosters of every replicate that loads. It parses one XML per
  simulation — which a sampling of hundreds would pay on every plot — to defend against a ragged
  roster the PRD already records as impossible without hand-editing files under `data/`.
- Rejected: reading the roster from the config instead of the output. The config names cell types
  but the plot's data comes from the output XML's `cell_types` element, and a roster from a
  different source is a roster that can disagree with the curves.
- A trial with no readable output anywhere now throws an `ArgumentError` naming it. The old code
  drew a `(0, 1)` layout in silence, so "I pruned too much" was indistinguishable from "plotting is
  broken".
- `MonadPopulationTimeSeries`'s time-mismatch assertion names `first_kept_id` — the replicate `time`
  was actually taken from — where it named `simulation_ids[1]`, which may have been `continue`d for
  having no output. `plotbycelltype` already did this correctly with `kept_ids`; this is that fix in
  the other place.
- An IC cell / IC ECM setup failure writes its cause to the simulation's `output.err` before
  `prepareSimulationCommand` returns `nothing`. Rejected the alternative in the issue — having
  `postSimulationCleanup` annotate whenever `!success` regardless of `cmd` — on two counts: the
  cause is an exception that exists only inside the catch block and would have to be smuggled
  forward, and the `isnothing(cmd)` guard is load-bearing for the SLURM path it was written for.
- `_pathToSimulationErr` is now the single definition of that path, because the failure writer and
  the cleanup annotator agreeing on it is the whole point.
- The `println` became a `@warn`: it reaches the logger's stream rather than interleaving into
  whatever a worker was writing mid-line, and a caller can silence or capture it.

**Traps**
- The new `plotbycelltype` test stashes the first replicate's `initial.xml` and puts it back rather
  than deleting it. Monad 1's first replicate is simulation 1, and `GraphsTests.jl` and `PCFTests.jl`
  read its snapshots later in the same run.
## 2026-09-14 — One reducer for every QoI builder (#232)

**Decisions**
- **One count builder (revised 2026-09-14).** The first pass kept both `populationCountQoI` and
  `endpointPopulationCountQoI` on the grounds that two names for similar measurements is acceptable
  and both column families were already in users' databases. The maintainer reversed that once the
  two reduced identically: with no bespoke reducers left, `endpointPopulationCountQoI()` was
  `populationCountQoI()` under a second name and a second family of sink columns, so it is removed
  and `populationCountQoI(; index)` — `index` defaulting to `:final` — is the single count builder.
  Callers of the old name pass the same `cell_types`/`include_dead` keywords to the new one; the sink
  column family and the GSA/calibration label become `population_count.<cell_type>`, and
  `observed_data` keyed by bare cell type is unaffected.
- **`endpointPopulationFractionQoI` becomes `populationFractionQoI(; index)` (2026-09-14).** Having
  settled on one builder per quantity, the fraction gets the same treatment as the count: it reads
  the snapshot at `index` (defaulting to `:final`) through `PhysiCellSnapshot` + `populationCount`
  rather than `finalPopulationCount`, and the two computes share `_populationCountsAt` so the
  snapshot handling — and the `missing` a pruned snapshot produces — has one definition. The
  denominator is still summed before the `cell_types` restriction, so filtering to one type reports
  its share of everything. Sink columns and GSA labels become `population_fraction.<cell_type>`. The
  old name is removed outright, not aliased: 0.5.0 is already breaking.
- **The three monad-level statistics are removed (2026-09-14).** `endpointPopulationCounts`,
  `endpointPopulationFractions` and `meanPopulationTimeSeries` each took a monad ID and did their own
  averaging — the pre-0.9 measurement contract, which is why none of them was a valid
  `summary_statistic`. Once every builder reduced under the default per-key mean, each was its
  builder's value computed a second way, so they duplicated the builders and the tests comparing the
  two were testing float summation order. `finalPopulationCount(::Monad)` and
  `MonadPopulationTimeSeries` in `population.jl` already answer the analyse-a-finished-monad
  question, so nothing a user could do is lost.
- **What replaced the comparison tests.** The builder-vs-monad-level equalities in
  `CalibrationTests.jl` are now direct assertions on each builder's value, computed from the
  replicates' own output: `populationCountQoI` reduced over the monad equals the mean of the
  replicates' `finalPopulationCount`; every replicate's fractions sum to 1 and so does the reduced
  value; `meanPopulationTimeSeriesQoI` equals the elementwise mean of the replicates'
  `SimulationPopulationTimeSeries` counts. The pruned-replicate case keeps the same form, against the
  survivors. `_averageStatDicts` went with the deleted functions; `_excludedReplicates` stays,
  because `population.jl` logs through it at three sites.
- **The three bespoke reducers go.** `_meanEndpointCounts`, `_meanEndpointFractions` and
  `_meanPopulationTimeSeriesOf` are deleted. `endpointPopulationFractionQoI` and
  `meanPopulationTimeSeriesQoI` now define no `reduce` and are averaged by ModelManager's default
  per-key mean, as `populationCountQoI` already was; the count builder's reducer went with the
  builder. Whatever that changes numerically is accepted rather than preserved.
- **Zero-fill versus exclusion of a missing cell type is moot.** Each bespoke reducer existed to
  reconcile a replicate lacking a cell type — the endpoint pair by filling in a zero, the time series
  by shrinking the denominator. Neither case can arise: `populationCount` keys every cell type the
  model declares rather than only the ones with living cells, so the replicates of a monad, which
  share a config, cannot disagree about their roster. The default reducer's key-agreement rule is
  satisfied by construction, and the reconciliation each reducer performed was unreachable code.
- **`meanPopulationTimeSeriesQoI`'s `compute` returns the `Dict` itself.** It used to return a
  `SimulationPopulationTimeSeries` and let its reducer turn the replicates into
  `Dict{String,Vector{Float64}}`; `compute` now returns that shape directly — one entry per cell type,
  the replicate's counts on its own time grid — and the default reducer averages the vectors
  elementwise, which is all `MonadPopulationTimeSeries` ever did to them. The reducer's
  shared-time-grid assertion went with it: replicates of one monad share a config and therefore a save
  schedule. A consequence worth naming — the sink and sensitivity analysis now refuse this builder for
  the *same* reason at both ends (a component that is a series, not a `Real`), where the sink used to
  refuse an unstorable struct.
- **Agreement with the monad-level functions is now up to summation order.** `endpointPopulationCounts`,
  `endpointPopulationFractions` and `meanPopulationTimeSeries` keep their own accumulation, so the
  `==` assertions in `CalibrationTests.jl` became `≈`. They still cannot disagree about *which*
  replicates or cell types went into an average.

**Not pursued**
- The `times=`-keyed flat time-series builder from #232 (`Dict("<type>@<t>" => count)`, so the sink and
  GSA could take a series). The `Dict`-of-`Vector`s shape is what calibration wants and what
  `mseDistance` already walks, so nothing is broken; a flat form is a new feature with its own
  questions (which times are on the grid, how many columns SQLite will take) and needs its own brief.

**Removed**
- `_meanEndpointCounts`, `_meanEndpointFractions`, `_meanPopulationTimeSeriesOf`.
- In the "QoI builder reducers" testset: the zero-fill/union assertion, and the 1200-copies-of-0.1
  block that pinned the float-associativity gap between the counts and fractions reducers. Both
  described deleted code; there is one reducer now, so there is no gap between builders to pin.
- Every claim in PRD.md, README.md and the manual that a builder zero-fills, excludes a replicate from
  a key's average, or returns exactly (`==`) what its monad-level counterpart returns.

`_restrict`, `_averageStatDicts` and `_excludedReplicates` stay — the monad-level functions still use
them.

---

## 2026-09-14 — Compact the maintainer records

`progress.md`, `PRD.md`, `README.md`, the manual and the source comments restated the ModelManager
0.9/0.9.1 transition in some twenty places, and the PRD carried personas, business objectives,
success metrics and a phased release plan no session ever read. All of it is gone, under one rule:
**a record describes the present; history stays only where it explains a present constraint** — why
`populationCountQoI` writes no `count_` prefix, why each QoI builder carries its own reducer, why
`-march` defaults as it does. Every dated entry below keeps its heading and its decisions, rejected
approaches and traps; the narration around them is not kept. progress.md 1440 → 669 lines.

---

## 2026-09-14 — Figures for the GSA and calibration plots; pruning back in the manual

**Decisions**
- `docs/generate_figures.jl` also runs a MOAT(8) and RBD(16) design and a four-generation ABC-SMC on
  the template project — two parameters (a cycle phase duration and the apoptosis rate), final cell
  count as the measurement, 50 cells for two simulated days — and saves eight PNGs, embedded in
  `sensitivity_analysis.md` (which had no plotting section at all) and `calibration.md`. Committed
  PNGs, regenerated by hand when a recipe changes, because the docs CI has no PhysiCell.
- The template project, not `immune_sample`: its config parameters govern the cell count directly
  and a simulation takes seconds, where `immune_sample`'s rates are set by its custom code, so
  varying them in the XML would draw indices of nothing.
- The Sobolʼ bars are illustrative numbers pushed through the real recipe, not a measurement:
  Sobolʼ(16) — 40 simulations — estimated `ST < S1`, which no total-order index is, and the design
  that respects it, Sobolʼ(64), is 238 simulations for a picture that only shows the plot. The
  figures are there so a user sees what can be plotted.
- `prune_options` belongs on the post-processing page, not Best practices: pruning is a step that
  follows a simulation, not a practice. The section gives the `run(...; prune_options=)` call, what
  each flag removes, the ordering against the callback, and what stops working afterwards (movies,
  snapshot loading, monad aggregates).

**Traps**
- ModelManager's Sobolʼ recipe drew `ST` on top of `S1`; only drawing the figure exposed it. Fixed
  there. `PruneOptions`' docstring had separately lost `prune_xml`.

---

## 2026-09-05 — SLURM defaults PhysiCell needs; ModelManager 0.10

### `cpus-per-task` follows `omp_num_threads`
PhysiCell's `main.cpp` calls `omp_set_num_threads(PhysiCell_settings.omp_num_threads)`, so a job
starts as many threads as its config says whatever SLURM allocated — and SLURM allocates one CPU
unless asked, while every shipped sample config asks for 6–12. A cluster campaign then time-slices
six threads on one core and finishes several times slower than a single-threaded run would, with
100% CPU efficiency in `sacct` and nothing in any log to explain it. Found by the architecture
review of the 0.9 HPC path, not by a user, which is the point: it is silent.

**Decisions**
- ModelManager owns the `cpus-per-task` default and asks the backend for the number through a new
  optional interface method, `simulationThreads(sim, simulation)`; PCMM reads
  `parallel/omp_num_threads` through `getParameterValue`, so a *varied* thread count is honoured. A
  config whose element cannot be read falls back to 1 with one warning rather than failing the
  submission; a user's own `cpus-per-task` replaces the default.
- Version 0.5.0, compat bound ModelManager 0.10, whose `runSimulation` throws
  `ModelManager._SubmissionRefused` when `sbatch` refuses a job (or is absent) instead of returning a
  failed `SimulationProcess` — user-visible on a cluster. No PCMM source changed for it
  (`postSimulationCleanup` is never reached for a refused submission, as before), but `HPCTests`
  asserts the exception on the no-`sbatch` path.

**Rejected**
- Installing the `cpus-per-task` option from PCMM's `initializeModelManager` wrapper as a `Function`
  job option. Stubbing the interface method in ModelManager and implementing it here is the same
  mechanism without the wrapper, and lets every backend fill the default the same way.
- Callable structs for the builders' restorability below: also restorable, but `data=` is the
  mechanism ModelManager documents for exactly this case.

### ModelManager 0.10's QoI contract, on the PCMM side
Found by running the suite against ModelManager `main` once every 0.10 PR had merged; two files
failed (`PrunerTests`, `DocstringRefTests`) and the rest of it was prose describing 0.9.
- A post-processor returning `nothing` is refused ("say `missing`"), so `populationCountQoI` returns
  `missing` for a pruned snapshot.
- `QoI`'s default `skip_missing=true` hands `reduce` only the replicates that produced a value and
  reduces an empty monad to `missing` itself — exactly what `_reduceKept` did, which is deleted.
- The default reducer is a per-key mean, so `populationCountQoI` reaches every consumer rather than
  the sink alone. Its docstring says what that default refuses (replicates reporting different cell
  types) and that `endpointPopulationCountQoI` zero-fills instead.
- `distance` receives a `SummaryValues` carrying three spellings of each key (the key `reduce`
  returned, `"<qoi name>.<key>"`, the exact tuple); `mseDistance` iterates the *observed* keys, errors
  on one it cannot resolve, ignores extra simulated components, and divides by the number of
  differences computed.
- The builders' keyword arguments travel in the QoI's `data` slot and `compute`/`reduce` are named
  top-level functions, which JLD2 restores by name. As closures over `cell_types`/`include_dead` they
  were stored as `nothing`, so a bare `resumeABC` of any PCMM calibration refused (#234).
  `_isAnonymousFunction` ignores `data` on purpose, so nothing in ModelManager changes.
- `post_processor_qois.jl` is folded into `standard_qois.jl`: it existed (#217) only because
  `populationCountQoI` was written for the sink alone, back when the default reducer could not
  combine keyed values. Collapsing `populationCountQoI` into `endpointPopulationCountQoI` is #232 and
  still needs its own brief (zero-fill vs the default reducer, column names).
- `registerSimulator!` is the public registration half of the backend contract and `mm_globals_ref`
  is internal again, so `__init__` registers through it and `_pcmmGlobalsRegistered`'s docstring
  drops its `@ref` to the Ref — that `@ref` was the `DocstringRefTests` failure.
- `docs/make.jl` runs `checkdocs=:exports` over ModelManager too, so every new ModelManager export
  needs a home in `docs/src/lib/`: `samplePosterior` and `createTrial(::ABCResult, ::DataFrame)` are
  listed in `lib/calibration.md`.

**Traps**
- The test comparing the builders with the monad-level functions held its own copy of ModelManager's
  reduction seam, and the copy is what drifted. It evaluates through ModelManager's seam instead.
- `march_flag` is set by PCMM's own `initializeModelManager` method, not by ModelManager, which
  knows nothing about the flag: `PhysiCellSimulator`'s constructor runs before the probe exists.

### Housekeeping
- `requestHeaders` treats an empty `PCMM_PUBLIC_REPO_AUTH` as unset. An empty value sent
  `Authorization: token ` and GitHub answered 401 to a request that succeeds anonymously, so a shell
  exporting the variable empty broke `createProject(; clone_physicell=false)` locally.
- `src/sensitivity.jl` and `src/user_api.jl` were comment-only placeholders left from the
  modularization; deleted with their includes. The docs pages of the same names render
  ModelManager's files by filename, so they are unaffected.

---

## 2026-09-02 — ModelManager 0.9 migration and the release backlog

Seven release-backlog items arrived with the ModelManager 0.9 bump. Two — a compile error leaving a stale
executable, and re-checking the PhysiCell version mid-session — were already done in the 2026-08-19 entry and
should not be re-investigated; PhysiPKPD inputs was deferred to a CLAUDE.md to-do.

**Decisions**
- **Version 0.4.0, not 0.3.4.** `runStudio`'s error type, `configPath` rejecting unrecognised tokens, and
  `plotbycelltype`'s corrected numbers are breaking on their own terms. Compat bound `"0.9.1"`, not `"0.9"`:
  `"0.9"` resolves to `[0.9.0, 0.10.0)` and would let a project resolve 0.9.0 while the docs promise behaviour it
  lacks.
- **`rm_hpc_safe`'s new contract** (remove first, stage the residue, return `:removed`/`:staged`) is a test-side
  change; the staging path is left uncovered rather than faked, since on a healthy filesystem nothing is staged.
- **`prepareBaseFile` on an unselected `:rulesets_collection`.** The `AssertionError` was PhysiCellXMLRules being
  right about its own contract; PCMM should never have made the call. Testing `location == :rulesets_collection`
  before the `ismissing(input_folder.basename)` guard was the bug; reordering the two branches is the whole fix.
- **`PCMM_PUBLIC_REPO_AUTH`: bound the cascade, do not fix the token.** Leave the token a GitHub secret and accept
  the local failure, on condition that it costs exactly one error. (Superseded 2026-09-05: an empty value is
  treated as unset.)
- **Missing data is audible.** `@info ... maxlog=1`, not `@warn`: pruning is a deliberate user action. `maxlog=1`
  is load-bearing — calibration calls these once per monad across thousands of particles — and Julia scopes it per
  callsite, so each of the four aggregation sites still reports. They share no implementation, which is both why
  each needs its own `@info` and how `plotbycelltype` came to divide by the unfiltered replicate count while
  filling only the loaded replicates.
- **`configPath("<cell type>", "motility", <tag>)` closes the class, not the instance.** A natural guess must
  resolve or be rejected by name, so an unrecognised third token under `<motility>` or `<chemotaxis>` — both closed
  tag sets — raises an `ArgumentError` naming the valid ones. `advanced_chemotaxis` stays open-ended because its
  third token is a substrate name. The regression test asserts the two- and three-token spellings agree.
- **One `Dict`-valued `QoI` per calibration statistic**, not a `Vector{QoI}` with one per cell type.
  ModelManager passes a single QoI's value through unwrapped and keys only a *vector* by QoI name, so one
  Dict-valued QoI hands `mseDistance` the flat dict it wants; the plural shape had been written against an earlier
  PR that wrapped every value. `cell_types` is therefore optional, as for the monad-level functions.
- **Each `reduce` is its monad-level function's own aggregation step**, so the `==` assertions guard a
  transcription rather than a reimplementation. Three reducers, deliberately not shared, because the statistics
  disagree:

  | | cell type absent from a replicate | summation |
  |---|---|---|
  | counts | zero-filled | `mean` over a generator |
  | fractions | zero-filled | `mean` over a materialised `Vector` |
  | time series | not zero-filled | `mean(array, dims=2)` |

  One deliberate deviation from bit-exactness: where every replicate is missing,
  `meanPopulationTimeSeriesQoI` returns `missing` where `meanPopulationTimeSeries` raises an incidental `KeyError`.
- **Every measurement function receives a `Simulation` (#46)** — `summary_statistic`, `functions=`,
  `post_processor` and a `QoI`'s `compute` — and ModelManager reduces the replicates. The `QoI` builders are the
  migration path for the three monad-level statistics, which stay for monad-level analysis. Every measurement
  function in PCMM's tests and docs is annotated `::Simulation`, because an untyped monad-level statistic returns
  a different number rather than erroring.
- **PCMM tests do not pin ModelManager internals.** The equality test reached into
  `ModelManager._asSummaryStatistic`, which #46 renamed; it now goes through each QoI's documented `compute`/`reduce`.
- **`simulationCommand` replaces `runSimulation` (#47).** PCMM's method is one line returning
  `prepareSimulationCommand(spec.simulation)`; ModelManager owns launching, redirection, `sbatch` wrapping and
  completion detection. PCMM's own `hpc.out`/`hpc.err` redirection is deleted (two writers would race); the
  `mkpath` of the `output` subfolder stays.
- **The `Cmd` carries no `env`.** ModelManager refuses one, rightly: `Cmd.env` *replaces* the environment where
  `sbatch --export` extends it. Removing `env=ENV` was a no-op locally (a child inherits the environment, including
  the `DYLD_LIBRARY_PATH` entry for libRoadrunner). `dir` stays.
- **`postSimulationCleanup` reads `.cmd`, not `.process`.** `process === nothing` is now the norm for a
  *successful* HPC simulation, so testing it would have silently skipped the hook for an entire cluster campaign —
  no pruning, `output.err` never cleaned. `isnothing(cmd)` is what `isnothing(process)` used to mean.
- **`gsaLabels` needs the `ModelManager.` prefix.** It is public there but not exported, and `@reexport` forwards
  exports only.
- **Key sets come from the model's roster** — `cellTypeToNameDict` of the **initial** snapshot, not the set of
  types with living cells. Keying off observed cells would hit sensitivity analysis's same-keys requirement on
  every sweep that kills a population.
- **No `up.jl` milestone for the `count_` → `population_count.` column rename.** `postprocessing.db` is
  ModelManager's sink, not PCMM's schema, and a migration could not tell this builder's `count_<x>` columns from a
  user's own `QoI("count_foo")`. The rename rides along with the compat bump so a stored column is renamed once;
  old rows keep the old columns and new rows fill the new ones, and `post_processing.md` says so.

**Rejected**
- A typed `PCMMMissingInputFile` for a *selected* rulesets folder holding neither `base_rulesets.csv` nor
  `base_rulesets.xml`: unreachable, because `InputFolder`'s constructor already refuses such a folder.
- Guarding a ragged cell-type roster. The trust boundary sits at the data directory, and guarding one tampering
  route implies guarding them all; a comment at the aggregation site records the assumption. (A stale
  `summary/population_time_series.csv` is not a route: it lives inside one simulation's folder, whose config is
  fixed.)
- Falling back to the last row of `summary/population_time_series.csv` in `finalPopulationCount` when
  `final.xml`/`final.mat` are pruned — the substitution would be undetectable. If a cache is ever wanted, write one
  for the final snapshot at run time.

**Traps**
- `PhysiCellVersionTests.jl` restores the original project *after* a download that 401s without a token, so one
  401 silently disabled every later testset, `PhysiCellStudioTests` and `DocstringRefTests` included. The download
  section is wrapped so the restore always runs.
- `PhysiCellStudioTests` only ever passed a nonexistent `fake_python_path`, so the branch where Studio runs and
  exits non-zero had never been exercised.
- The summation-order test input must cross Julia's pairwise-summation blocksize (1024), e.g. `fill(0.1, 1200)`, so
  the divergence follows from the algorithm. Below it, divergence comes from SIMD reassociation, which is
  CPU-dependent — a vector that diverges on an ARM Mac need not diverge on CI — and a random search found nothing.
- A test that prunes a replicate must build a monad nothing else can match. PCMM reuses matching simulations, so
  `Monad(1; n_replicates=3)` was *the same monad* `PopulationTests` builds, which then failed on the missing output.
  The fixture is distinguished by a phase duration no other test uses.
- An untyped measurement function is what lets a stale contract keep looking healthy: `PostProcessorQoITests`
  constructed a `SimulationProcess` by hand and passed it to the then-untyped `populationCountQoI` closure, so the
  suite kept passing against a contract ModelManager had already replaced.

**Open questions**
- **PhysiPKPD inputs.** Deferred deliberately. Needs a design brief covering how dosing schedules are represented,
  where they live under `inputs/`, and how they are varied.
- The `InputFolder` rejection of a rulesets folder with no rules file *is* reachable by ordinary user error and
  raises a bare `ErrorException`; if typed errors for GUI consumption are wanted, it belongs in ModelManager.

---

## 2026-08-19 — Name the executable for the PhysiCell version; drop `physicell_commit_hash.txt`; check that version at every compile

`loadCustomCode` decided whether to recompile from two records that could disagree: `physicell_commit_hash.txt`
was written *before* `make` ran and the executable was always named `project`, so a compile error left the old
binary next to a file claiming the new version, and the next run silently used a binary built from different
PhysiCell source. `macros.txt` had the same defect. Separately, the PhysiCell version was resolved once, at
initialization, so a PhysiCell edited or checked out mid-session was neither recompiled for nor recorded.

**Decisions**
- One record instead of two: the executable is named `project_<physicell-version>` and its existence *is* the
  record that a build for that version finished; `physicell_commit_hash.txt` is gone.
  `unreproduciblePhysiCellVersion()` names the dirty/downloaded case, where the source can change without the
  version changing, so those recompile every run.
- `macros.txt` is written only after `make` succeeds; `neededMacros(S)` computes the list in memory and
  `compilerFlags` compares it against the file to decide `recompile`/`clean`.
- Old executables are kept: the name is a cache key, so switching PhysiCell versions back and forth does not force
  a rebuild. They live in a `pcmm_build/` subfolder PCMM owns, so `clearSimulatorArtifacts` (via `resetDatabase`)
  removes the directory rather than matching a glob, and matches each legacy name exactly.
- Legacy `project` and `physicell_commit_hash.txt` are removed by `removeLegacyBuildArtifacts` after the first
  successful compile, not by an `up.jl` milestone: the upgrade is self-healing, since the first run recompiles.
- A build that does not finish deletes the executable it was replacing (`abandonBuild`). The recompile may have
  been forced by changed macros, `force_recompile`, or a dirty tree with the current version's executable still
  present; in the `force_recompile` case the next run would otherwise reuse a binary the user asked to replace.
- The version string is sanitized before it becomes a file name (`VERSION.txt` from a download is not guaranteed
  tame), and `make` exiting 0 without producing the executable is a failure return, not an unhandled `mv` error.
- `refreshPhysiCellVersion()` runs as the first statement of `loadCustomCode` — the single funnel for compilation,
  once per sampling, before recording. With the version in the executable name, re-resolving it *is* the guard: a
  moved HEAD changes the name, a dirty tree flips `unreproduciblePhysiCellVersion()`, and the recorded version
  reads the same field. Cost: one `git status --porcelain` per sampling (~30 ms).
- Resolve quietly, report in one line: the refresh prints `PhysiCell version changed. Now using <info>.` only
  when the id moved. No opt-out — recording the wrong commit hash is corruption, not a preference.
- `PhysiCellSimulator.strict_check` deleted. Documented on an exported type as requiring a clean tree to skip
  recompile and read nowhere under either of its names since the modularization; the behaviour exists
  unconditionally in `unreproduciblePhysiCellVersion()`. Breaking only for a nine-positional-argument construction.

**Rejected**
- Pruning old executables on each successful compile: it would delete a binary another session on a shared
  filesystem may be about to launch.
- Making a delete-glob safe (`project*`, then `project_`): `project_notes.md` is indistinguishable from
  `project_<hash>`. A folder PCMM owns ends the argument.
- Deleting the executable up front, before `make`: covers a `kill -9` mid-compile that `abandonBuild` does not, but
  removes the binary for the whole rebuild (the final `mv` is an atomic swap), so a concurrent session on a shared
  filesystem would fail to launch for minutes rather than an instant.
- Refreshing the version per simulation: would let one sampling straddle two PhysiCell versions.
- Keeping `strict_check` as an off-switch under a name stating its consequence (`recompile_if_unreproducible`):
  it would record a clean hash for a tree that is not that commit; "make a new commit or stash changes" is better.

**Traps**
- The regression test must let a real build happen after the failure path (swap in a `Makefile` whose recipe is
  `@exit 1`, plant the stale `project` + hash-file pair, check `loadCustomCode` returns `false` and the executable
  is gone, then check the next call rebuilds). An earlier version moved the executable aside to save a build,
  which left the failure path nothing to lose.
- `PhysiCellVersionTests.jl` dirties the repository the same way but re-initializes afterwards, which is why the
  missing mid-session refresh was never caught. The guard test edits a tracked PhysiCell file without
  re-initializing and restores it in `finally`. Not covered: checking out a different commit (same code path).

**Open questions**
- The name carries no OS, architecture, or compiler-flag component, so copying `data/` to another platform still
  reuses an unrunnable binary. A march/ISA component in `executableName` is the remaining step for the deferred
  `-march` work (2026-08-05).

---

## 2026-08-05 — `-march` selection: investigation only, implementation deferred

`PhysiCellSimulator()` picks `march_flag` as `isRunningOnHPC() ? "x86-64" : "native"`, and `isRunningOnHPC()` is
`which sbatch`. Investigated whether a better check exists; a design brief was written and deliberately shelved.
Nothing implemented. Read this entry before touching `march_flag`.

### The predicate is about scheduler presence, not architecture
The compiled executable is persisted and reused by later sessions, and its cache key (the PhysiCell version) has
no ISA or march component. The real question is "will this on-disk binary ever be executed by a machine that did
not build it", which the current session cannot answer: a login-node compile with `useHPC(false)` bakes in that
node's ISA and a later session can flip `useHPC(true)`, and a compile inside an allocation on node A is followed by
an array job on older node B. A batch scheduler is precisely the thing that hands a binary to a different machine,
so its presence is a good proxy. Compilation is a plain `run(...)` from the Julia process, never scheduled.

### Three failure classes — only two are `-march`-addressable
| Case | build → run | fails at | fixable by `-march`? |
|---|---|---|---|
| mixed µarch, one ISA | Haswell → Ivy Bridge | run (SIGILL) | yes — already fixed by the `x86-64` default |
| uniform non-x86 cluster | aarch64 → aarch64 | compile (`unknown value 'x86-64' for -march`) | yes — needs an arch-aware fallback |
| mixed-ISA cluster | x86 login → aarch64 nodes | run (`ENOEXEC`, "Exec format error") | **no** |

The third row is real hardware (Ookami pairs x86 login nodes with A64FX compute nodes; Grace-Hopper partitions on
x86 clusters are appearing). It is a cross-compilation problem PCMM's compile-then-submit structure cannot support
without an `sbatch`'d compile on the target partition plus an ISA-keyed executable cache. Recommendation: document
as unsupported ("run Julia on a node with the same architecture as your compute partition"); it fails legibly at launch.

### Findings that constrain any future design
- **There is no public API for this.** `setMarchFlag` is internal (no export, no `@compat public`); the test suite
  reaches for it as `PhysiCellModelManager.setMarchFlag`. A user whose auto-detection guesses wrong has no
  supported recourse — this is the gap a `PCMM_MARCH` env var closes.
- `run_on_hpc` and the march flag are already decoupled: `isRunningOnHPC()` has one caller (the march default) and
  `useHPC` cannot affect compilation. Using the global would be wrong anyway: the cached binary spans compile time
  and run time, and the global's value at one does not constrain the other.
- **`x86-64-v3` is exactly the Haswell feature level** and therefore the *risky* choice on the cluster whose
  pre-Haswell nodes originally broke `native`. Never a default; opt-in only.
- **`-m64` is hardcoded** in `cflags` and is x86-only; fixing `-march` alone will not make an ARM Linux cluster
  compile. The two must move together.
- An env var does not solve the arch problem (a dotfile follows you onto any machine). Validate the resolved flag
  against the actual compiler before `make` (`g++ -march=<flag> -fsyntax-only -x c++ /dev/null`): one cheap
  subprocess that catches a stale dotfile, a typo, and an auto-detected `x86-64` on an ARM cluster.

### Deferred design (PCMM side, ~70 lines src / ~50 test / ~15 docs, risk low–medium)
1. `_defaultMarchFlag()` — `get(ENV, "PCMM_MARCH")`, then the probe.
2. `_mayRunOnOtherHosts()` — ``isRunningOnHPC() || shellCommandExists(`qsub`) || shellCommandExists(`bsub`)``.
   Deliberately disposable scaffolding, to be replaced by `scheduler() !== :none` once ModelManager grows a
   scheduler abstraction; say so in a source comment.
3. `_marchFlagSupported(compiler, flag)` — validate at first compile (not `__init__`), memoized per
   `(compiler, flag)`; skip when `shellCommandExists(compiler)` is false so `make` keeps producing its usual error.
4. Promote `setMarchFlag` with `@compat public` — an env var for a knob whose function form is internal is incoherent.
5. Docs: a short section in `installation.md` (there is no central env-var page) plus two lines in
   `known_limitations.md` for the mixed-ISA case.

Release note: PBS/LSF/SGE users move from `native` to `x86-64` — correct, but slower on a homogeneous non-Slurm
cluster. `PCMM_MARCH=native` restores it.

### Rejected
- Widening `isRunningOnHPC` itself: the name honestly means "Slurm is available", and the HPC submission path is
  Slurm-specific. The march decision wants its own predicate.
- An Lmod / `MODULESHOME` check: a proxy for a proxy, a false positive for Homebrew-Lmod workstations, and redundant
  with the scheduler probes.
- Parsing `scontrol show nodes` to detect a heterogeneous partition: fragile, slow, needs permissions.
- Compiling inside the job so `native` is safe and optimal: the missing piece is keying the cached executable on
  the ISA it was built for, which is a real feature; `x86-64-v3` gets most of the performance for a fraction of the
  work. (2026-08-19: the artifact is now keyed on the PhysiCell version; a march/ISA component is the remaining step.)

### Open questions
- Why deferred: the `x86-64` default is correct for the common case; the live gap is only the silent `native` on
  non-Slurm sites.
- **Multi-scheduler submission is a separate repo and a separate brief.** ModelManager builds
  `sbatch --wrap="<command>"` and PBS has no `--wrap`; `--$k=$v` is Slurm long-option syntax applied to every user
  option, and `defaultJobOptions()`'s keys are Slurm names. Needs a semantic job-options layer, a rename of
  `sbatch_options`, and a deprecation path (`defaultJobOptions` is public).
- Ordering: the PCMM march branch is self-contained (needs only exported `isRunningOnHPC` and public
  `ModelManager.shellCommandExists`), so it can land first at the cost of ~6 throwaway lines.

---

## 2026-08-03 — Stop `__init__` from auto-initializing during precompilation

The logo and status banner printed repeatedly, apparently once per package in the environment that did
`using PhysiCellModelManager`. Julia runs a module's `__init__` at most once per process per load; the repeats came
from the precompilation *subprocess* of each dependent package, whose output Julia 1.12 surfaces boxed under the
dependent's name. Because the worker inherits the parent's working directory, precompiling an unrelated package
from inside a project folder also had PCMM open the real project database.

**Decisions**
- Gate on `jl_generating_output`: `_generatingOutput()` is true exactly while a cache file or sysimage is being
  written. `@static if isdefined(Base, :generating_output)` prefers Base's wrapper (not `public`, and its body is
  the same `ccall`, but Base then owns the mapping), falling back to the raw `ccall`.
- The globals are registered *before* the early return — pure in-memory work that keeps `mm_globals()` usable for
  a `PrecompileTools` workload in a dependent package. Only `initializeModelManager()` is skipped.
- `_pcmmGlobalsRegistered()` checks `globals.simulator isa PhysiCellSimulator`, not just that the ref is set, so
  PCMM reliably claims the globals from another backend instead of silently running against a foreign simulator.

**Rejected**
- Guarding on `mm_globals_ref[]` being non-`nothing` (plus `isInitialized()`): PCMM's own `__init__` is the only
  assignment site, so in a fresh worker the ref is always `nothing` and the guard falls through. Keyed on the ref
  alone it would also return before registering `PhysiCellSimulator` when another backend had initialized first —
  `simulator().compiler` throws `FieldError` and `setupMonad` dispatches to the other backend.

**Open questions**
- Whether two ModelManager backends should ever coexist in one process. `ModelManagerGlobals` holds one
  `simulator`, so today they cannot; coexistence needs a per-backend registry in ModelManager.

---

## 2026-08-02 — Absorb ModelManager's docs-findability pass; declare PCMM's public API

`docs/make.jl` uses `checkdocs=:exports` over both modules with no `warnonly`, so any ModelManager export with no
matching PCMM `Pages` entry turns the build red. That is the standing obligation this session set up for.

**Decisions**
- **Reachability defines the public API**, not ModelManager's rule ("not underscore-prefixed, so never internal",
  which here would promote ~174 of 177 non-public bindings). A name is public if we tell users how to use it, or
  if it is passed to or returned from a non-internal. Internals do not appear in the docs at all. Run the closure
  to a fixpoint; count types users receive or pass, not types that merely appear in a dispatching method's signature.

**Rejected**
- Per-method docstring splitting so internal-dispatch methods stay unrendered. `@autodocs` filters per binding, not
  per signature, and `missingbindings` removes one signature at a time, so rendering only some methods of an
  exported function is a `:missing_docs` error. Fallback: leave the internal internal and strip the `@ref`.

**Traps**
- Backticked sub-headings shadow docstrings: Documenter's `Header` resolver runs before `Docs`, and the build stays
  green. PCMM had ~17 such headings; they need explicit `@id`s.
- A PCMM-authored docstring on a ModelManager binding (`src/deletion.jl` on `clearSimulatorArtifacts`) lives in
  `meta(PhysiCellModelManager)`, so a page listing `Modules = [ModelManager]` only does not render it.
- An `@autodocs` block whose `Pages` glob matches nothing fails silently, and `Pages` matching is `endswith`, so
  `utilities.jl` also matched ModelManager's `xml_utilities.jl`.

---

## 2026-07-23 — Migrate `src/loader.jl` onto PhysiCellOutput.jl

`src/loader.jl` (~865 lines) duplicated the path-based, stateless loading that now lives in PhysiCellOutput.jl.
PCMM keeps only its database-identity layer.

**Decisions**
- Preserve the API by extending PhysiCellOutput's own constructors, not by wrapping them in a PCMM-owned type: the
  only internal callers are `src/analysis/*.jl`, heavily typed on the concrete
  `PhysiCellSnapshot`/`PhysiCellSequence` types and reading their fields, and a wrapper must not subtype
  `AbstractPhysiCellSequence` and would rename the public constructors. The piracy is confined to one file and
  tolerable because PCMM is the terminal application in the stack.
- `assertInitialized()` stays at PCMM's id-based entry points; PhysiCellOutput does not assert.
- PhysiCellOutput's `PhysiCellSequence` has no `simulation_id`, so the three sequence-typed builders that stamp
  results with it receive the id threaded from the entry point.
- Accepted: `show(::PhysiCellSnapshot)` prints `Folder=…` rather than `SimID=…`.

---

## 2026-07-22 — Vector/range dispatch for `makeMovie`

`makeMovie(4:7)` and `makeMovie(Simulation.(4:7))` threw `MethodError`; only the scalar `Int`, single
`AbstractTrial`, and `PCMMOutput` forms existed.

**Decisions**
- `makeMovie(::AbstractVector{<:Integer})` reuses the announce → loop → delegate shape of the `AbstractTrial`
  method; `makeMovie(::AbstractVector{<:AbstractTrial})` flattens to IDs via `simulationIDs` and reuses it.
- The worker signature is broadened from `Int` to `Integer`, since `simulationIDs`' elements are not guaranteed to
  be `Int` and downstream already accepts `Integer`.

---

## 2026-07-08 — Expose Makefile animation parameters (`framerate`, `magick_density`, `magick_resize_x/y`) in `makeMovie`

`makeMovie` forwarded only `OUTPUT=` to the PhysiCell Makefile, which also reads `FRAMERATE`, `MAGICK_DENSITY`,
`MAGICK_RESIZE_X`, `MAGICK_RESIZE_Y`.

**Decisions**
- Four keywords, each `Union{Missing,Int}=missing`, mirroring the existing `magick_path`/`ffmpeg_path` sentinel
  pattern. A `missing` keyword is not appended, so the project's own Makefile default applies rather than PCMM
  overriding a user's Makefile customization.
- `framerate` goes to the `movie` target and the three `magick_*` keywords to `jpeg`, matching which target reads
  which variable. The trial/output methods forward `kwargs...` unchanged.

---

## 2026-07-08 — Task B: `populationCountQoI`, a ready-made `post_processor` builder

Task A made `post_processor` usable; a user still had to know which loader to call and how to shape the return.
The user asked for final counts *and* any indexed save.

**Decisions**
- New file `src/analysis/post_processor_qois.jl`, separate from `standard_qois.jl` (a different consumer).
  (Folded back into `standard_qois.jl` on 2026-09-05, when one `QoI` came to reach every consumer.)
- Returns a `Dict`, not a `NamedTuple`: cell type names can contain spaces, which are not valid field names. (The
  `count_` key prefix chosen here was dropped on 2026-09-02.)
- A missing snapshot (e.g. pruned) records no QoI rather than erroring. (It returned `nothing` here; 0.10 refuses
  `nothing` and it returns `missing`.)

---

## 2026-07-08 — Docs for batch `run(Vector)` and the calibration evaluation budget (D5/D6)

Third handoff from the ModelManager session; both changes are inherited via `@reexport`, so this is doc-only.

**Decisions**
- `max_evaluations` caps before each batch, so the final generation may be partial, and the budget counts
  particles: a calibration launches up to `max_evaluations × n_replicates` simulations. Verified against
  `_capBatchToBudget`.
- **Style (user feedback, applies going forward):** docs pages state current behaviour directly; no "used to be X,
  now Y" and no references to the conversations that produced a change. The before/after narrative belongs here.

---

## 2026-07-07 — Post-processing hook: move pruning to `postSimulationCleanup` (Task A)

ModelManager split the per-simulation post hook into `postSimulationProcessing` (non-destructive) → user
`post_processor` → `postSimulationCleanup` (destructive). PCMM pruned in the first, so a callback would have seen
a gutted output folder.

**Decisions**
- Move the whole body, not just pruning: err-file handling runs equally well after the callback, and
  `postSimulationProcessing` is left at ModelManager's no-op default.
- Import wiring: `postSimulationCleanup` in the extending `import ModelManager:` list; `postSimulationProcessing`
  kept in the non-extending `using` line so its docstring `@ref` resolves (the hooks are not exported).
- No compat change: the feature ships in a `0.7.x` bump.
- `monadsTable` (new in ModelManager) is documented in `querying_parameters.md` beside `simulationsTable`; the docs
  nav section `"Experiments"` is renamed `"Uncertainty Quantification"` to match ModelManager.

**Open questions**
- Task B: `populationCountQoI(; index=:final)` on `PhysiCellSnapshot(sim_id, index)`.
- Release lockstep: Task A must not ship against a ModelManager with the old single-hook ordering.

---

## 2026-06-15 — Upgrade-path CI for `src/up.jl`

`src/up.jl` was untested: exercising a migration needs two package versions present, which cannot coexist inside
`Pkg.test()`.

**Decisions**
- "Go backwards": generate a project with an older *released* version and upgrade it with the dev checkout, so the
  repo's actual `up.jl` is exercised, rather than upgrading to a released version and testing released migration
  code. Verification reads SQLite directly.
- The generation API is unchanged across `0.1.7` and `0.2.2`, so one `generate.jl` serves both matrix entries.
- Early hops assert data preservation, not migration-specific deltas, because `upgradeToV0_3_0`'s `calibrations`
  table is also created by `initializeDatabase`.
- The first run caught a shipping bug: `upgradeToV0_2_0` called `validateParsBytes` unqualified after the
  modularization moved it, unexported, into ModelManager, so every `0.1.7` upgrade threw and rolled back. Fixed by
  adding it to `up.jl`'s explicit `using ModelManager:` import.

**Rejected**
- A `target_version` cap on `initializeModelManager`: `upgradePackage` always upgrades to the runtime version, and
  adding a cap is a ModelManager change.

**Open questions**
- How far back the generation API can be reused; the `pcvct` era will likely need an older script, and it is not
  known whether `pcvct@0.0.3` stamps a version table the newer code can read.

---

## 2026-06-12 — Documentation restructure for clarity & discoverability

Users repeatedly asked how to use PCMM. The docs were accurate but a flat 17-item manual in arbitrary order, a
34-page alphabetical API dump, and a getting-started page that buried the happy path under `importProject`.

**Decisions**
- Sidebar regrouped by user intent; getting-started split into `installation.md`, `julia_environments.md`,
  `getting_started.md` (happy path only) and `importing_projects.md`; `examples.md` as a cookbook hub; `index.md`
  as a hub with a "Where do I look?" table.
- API reference grouped by code family, hand-maintained, with the alphabetical Index kept for name lookup.
- Colliding section refs resolved with explicit `@id`s (`examples_cookbook`, `calibration_section_man`).

**Rejected**
- Mirroring the Manual and API reference structures: redundant and high-maintenance; they serve different purposes.

---

## 2026-05-17 — MM 0.7.0 calibration features; CI registration gap

All calibration infrastructure moved to ModelManager 0.7.0 and PCMM pins `ModelManager = "0.7.0"`, but 0.7.0 was
not yet registered in BergmanLabRegistry, so PCMM CI could not resolve it.

**Decisions**
- Fix sequence: merge ModelManager `feature/latent-inverse-maps` → `main`; register 0.7.0 in BergmanLabRegistry
  (`Versions.toml` entry with the new `main` tip's git-tree-sha1); re-run PCMM CI.

---

## Rollback anchor — last commit with functioning pyabc backend

The last commit with the fully-wired PythonCall/pyabc backend, for a side-by-side comparison against native
ABC-SMC, is `9d9dda07aa1464db02a9aeb1d0171d3f32db15f0` ("Merge branch 'main' into feature-par-naming"; the last
substantive pyabc change is `2d575527`). Restore it with
`git checkout 9d9dda07aa1464db02a9aeb1d0171d3f32db15f0 -- ext/PCMMCalibrationExt.jl CondaPkg.toml Project.toml src/calibration/`
or branch from it directly.

---

## 2026-04-25 — PCMM side of SimulationSpec flatten / setup-collect split

Counterpart to the ModelManager refactor of the same date; see ModelManager's `progress.md` for the rationale.

**Decisions**
- `setupSampling` accepts `AbstractSampling`; `setupMonad` accepts `AbstractMonad` and needs no `do_full_setup`
  kwarg, since `setupSampling` always runs first and covers compilation. `monad_id` is always an `Int`, so no
  `ismissing` branch is needed on it.

---

## 2026-04-24 — Remove PythonCall / pyabc deprecation residue

Native ABC-SMC passed the full suite, so the deprecated pyabc surface promised for removal on 2026-04-22 is
deleted: `ext/PCMMCalibrationExt.jl`, `CondaPkg.toml`, every `PythonCall` entry in `Project.toml`, and the
"Deprecated pyabc backend" sections of `calibration.md` and PRD.md. Rollback is via the commit hash recorded above.

---

## 2026-04-24 — `AbstractSimulationSpec` / `SimulationSpec` refactor

Replaced the calibration's `redirect_stdout(devnull)` stopgap with a real `quiet=true` kwarg on `run` by
completing the SimulationSpec refactor across ModelManager and PCMM.

**Decisions**
- `AbstractSimulationSpec` (ModelManager) is an extension point for simulators with distinctive per-spec state, not
  a dispatch axis. `SimulationSpec` is the concrete default (`simulation` + `monad_id`); PCMM uses it directly.
- One dispatch axis — the simulator type. `runSimulation(::AbstractSimulator, spec)` does all simulator-specific
  routing; simulator flags like `force_recompile` flow as kwargs through `run`.

**Rejected**
- A separate `dispatchSimulation(::AbstractSimulationSpec)` stub: redundant with simulator dispatch for one spec
  type per simulator, and by spec time all simulator-specific routing is done.

---

## 2026-04-22 — Julia-native ABC-SMC (replacing pyabc)

The pyabc backend (PythonCall/CondaPkg) worked but carried conda environment management, a `SingleCoreSampler`
constraint (Julia closures cannot be pickled), and a deep bridge.

**Decisions**
- Implement ABC-SMC directly (Toni et al. 2009 / Beaumont et al. 2009), no new dependencies, on PCMM's
  Monad/runner infrastructure. Framework-agnostic core: `abc_smc.jl` operates on an
  `evaluate_particle(params) → (distance, metadata)` callback and PhysiCell wiring is isolated in `abc.jl`, so the
  core can move to ModelManager.
- `AbstractCalibrationMethod` supertype with `ABCSMC` as the first subtype; `runCalibration` dispatches on it and
  `runABC` is the keyword convenience.
- No warm-start from existing simulations: seeding generation 1 biases it away from the prior.
  `Monad(...; use_previous=true)` still reuses exact-match points transparently.
- Each generation saved as CSV with `method.toml`, enabling `resumeABC`.

**Rejected**
- ApproxBayes.jl (`Distributed.jl` parallelism conflicts with the Channel-based runner; dormant), KissABC.jl
  (archived), GpABC.jl (compatible with modern Julia after all — its `"1.6, 1.7"` compat is an intersection — and
  worth revisiting for GP emulation), SimulationBasedInference.jl (ABC-SMC incomplete).

**Open questions**
- GP emulation (GpABC.jl or custom) as `GPAcceleratedABC <: AbstractCalibrationMethod`.

---

## 2026-03-31 — Optional names for variations

**Decisions**
- Optional `name` on `DiscreteVariation`, `DistributedVariation`, `CoVariation`, `LatentVariation`, as a keyword to
  preserve positional APIs; `variationName` is the unified accessor.
- Defaults follow `shortVariationName(location, columnName(target))` so labels align with summary table naming.
  `CoVariation` stores one name for the combination; children keep theirs.
- Sensitivity scheme headers inherit the names because `LatentVariation(dv|cv)` uses `variationName` for
  `latent_parameter_names`. Metadata only: variation keys in SQLite remain XML-path-based.

---

## Test infrastructure — 2026-03-30

**Decisions**
- Cleanup runs at the **start** of `runtests.jl`, not the end, so artifacts remain for inspection and are cleared
  before the next run.
- The artifacts list is kept in sync between `test/.gitignore` and the cleanup block in `runtests.jl`; both change
  when a test adds an output path.

---

## 2026-03-29 — Analysis naming decisions

**`finalPopulationCount(Monad)` placement**
Added to `src/analysis/population.jl` (not a calibration file) because it is a general analysis utility. The summary statistics in `standard_qois.jl` delegate to it.

**`meanPopulationTimeSeries` naming**
Rejected "endpointPopulationTimeSeries" (contradictory terms). Chose `meanPopulationTimeSeries` wrapping `MonadPopulationTimeSeries.mean` field.
