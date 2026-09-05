# progress.md — PCMM Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

---

## 2026-09-05 — SLURM defaults PhysiCell needs; ModelManager 0.10

### `cpus-per-task` follows `omp_num_threads`
PhysiCell's `main.cpp` calls `omp_set_num_threads(PhysiCell_settings.omp_num_threads)`, so a job
starts as many threads as its config says whatever SLURM allocated -- and SLURM allocates one CPU
unless asked. Every shipped sample config asks for 6-12. Left alone, a cluster campaign time-slices
six threads on one core and finishes several times slower than a single-threaded run would, with
100% CPU efficiency in `sacct` and nothing in any log to explain it. Found by the architecture
review of the 0.9 HPC path, not by a user, which is the point: it is silent.

The default is installed by PCMM's `initializeModelManager` wrapper, not by ModelManager, because
ModelManager cannot know where a backend keeps its thread count. It is a `Function` value -- the
per-simulation hook `setJobOptions` already supports -- reading `parallel/omp_num_threads` through
`getParameterValue`, so a *varied* thread count is honoured. It is skipped when the user has set
`cpus-per-task` themselves, and a config whose element cannot be read falls back to 1 with one
warning rather than failing the submission.

Rejected: putting a `cpus-per-task` default in ModelManager's `defaultJobOptions`. Only the backend
knows the number, and a fixed number is wrong for a varied one.

### ModelManager 0.10: a refused submission throws
`runSimulation` no longer returns a failed `SimulationProcess` when `sbatch` refuses a job (or is
not installed); it throws `ModelManager._SubmissionRefused` and `run` fails fast with the row left
at `Not Started`. `HPCTests` asserted the old shape on the no-`sbatch` path and now asserts the
exception. Nothing in PCMM's source changed for this: `postSimulationCleanup` is never reached for a
refused submission, as before.

### Housekeeping
- `requestHeaders` treats an empty `PCMM_PUBLIC_REPO_AUTH` as unset. An empty value sent
  `Authorization: token ` and GitHub answered 401 to a request that succeeds anonymously, so a shell
  exporting the variable empty broke `createProject(; clone_physicell=false)` locally.
- `src/sensitivity.jl` and `src/user_api.jl` were comment-only placeholders left from the
  modularization; deleted with their includes. The docs pages of the same names render
  ModelManager's files by filename and are unaffected.
- Version 0.5.0: the compat bound moves to ModelManager 0.10, whose `runSimulation` behaviour
  change is user-visible on a cluster.

---

## 2026-09-02 — ModelManager 0.9 migration and the release backlog

### Scope, and why the triage is recorded
Seven backlog items were handed over. **Two were already implemented**, one is a test-side
contract change rather than a source change, and one new defect surfaced from the baseline test
run. The triage is recorded here because items 1 and 4 should not be re-investigated.

| # | Item | Outcome |
|---|---|---|
| 1 | Compile error leaves a stale executable | Already done — see the 2026-08-19 entry |
| 2 | Studio `e.code` `FieldError` | Real; fixed here |
| 3 | Bump to MM 0.9 | Source parts mechanical; `rm_hpc_safe` is a test-contract change |
| 4 | PhysiCell-update docs + mid-session guard | Already done — see the 2026-08-19 entry |
| 5 | `prepareBaseFile` on an unselected folder | Real; cause is in PCMM, not PhysiCellXMLRules |
| 6 | PhysiPKPD inputs | Deferred to a to-do; needs a schema design |
| 7 | Visualization in the docs | Real gap; zero rendered figures existed |

Baseline before any work, against MM 0.9.0-dev: **614 pass, 4 fail, 6 errors**.

### Items 1 and 4 were already done
`loadCustomCode` calls `refreshPhysiCellVersion()` as its first statement
(`src/compilation.jl:29`), so the PhysiCell version is re-read before every compile decision —
which is what item 4 asked for. `best_practices.md` already carries the "Update PhysiCell between
campaigns, not during one" section. Item 1's executable-naming scheme landed in the same commit.
The residual granularity limit (the check is once per sampling, so a `Trial` spanning several
samplings can straddle two PhysiCell versions) is documented in `best_practices.md` and is not
addressed here.

### Item 3 — what MM 0.9 actually broke
Three mechanical source changes, all required before PCMM would even load:
`ModelManager = "0.8"` → `"0.9"`; `packageName` removed from `src/simulator_interface.jl` (MM
derives package identity from the module defining the simulator type); `getPackageVersion` →
`getInstalledVersion`. With those, PCMM compiles and loads cleanly.

`pcmmVersion()`'s docstring became wrong rather than broken. It says "runtime version", but
`getInstalledVersion` is deliberately the *installed* version — MM 0.9 separates installed from
loaded precisely because they diverge when the environment changes mid-session. The docstring
follows the function.

`rm_hpc_safe` changed contract: it now attempts the real removal first, stages only the residue,
returns `:removed`/`:staged`, and still throws for a missing path with `force=false`. `HPCTests.jl`
asserted the old "always stage, return `nothing`" behaviour. **This is a test change, not a source
change** — PCMM has no `rm_hpc_safe` of its own. Note that the two `.trash` assertions cannot hold
on any healthy filesystem under the new contract, because `rm` succeeds and nothing is ever staged.
The staging path is left uncovered rather than faked; simulating an unremovable file portably is not
worth the machinery.

### Item 2 — the studio error had two exception types and handled one
`quietRun` is `run(pipeline(cmd, ...))`, which throws `Base.IOError` (which has `.code`) when the
binary cannot be spawned, and `ProcessFailedException` (which has `.procs` and **no** `.code`) when
the process runs and exits non-zero. `executeStudio` built its return value as
`Base.IOError(msg, e.code)`, so the second case raised a `FieldError` from inside the error handler.

The existing test only ever passed a *nonexistent* `fake_python_path`, which takes the `IOError`
branch — so the reachable real-world path had never been exercised. That gap is why the bug
survived.

### Item 5 — the assertion was PhysiCellXMLRules being right
Reproduced: `prepareBaseFile` on an unselected (`""`) `:rulesets_collection` throws
`AssertionError: The path to the CSV file must be a file` from inside PhysiCellXMLRules, while every
other unselected location returns `nothing`.

The cause is branch order in `src/configuration.jl`: `location == :rulesets_collection` is tested
**before** the `ismissing(input_folder.basename)` guard, and an unselected folder has
`basename === missing`. So the unselected rulesets case skips the `nothing` path that every other
location takes and goes on to compute a CSV path that cannot exist.

Answering ModelManagerStudio's question directly: **no, this does not belong in
PhysiCellXMLRules.** The assertion correctly describes that package's own contract; PCMM should
never have made the call. Reordering the two branches is the whole fix.

A typed `PCMMMissingInputFile` was written for the *selected*-folder-missing-its-CSV case and then
**removed as unreachable**, by the same reasoning that rejected the ragged-column guard. `basename`
for `:rulesets_collection` is the vector `["base_rulesets.csv", "base_rulesets.xml"]`, so
`InputFolder`'s constructor already refuses a selected folder containing neither — verified by
constructing one, which fails with `ErrorException: No basename files found in folder ...`. By the
time `prepareBaseFile` runs, at least one of the two files exists, so a check for their joint
absence can never fire. It was deleted rather than shipped.

*Observation for the ModelManager side:* that `InputFolder` rejection **is** reachable by ordinary
user error — creating a rulesets folder and forgetting to put a rules file in it — and it currently
raises a bare `ErrorException`. If typed errors for GUI consumption are wanted, that is a better
candidate than anything PCMM can offer here, and it belongs in ModelManager.

### `PCMM_PUBLIC_REPO_AUTH` — bound the cascade, do not fix the token
`src/creation.jl:141` uses `haskey(ENV, ...)`, so a set-but-empty value is sent as
`Authorization: token ` and GitHub answers 401. **Decision: leave it.** The token stays a GitHub
secret rather than being stored locally, and the resulting local failure is accepted — on the
condition that the number of errors stays bounded.

It was not bounded. `PhysiCellVersionTests.jl:40` calls `createProject(...)`, which performs the
download that 401s; ten lines later, line 50 restores the original project with
`initializeModelManager(original_project_dir)`. That line never ran, so every subsequent testset
failed with "has not been initialized for a project" — one 401 became six errors across
`PhysiCellStudioTests`, `DeletionTests`, `DepsTests`, and `DocstringRefTests`.

Two of those matter beyond the noise: `PhysiCellStudioTests` is where item 2's fix has to be
verified, and `DocstringRefTests` guards the docs cross-reference rule that needs no docs build.
Both were silently not running. Fixed by wrapping the download section so the restore always
happens; the 401 now costs exactly one error, in the testset that genuinely needs the token.

### Making missing data audible
Three functions silently drop replicates whose output is gone:
`finalPopulationCount(::Monad)` (`filter!(!ismissing, ...)`), `endpointPopulationFractions`
(`continue`), and `MonadPopulationTimeSeries` (`ismissing(spts) && continue`). Pruning makes this
reachable on healthy data.

**`@info`, not `@warn`, and `maxlog=1`.** Pruning is a deliberate user action, so warning about its
consequence is scolding rather than informing; the message states that data was deleted and is
therefore not contributing. `maxlog=1` is load-bearing: calibration calls these once per monad
across thousands of particles, and without it a pruned project buries the run in identical lines.
Julia scopes `maxlog` per callsite, so each of the three sites still reports independently and names
which computation lost data.

**A ragged column is not guarded.** Considered and rejected, after going back and forth on it, so
the reasoning is worth keeping.

A cell type present in some replicates of a monad but not others cannot occur in a healthy project:
`spts.cell_count`'s keys come from the output XML's `cell_types` roster, which is shared by every
snapshot in a simulation and, since replicates share a config, by every replicate in a monad. The
tempting conclusion is that an unreachable state is exactly what one should assert, since the error
path costs nothing at runtime.

**The deciding argument is that the trust boundary has to sit somewhere, and it already sits at the
data directory.** Producing a ragged roster requires editing files under `data/`. So does renaming
`base_rulesets.csv`, or hand-editing the database, or mangling an output XML. Guarding one of those
implies the others are worth guarding too, and writing detection machinery for a state that only
deliberate tampering can produce asserts that we think it might happen accidentally. It cannot.
`best_practices.md` opens with "Do NOT manually edit files inside `inputs`" — the boundary is
already documented policy, and PCMM is entitled to rely on it.

The stale-`summary/population_time_series.csv` path was offered as a non-tampering route to the same
state, but it does not survive scrutiny: the cache lives inside a single simulation's folder, and a
simulation's config is fixed at creation, so the columns cannot drift from the output under the same
simulation ID. No demonstrable non-tampering path exists.

What remains is a comment at the aggregation site recording that the roster is assumed shared, and
why — so that a future reader who notices the two denominator conventions does not "fix" one of them.
The reasoning is here rather than in production code.

### A real zero-fill bug, found while generating the docs figures
Unlike the ragged-roster case, this one **is** reachable on healthy data, and it was silently wrong.

`plotbycelltype` does not go through `MonadPopulationTimeSeries`; it re-implements the aggregation.
It sized its count arrays by `monad_length = length(simulation_ids)` — the *unfiltered* replicate
count — then filtered `sptss` for `missing` and filled one column per replicate that survived. A
pruned replicate therefore left an all-zero column, and `mean(array, dims=2)` divided by a
denominator that included it.

Measured on a monad with one of three replicates pruned: the plotted curve came back as
`[46.7, 44.7, 44.0, 44.0]` where the mean over the two survivors is `[70.0, 67.0, 66.0, 66.0]` — a
one-third understatement, with no error and no warning. Fixed by taking the denominator from
`length(sptss)` after filtering, which also makes it agree with `MonadPopulationTimeSeries`.
`plot(::AbstractMonad)` was checked and is unaffected: it delegates to `MonadPopulationTimeSeries`,
which drops missing replicates correctly.

This is the fourth silent-skip site, and it is why the `@info` was worth adding at each of them
rather than at one shared helper — the sites do not share an implementation, so they did not share
a bug either.

### `configPath("<cell type>", "motility", "speed")` resolved into `<options>`
Reported mid-session, unrelated to the rest of this work, fixed here because it is small and
self-contained.

**A footgun rather than a correctness bug, and the distinction is worth recording.** The three-token
branch read `token2 == "motility"` and sent **every** third token through `<options>`. But
`<motility>` holds `speed`, `persistence_time` and `migration_bias` as direct children and reserves
`<options>` for `enabled`, `use_2D`, `chemotaxis` and `advanced_chemotaxis`. So
`configPath("default", "motility", "speed")` produced `.../motility/options/speed`, which is not in
the schema.

No results were ever silently wrong. Variations are written through `setSimpleContent`, which calls
`retrieveElement(...; required=true)` and therefore throws
`ArgumentError("Element not found: ... Failed at: speed")`. The element-creating `makeXMLPath` —
the one that would have quietly invented `<options><speed>` and let PhysiCell ignore it — is not in
the variation write path at all; it is used only by studio, export and configuration. What the user
actually got was a confusing failure deep in the XML layer for a spelling that reads as obviously
correct.

That is the shape of the hazard: `configPath`'s own docstring invites guessing ("Take a guess at
what you think the inputs should be"), so a natural guess must either resolve correctly or be
rejected by name — not resolve to a plausible path that fails later somewhere else.

**The fix closes the class, not the instance.** Both `<motility>`'s and `<chemotaxis>`'s tag sets are
closed, so an unrecognized third token now raises an `ArgumentError` naming the valid ones — the same
thing every other `configPath` branch does with a token it cannot honour. `advanced_chemotaxis` is
deliberately left open-ended, because its third token is a substrate name rather than a fixed tag.

The two-token spelling — `configPath("default", "speed")` — dispatches through a different branch
and was always correct. That is why this survived: the two spellings of the same parameter disagreed
with each other, and only one of them was ever used. The regression test asserts their equality
rather than a literal path, which states the invariant more sharply and costs nothing to maintain.

### Rejected — falling back to the time-series CSV for `finalPopulationCount`
Pruning degrades the analysis functions asymmetrically: `meanPopulationTimeSeries` has a
`summary/population_time_series.csv` cache that, once written, survives any prune, while
`finalPopulationCount` has no cache and always loses the data. The tempting fix is to have
`finalPopulationCount` fall back to the last row of that CSV.

**Rejected, for a reason independent of taste.** `finalPopulationCount` reads `final.xml`/`final.mat`
— `indexToFilename(:final)` returns the literal string `"final"` — whereas `PhysiCellSequence`
enumerates *only* indexed outputs (`while isfile(pathToOutputXML(folder, index))`) and never
includes `final`. The CSV's last row is therefore the last full-save interval, not the simulation's
true end. The two coincide only when total time is an exact multiple of the save interval, so the
fallback would silently return a count from an *earlier* time point, undetectably. The honest
`missing` is better.

If a cache for `finalPopulationCount` is ever wanted, the right move is to write its own summary
file at run time — same value, same snapshot — not to reinterpret a different series' endpoint.

### The `QoI` migration, done: `Vector{QoI}` builders with per-function reducers
`QoI` landed in ModelManager `main` as #43 (`d9539a5`, "Add the QoI seam") partway through this work
— it had been on the unmerged `feature/qoi-seam` branch when `HANDOFF-QoI-unification.md` was
written — so the migration became possible and was done here.

**The handoff's `Vector{QoI}` shape was obsolete, and shipping it created a gratuitous
inconsistency.** It was written against PR #45, where *every* summary statistic value was wrapped as
`Dict(q.name => value)` — so a single QoI named `"counts"` would have handed `mseDistance` a
`Dict("counts" => Dict("tumor" => ...))` and broken the comparison, and one QoI per cell type was the
only way to keep the dict flat. Merged ModelManager does not do that:

```julia
_evaluateSummary(q::QoI, monad_id) = _reduceOverMonad(q, monad_id)   # one QoI: passed through
```

A single QoI's value is unwrapped, and only a *vector* is keyed by QoI name. So one Dict-valued QoI
gives `mseDistance` exactly the flat cell-type-keyed dict it wants. The builders are therefore one
QoI each, matching `populationCountQoI` — the plural shape had shipped an asymmetry with no reason
behind it, since both are measuring the same thing.

Three things fall out of the single-QoI shape, and all of them are better:

- **`cell_types` is optional again.** One QoI discovers cell types from the simulation exactly as the
  monad-level functions do. Required-ness was a consequence of the vector shape, not of anything real.
- **Exactness is structural, not tested.** Each `reduce` *is* the corresponding monad-level
  function's aggregation step — `_averageStatDicts` for fractions, `finalPopulationCount(::Monad)`'s
  union-and-generator-mean for counts. The `==` assertions still run, but they now guard a
  transcription rather than a reimplementation.
- **One shape across the whole file**, so `populationCountQoI` no longer looks like an exception.

The cost, stated because it is the one thing the vector shape bought: sensitivity analysis needs a
`Real` from `reduce`, so a `Dict`-valued QoI cannot feed `functions=`. A vector of per-cell-type QoIs
could. Naming the one quantity wanted is a one-liner —
`QoI("tumor", sim -> finalPopulationCount(sim)["tumor"])` — and that is the documented answer.
- `_reduceOverMonad` calls `red([f(sid) for sid in sim_ids])` — a materialised vector of **every**
  replicate's value, `missing` included, unfiltered. So each `reduce` must filter `missing` itself;
  the default `mean` would return `missing` for any monad with a pruned replicate.

**Three reducers, deliberately not shared**, because the three statistics disagree with each other
(each is now its monad-level counterpart's own aggregation, so the disagreement is inherited rather
than re-encoded):

| | cell type absent from a replicate | summation |
|---|---|---|
| counts | zero-filled (`get(c, k, 0)`) | `mean` over a **generator** |
| fractions | zero-filled (`get(d, k, 0)`) | `mean` over a materialised **Vector** |
| time series | **not** zero-filled — divides by replicates having the cell type | `mean(array, dims=2)` |

Only two of the handoff's four divergences are reachable on healthy data: missing-replicate skipping
(via pruning) and summation order. Zero-fill-vs-not and `union` vs `keys(first(dicts))` both need
replicates of one monad to disagree about their cell-type roster, which means damaged output — see
the ragged-column discussion above for why that is not guarded. They are reproduced anyway, because
reproducing each function's own form is what makes the migration test `==` rather than a tolerance.

**Choosing the summation test input took two tries, and the first was wrong instructively.** It
searched 10,000 random 24-element vectors for a diverging case and found none, so the assertion
silently tested nothing. Julia's `sum` only switches to pairwise summation above a blocksize of
1024; below that, divergence comes from SIMD reassociation, which is rarer than a quick measurement
suggests **and CPU-dependent** — a vector that diverges on an ARM Mac need not diverge on CI.
`fill(0.1, 1200)` crosses the blocksize, so the difference follows from the algorithm and reproduces
anywhere: `0.09999999999999988` against `0.09999999999999788`.

**One deliberate deviation from bit-exactness.** Where *every* replicate is missing,
`meanPopulationTimeSeries` raises a `KeyError` — `MonadPopulationTimeSeries` leaves `cell_count`
empty and `mpts.cell_count[k]` then fails. The builder returns `missing`, matching the other two.
That `KeyError` is incidental behaviour rather than contract, and `missing` is what a caller can act
on.

**A test-isolation trap worth remembering.** The first draft built its fixture with
`Monad(1; n_replicates=3)` and pruned a replicate. PCMM reuses matching simulations, so that is *the
same monad* `PopulationTests` builds — which then received a replicate whose output was already gone
and failed with `FieldError: type Missing has no field cell_count`. A test that destroys output must
build a monad nothing else can match; this one is distinguished by a phase duration no other test
uses.

### ModelManager v0.9.0's `simulationCommand`: what could be folded in, and two corrections
`HANDOFF-MM-v0.9.0-simulationCommand.md` (repo root) describes replacing PCMM's `runSimulation` with
a one-line `simulationCommand`, because ModelManager takes over launching. **The core of it is
blocked:** it is written from MM PR #47, which is not merged — `main` still has `prepareHPCCommand`
and no `simulationCommand`, so the method cannot be written against anything. Neither is #46, so
`post_processor` still receives a `SimulationProcess` and the doc's correction about that does not
apply to us yet either.

Two things were foldable now, and reading the code to do them corrected the document twice.

**§8's unchecked question was the blocker, and the answer was yes.** The doc lists "whether
`prepareSimulationCommand` ever sets `env` or `dir`" as not checked. It set **both**:
`Cmd(...; env=ENV, dir=physicellDir())`. v0.9.0 refuses a `Cmd` carrying an environment, so the §3
one-liner would have failed on contact. Removing `env` is safe and is done here: a child inherits
the parent's environment regardless, including the `DYLD_LIBRARY_PATH` entry `compilation.jl` adds
for libRoadrunner, so it was a no-op locally — verified by the intracellular tests, which are what
exercise that path. It is *not* a no-op on a cluster, and that asymmetry is precisely why MM refuses
it: `Cmd.env` replaces the environment where `sbatch --export` extends it. `dir` stays; the doc
confirms MM honours it on both paths.

**§6 describes a crash that cannot happen.** It says `postSimulationCleanup`'s
`println(io, "Execution command: $(p.cmd)")` throws today when the command could not be built,
because that path yields `process === nothing`. It does not: the function opens with
`isnothing(simulation_process.process) && return`, so the line is unreachable in exactly that case.

The real v0.9.0 hazard is the inverse, and worth stating because a guard written against the
described crash would not address it. Under #47, `process === nothing` becomes the norm for
**successful** HPC simulations — the work happened on a compute node, so there is no local process
to hold. That early return would then skip the entire hook: `output.err`/`hpc.err` never cleaned up
on success, failed jobs never annotated with their command. The fix is not a `p.cmd` guard but a way
to distinguish "no process because it ran remotely" from "no process because the command could not
be built", which the current `SimulationProcess` boolean cannot express.

**Version bumped to 0.4.0 rather than 0.3.4**, per §2. The doc argues it from the HPC completion
mechanism changing under anyone pinning `"0.3"`, which is not in this branch — but this branch has
its own breaking changes (`runStudio`'s error type, `configPath` rejecting unrecognised tokens,
`plotbycelltype`'s corrected numbers), so a minor bump is right on its own terms.

Still open on the ModelManager side, and both change what PCMM eventually writes: whether
`simulationCommand` may return `nothing` to fail a single simulation (§4 — today that would abort
the whole campaign), and whether `hpc.out`/`hpc.err` survive (§5).


### ModelManager #46 chose the "Full" option, and it broke four things
`HANDOFF-MM-v0.9.0-addenda.md` lists two stray call sites for MM #46. Running the suite against
merged `main` (`f31bb89`) found **four errors**, because #46 is not a couple of call sites — it is
the decision `HANDOFF-QoI-unification.md` §5 framed as a choice between "granularity only" and
"Full", and ModelManager took Full: *every* measurement function receives a `Simulation`.

```
MethodError: no method matching endpointPopulationCounts(::Simulation)
MethodError: no method matching gs_fn(::Simulation)
UndefVarError: `_asSummaryStatistic` not defined in `ModelManager`
```

So PCMM's three monad-level summary statistics are no longer valid `summary_statistic` arguments at
all. That is a role change, not a signature tweak, and it makes the `Vector{QoI}` builders added
earlier in this branch **load-bearing rather than additive** — they are the migration path. The
monad-level functions stay, as monad-level analysis; the docs now say which is which.

**The failure mode MM guards is worth knowing.** `_validateSummaryStatistic` warns when a function
does not declare `::Simulation`, because an old monad-level statistic that is *untyped* will now
return a different number without erroring, and `mseDistance` will not catch it — on a key mismatch
it warns once and computes anyway, treating absent keys as zero. PCMM's functions are annotated
`::Int`, so they failed loudly instead. Every measurement function in PCMM's tests and docs is now
annotated `::Simulation` for the same reason: the annotation is the only signal that distinguishes
the two contracts.

**One of the four errors was mine, and it was a mistake I had already named.** The equality test
reached into `ModelManager._asSummaryStatistic`, which #46 renamed to `_validateSummaryStatistic`.
I had argued against pinning ModelManager's generation-file layout in a PCMM test two commits
earlier and then pinned an internal function in the next one. It now evaluates each QoI through its
own documented `compute`/`reduce`, and the flat-versus-nested dict shape is left as ModelManager's
contract to keep. The naming check still holds: the builders' QoI names are compared against the
monad-level function's keys, so a single QoI named `"counts"` would still be caught.

**`populationCountQoI` survived by luck rather than design.** Its closure took a `SimulationProcess`
and called `simulationID` on it; #46 hands it a `Simulation` and MM happens to have added
`simulationID(::Simulation)`. Renamed the parameter and corrected the file header, which still
claimed these builders are "keyed by `SimulationProcess`" — what actually distinguishes them from
the calibration statistics is where the value goes, not what they receive.

**Annotating that closure then failed six tests, which was the useful part.** `PostProcessorQoITests`
constructs a `SimulationProcess` by hand and calls the builder with it. While the closure was
untyped that worked, so the test went on passing against a contract ModelManager had already
replaced — the silent divergence MM's warning exists for, sitting in our own suite. The test now
passes a `Simulation`, which is what `run` actually hands a `post_processor`. Worth generalising: an
untyped measurement function is not merely unidiomatic here, it is what lets a stale contract keep
looking healthy.


### ModelManager #47 merged: `runSimulation` becomes `simulationCommand`
`HANDOFF-MM-v0.9.0-START-HERE.md` is the wrap-up over the other three and wins where they disagree.
Most of its checklist was already done on this branch — `env=ENV` deleted, the #46 call sites fixed,
compat at `"0.9"`, version at `0.4.0` — because it was written against PCMM at `bc60cdca6`. Three
items remained, all now done against MM at `295f749` (v0.9.0).

**`simulationCommand` replaces `runSimulation`.** PCMM's implementation is one line returning
`prepareSimulationCommand(spec.simulation)`; ModelManager owns the local/HPC branch, the output
redirection, the sbatch wrapping, waiting for completion, and constructing the `SimulationProcess`.
Deleted with it: the `runSimulation` method, its import, the `prepareHPCCommand` call, and PCMM's own
`hpc.out`/`hpc.err` redirection — ModelManager writes those files now, and two writers would race.
`prepareSimulationCommand`'s `mkpath` of the `output` subfolder stays: ModelManager creates the trial
folder, not that subdirectory.

**Both `.process` reads became `.cmd` reads.** `process === nothing` used to mean one thing, "no
command could be built". Under v0.9.0 it also means "ran as a SLURM job", because the work happened
on a compute node and there is no local process object. `isnothing(cmd)` is now exactly what
`isnothing(process)` used to be, so:

- `postSimulationCleanup`'s early return: had it kept testing `process`, it would have fired for
  *every* simulation on a cluster — no pruning for an entire campaign, `output.err` never cleaned or
  annotated, and nothing reported. This was the addenda doc's most valuable find precisely because
  it is silent.
- the failure annotation: `p.cmd` would have thrown on any failed simulation with `run_on_hpc` set,
  inside a hook `run()` treats as fail-fast, so one failed job aborted the campaign. Reading
  `simulation_process.cmd` is also *better* output — PhysiCell's own command line on both paths,
  where `p.cmd` on HPC printed the whole `sbatch` wrapper.

**`HPCTests` lost three assertions and gained better ones.** It was testing `prepareHPCCommand`
(deleted), `--wrap=` and `--wait` (that flag is gone — the sentinel file replaced the poll), and it
built a four-argument `SimulationProcess`, which now defaults `cmd` to `nothing` and would therefore
correctly skip the cleanup the test asserts. What is left is what PCMM is actually responsible for:
that `simulationCommand` returns the command, that the `Cmd` carries no environment and does carry
`dir`, that a failed submission yields no process but a non-`nothing` `cmd`, and that `setJobOptions`
reaches the globals — including the callable form resolved per simulation. Two of the dropped
assertions were `@assert` rather than `@test`, so they had never been able to fail the suite.


### `populationCountQoI` returns a `QoI` now, and the name stopped lying
`HANDOFF-QoI-unification.md` §3d calls this "the hardest of the four, and possibly should not migrate
at all", having corrected an earlier draft that thought it was the easiest. Two properties had no
`QoI` equivalent: a runtime-discovered number of sink columns, and returning `nothing` to skip a
simulation whose output could not be read.

**Both were closed by ModelManager #43, so §3d is stale.** `_asPostProcessor` now expands a
`NamedTuple` or `AbstractDict` return into one sink entry per key — un-prefixed, so the existing
`count_<cell_type>` keys pass straight through — drops an entry whose `compute` returned
`nothing`/`missing`, and returns `nothing` when every entry was dropped, which is exactly the old
"skip this simulation".

So the conversion is wrapping the existing closure in `QoI("population_count", …)`. Note what that
avoids: the handoff's other option was renaming the function, because it was named `…QoI` and did not
return one. Making it return one fixes the name instead, with no breaking rename — and the name had
become actively misleading now that `endpointPopulationCountQoI`, which does return QoIs, sits
beside it.

One QoI covers every cell type rather than one QoI each, and that asymmetry with the
`standard_qois.jl` builders is deliberate: those name their cell types at construction because they
must, and this one cannot, because it reads them from the simulation's own output. It works because
the sink never calls `reduce`.

The tests probed the returned closure by calling it directly, so they now go through `compute`.


### ModelManager 0.9.1: a keyed measurement reaches sensitivity analysis
Stacked on the branch above. Written first against the *premise* that ModelManager would spread a
`Dict`-valued measurement (issue #48), then rewritten against what actually shipped in 0.9.1
(ModelManager PRs #49 and #50).

**The premise version was deliberately thin, and correctly so.** Only two statements survived every
answer to #48's three open questions — key-set consistency, naming, and whether vector *values*
spread — so only those were written: the `[compat]` bound and an inverted admonition scoped to the
two endpoint builders. The bound is `"0.9.1"`, not `"0.9"`, checked against `Pkg.Types.semver_spec`:
`"0.9"` resolves to `[0.9.0, 0.10.0)` and would let a project resolve 0.9.0 while these docs promise
behaviour it does not have. No version bump — 0.4.0 is not yet tagged, so this folds into it. Surveying what else *might* be written turned up mostly corrections to the
base branch, which landed there rather than here.

**What 0.9.1 settled, and what each answer bought:**

- *Naming* is `"<qoi name>.<key>"`, and `GSASampling.results` is keyed by that label rather than by
  the measurement object. So the retrieval example and the test held back for want of an answer are
  both writable: `endpointPopulationCountQoI()` yields `endpoint_population_count.<cell_type>`.
  `gsaLabels` lists them; it is public in ModelManager but not exported, and PCMM's
  `@reexport using ModelManager` only forwards exports, so it needs the `ModelManager.` prefix.
- *Vectors are not spread by index* — equal length is not equal meaning. That makes
  `meanPopulationTimeSeriesQoI` definitively GSA-incompatible: its `Dict` clears the key check and
  is then refused per label, since a `Vector` is not a `Real`. The PRD open question became a
  statement.
- *Key sets must match across the design*, with no fill. PCMM satisfies this by construction, for a
  reason worth recording because the opposite choice would have been easy to make: `populationCount`
  keys off `cellTypeToNameDict` of the **initial** snapshot — the roster the model *defines* — not
  the types observed alive. A cell type driven extinct by some parameter set therefore still reports
  zero rather than dropping its key. Had it keyed off observed cells, every GSA sweep that kills a
  population would hit the refusal.

**Two breaking changes #48 never mentioned, both of which land here.**

- *Sink columns are namespaced.* A spread column is `"<qoi name>.<key>"`, so `populationCountQoI`'s
  became `population_count.count_<cell_type>` — double-named. The `count_` prefix existed only
  because the old sink was one flat namespace and a prefix was the sole thing keeping two QoIs'
  "tumor" apart; 0.9.1 does that job. So the prefix is gone and the key is the bare cell type.
  This renames a stored column either way, which is why it rides along with the compat bump rather
  than waiting: one break, not two.

  **No `up.jl` milestone**, and the CLAUDE.md rule about reflecting database breaks there does not
  reach this: `postprocessing.db` is ModelManager's sink, not PCMM's schema — neither `up.jl` nor
  `database.jl` mentions it. A migration also could not be written correctly. Renaming
  `count_<x>` to `population_count.<x>` would have to guess which columns this builder wrote, and
  a user's own `QoI("count_foo", …)` is indistinguishable from them. ModelManager declined a
  milestone for the identical change on its side for the same reason. What actually happens to a
  v0.3.3 project is a split rather than a loss: the sink adds columns on demand, so old rows keep
  the old columns and new rows fill the new ones. `post_processing.md` says so, since the symptom
  otherwise looks like data going missing.
- *An anonymous `post_processor` that stores anything is refused*, since its derived `anon_9` would
  prefix every column and change between sessions. Two examples in `post_processing.md` — including
  the page's first — were exactly that shape and now throw; both are wrapped in a named `QoI`. The
  `function (sim) … return nothing end` examples are untouched: the guard sits after the
  `isnothing` skip, so a callback that stores nothing has nothing to name.

**Two fixes PCMM inherits without changing a line.** ModelManager's GSA plot recipes threw a
`MethodError` on a `QoI` — `_gsaFunctionLabel` had only a `::Function` method — and it went unnoticed
because the sole unguarded call was `sort(...; by=…)`, which never invokes `by` on a one-element
vector. So a PCMM user plotting a single-measurement analysis was fine and a two-measurement one
threw. PCMM defines no GSA recipes of its own, so this arrives purely by re-export.

**No PCMM impact from ModelManager #50**, the stacked refactor that merged QoI evaluation into
`qoi.jl`. Every name it moves is underscore-prefixed, and PCMM calls no ModelManager internal — the
only `ModelManager._` string in this repo is the comment in `CalibrationTests.jl` recording the #46
rename that broke a test here, which is deliberately prose and not a call. PCMM gets one silent fix
from it: sensitivity analysis now shares calibration's `_reduceOverMonad`, and so inherits its
empty-monad guard and batch loading instead of an N+1 query with neither.


### Open questions
- **PhysiPKPD inputs (item 6).** Deferred deliberately. Needs a design brief covering how dosing
  schedules are represented, where they live under `inputs/`, and how they are varied.
- **ModelManager is still moving.** `main` advanced 13 commits *during* this work and broke two
  calibration tests mid-review (`runCalibration`'s argument order, and generations becoming folders).
  More is expected before the release this branch is preparing, so the drift has to be re-checked
  rather than assumed settled — the suite is the only thing that catches it, and it catches only
  what it exercises.

---

## 2026-08-19 — Name the executable for the PhysiCell version; drop `physicell_commit_hash.txt`; check that version at every compile

### The bug
`loadCustomCode` decided whether to recompile from two records that could disagree with each
other. `physicell_commit_hash.txt` held the PhysiCell version, and `writePhysiCellCommitHash`
**wrote it before `make` ran**; the executable was always named `project`, so a compile error
left the old binary in place next to a file now claiming the new version. The next run read a
matching hash, found `project`, concluded nothing had changed, and silently ran a binary built
from different PhysiCell source.

### The fix — one record instead of two
The executable is named `project_<physicell-version>`, so its existence *is* the record that a
build for that version finished. `physicell_commit_hash.txt` is gone. There is nothing left to
fall out of step with: a failed compilation writes no executable, so the next run recompiles.

`unreproduciblePhysiCellVersion()` replaces the old function's dirty/download branches. Those
suffixes mean the source can change without the recorded version changing, so the name proves
nothing and the code recompiles every run — the previous behaviour, now stated as its own
predicate rather than a fall-through of the hash comparison.

### `macros.txt` had the same defect
Found while restructuring, and the same failure mode, so it is fixed in the same commit.
`addMacrosIfNeeded` appended to `macros.txt` *before* compiling. A macro change sets both
`recompile` and `clean` — the macros are part of every translation unit, so object files
compiled without them must be discarded. If that compilation failed, `macros.txt` already
listed the new macro, so the retry saw no macro change and skipped the `make clean` it needed.

Now `neededMacros(S)` computes the list in memory, `compilerFlags` compares it against the file
to decide `recompile`/`clean`, and `writeMacrosFile` runs only after `make` succeeds. Two bugs
fell out of the restructure rather than being hunted:
- `addMacrosIfNeeded` chained the checks with `||`, so PhysiECM being newly needed
  short-circuited the RoadRunner check entirely. A project needing both got one macro, failed
  to compile, and only picked up the second on the next attempt. The comment above the line
  ("julia's `|=` operator seems to evaluate the RHS even if the LHS is already true, but I don't
  trust that will always be the case") shows the `||` rewrite defeated its own intent.
- `addPhysiECMIfNeeded` called `addMacro(M, ...)` with an undefined `M` — an `UndefVarError`
  waiting on any project that enables `ecm_setup` in config without supplying an `ic_ecm` file.

### Decisions — the naming change
- **Old executables are kept, not pruned.** A custom code folder can accumulate one binary per
  PhysiCell version used there. That is deliberate: the name is now a cache key, so switching
  PhysiCell versions back and forth no longer forces a rebuild. `clearSimulatorArtifacts`
  (reached by `resetDatabase`) deletes all of them, which is the documented way to reclaim the
  space. Pruning on each successful compile was considered and rejected — it would delete a
  binary another session on a shared filesystem may be about to launch.
- **Legacy artifacts are cleaned up in place, not via an `up.jl` milestone.** `project` and
  `physicell_commit_hash.txt` are removed by `removeLegacyBuildArtifacts` after the first
  successful compile under the new naming. A milestone would drag the whole
  `continueMilestoneUpgrade` prompt in to delete two files, and the upgrade is self-healing
  anyway: no hash-named executable exists, so the first run recompiles regardless.
- **Executables live in a `pcmm_build/` subfolder, so clearing them needs no name match at all.**
  Two earlier rounds tried to make a prefix safe — first `project*`, then `project_` — and review
  rejected both: a glob that deletes can always swallow a file the user keeps for their own
  records, and `project_notes.md` is genuinely indistinguishable from `project_<hash>`. A folder
  PCMM owns ends the argument. `clearSimulatorArtifacts` removes that directory outright and
  matches every remaining name exactly (`isCompilationArtifact`), so `projectile.cpp` and
  `project_notes.md` are both safe. `project`, `project.exe`, and `physicell_commit_hash.txt` stay
  in the exact list, matched on either platform, so a data folder built elsewhere is still cleaned.
  `createDefaultGitIgnore` ignores `pcmm_build/` rather than `project*`.
- **A build that does not finish takes the executable it was replacing with it** (`abandonBuild`).
  Raised in review: is it possible to reach the failure paths with an executable for the current
  version still present? Yes — the recompile may have been triggered by changed macros, a
  `force_recompile`, or a dirty PhysiCell working tree, none of which imply the file is absent.
  In the `force_recompile` case the hole was live: the next run without the flag would find that
  executable, unchanged macros, and a clean repository, and reuse a binary the user had explicitly
  asked to replace. Deleting it on failure makes "an executable exists" mean "a build for this
  version finished" in the failure paths too.
  Rejected: deleting it up front, before `make`. That would also cover an abnormal termination
  mid-compile, which `abandonBuild` does not, but it removes the binary for the whole duration of
  every rebuild, where the `mv` at the end is an atomic swap. On a shared filesystem a concurrent
  session would fail to launch simulations for minutes rather than for an instant. Losing the
  binary to a `kill -9` is the residual, and it fails loudly on the next launch rather than
  silently returning wrong results.
- **The version string is sanitized before it becomes a file name.** It is either a git hash or
  the first line of `VERSION.txt` from whatever PhysiCell the user downloaded; the latter is not
  guaranteed tame. `sanitizedForFilename` replaces anything outside `[A-Za-z0-9._-]` with `_`.
- **`make` is invoked with `PROGRAM_NAME` set to the final name.** It used to build
  `project_ccid_<id>` and rename on the way out; the temp directory already carries a
  `randstring(10)` suffix, so the intermediate name bought nothing.
- **`make` exiting 0 without producing the executable is now a failure return**, not an
  unhandled `mv` error.

### Testing the naming change
`test/test-scripts/CompilationTests.jl`, run right after `RunnerTests.jl` so a real build
exists to inspect. It asserts the naming and sanitizing, the `isCompilationArtifact`
classification, that `removeLegacyBuildArtifacts` deletes the old pair and leaves `main.cpp`
alone, and that a real build leaves a hash-named executable, a `macros.txt`, and no legacy
files. The regression is driven end to end: with a real working executable in place, swap in a
`Makefile` whose only recipe is `@exit 1`, plant the state the old code was fooled by (a stale
`project` plus a `physicell_commit_hash.txt` naming the current version), and check that
`loadCustomCode` returns `false` and that the executable it was replacing is gone rather than
left to be trusted. The following call, without `force_recompile`, must then rebuild — which is
the naming regression itself, since v0.3.3 would have returned `true` off the leftover pair, and
the executable can only reappear if a compilation actually ran. That costs one real build; an
earlier version of the test moved the executable aside to avoid it, which left the failure path
with nothing to lose and missed the hole review found.

### What this does not fix
The name carries no OS, architecture, or compiler-flag component, so copying a `data/` folder
to a different platform still reuses an unrunnable binary. Called out in
`docs/src/man/known_limitations.md` with the `force_recompile=true` workaround. This was the
known limitation going in, not a regression.

### Bearing on the deferred `-march` work (see 2026-08-05)
That entry's analysis stands, but two of its statements are now out of date: the executable is
no longer "a single `project`" that gets overwritten, and the cache key is no longer empty — it
is the PhysiCell version. It still contains no ISA or march component, which is the part that
matters there. The mechanism that entry called for now exists: making `native` safe is a matter
of adding a march/ISA component to `executableName`, not of inventing artifact keying.

### Second half: the PhysiCell version was only ever checked at initialization
Flagged separately by the user as "guard against upgrading to new PhysiCell version mid-session.
This might already be done?" It was not.

`simulator().current_version_id` is assigned in exactly one place — `src/up.jl`, during database
initialization — and never revisited. `physiCellCommitHash()` reads the database row for that
cached id, so it cannot see the working tree. Measured directly: edit `PhysiCell/Makefile`
mid-session and `gitDirectoryIsClean()` returns `false` while `physiCellCommitHash()` still
returns the clean hash, `unreproduciblePhysiCellVersion()` returns `false`, and
`loadCustomCode` returns `true` without compiling.

Reusing a stale binary is the mild half. The damaging half: any recompile forced for another
reason (macro change, `force_recompile=true`) builds the *new* source while naming the
executable and writing `physicell_version_id` for the *old* version. The database then asserts a
clean commit for a binary that is not that commit — precisely what the `-dirty` suffix exists to
prevent, defeated by checking only at startup.

`refreshPhysiCellVersion()` now runs as the first statement of `loadCustomCode`. Everything else
follows from the naming change above, which is why the two belong in one PR:
- HEAD moved → a different `commit_hash` row → a different `executableName()` → `executableExists`
  is false → recompile.
- Went dirty → the hash gains `-dirty` → `unreproduciblePhysiCellVersion()` → recompile.
- ModelManager records each simulation from `currentSimulatorVersionID()`, which reads the same
  field, and setup always precedes recording, so the recorded version is corrected too.

Under the old naming this would have needed its own comparison against the hash file. With the
hash in the executable name, re-resolving the version *is* the guard.

### Decisions — the guard
- **`loadCustomCode`, not per simulation.** It is the single funnel for compilation, runs once per
  sampling, and precedes recording. Refreshing per simulation would let one sampling straddle two
  PhysiCell versions. The cost is one `git status --porcelain` per sampling: measured 30 ms for
  `resolvePhysiCellVersionID()` on the steady-state path, 20 ms of it the `git status`.
- **Resolve quietly, report in one line.** `resolvePhysiCellVersionID` and `gitDirectoryIsClean`
  gained `verbose::Bool=true` kwargs; the refresh passes `verbose=false` and prints
  `PhysiCell version changed. Now using <info>.` only when the id actually moved. Without this, a
  user with a permanently dirty PhysiCell would get the multi-line dirty warning plus a
  modified-file listing once per sampling instead of once per session. The `-dirty` suffix in the
  one-line message plus `unreproduciblePhysiCellVersion`'s own notice carries the actionable part;
  the full listing still appears at initialization.
- **A failed compile after a version change is safe.** The refreshed id is in place but
  `setupSampling` returns false and the run aborts, so no simulation is recorded against it.
- **No opt-out.** Recording the wrong commit hash is corruption, not a preference, so the
  version-changed path is unconditional. The dirty case is not configurable either — see the
  `strict_check` note below for why that off-switch was deleted rather than wired up.

### `strict_check` deleted — it was dead and always had been
`PhysiCellSimulator.strict_check` was documented on an **exported** type as "If `true`, require a
clean git directory to skip recompile", was set to `true` by the constructor, and was read nowhere.
`git log -S` shows it entered at the 2026-04-08 modularization as a rename of
`strict_physicell_check` from the old globals struct ("...requires a clean git folder (in
particular, not downloaded) to skip recompile"), which was itself never read either. Not a
refactor casualty — declared and never wired, under both names, while its docstring rendered on
the site as a promise the code did not keep.

The behaviour it described already exists unconditionally in `unreproduciblePhysiCellVersion()`,
covering both the dirty and the downloaded case, so the field was never missing behaviour — it was
a missing *off-switch*, for someone carrying a permanent local patch on PhysiCell who does not want
a full rebuild every run.

Deleted rather than wired up. Setting it to `false` would mean recording a clean commit hash for a
tree that is not that commit, in the package whose job is reproducible bookkeeping, and PCMM
already prints the better answer when it sees a dirty repository ("make a new commit or stash
changes") — which yields a real hash that caches like any other version. The rejected alternative
was to keep the hatch under a name stating its consequence (`recompile_if_unreproducible`, with a
`@compat public` setter, since a knob with no API is the incoherence the 2026-08-05 entry flagged
about `setMarchFlag`).

Technically breaking for anyone constructing `PhysiCellSimulator` with nine positional arguments.
Nothing in either repo does — every construction site is the no-argument constructor — and the
package is pre-1.0.

### Testing the guard
Added to `CompilationTests.jl`. The wiring is pinned by setting `current_version_id` to the `-1`
sentinel and calling `loadCustomCode`: with the refresh in place the id is corrected and the call
returns `true`; without it, the first read of the version cannot resolve an executable name at
all, so the test fails loudly. The semantics are pinned by editing a tracked PhysiCell file
without re-initializing and asserting that the id is unchanged until `refreshPhysiCellVersion()`
runs, then that the hash gains `-dirty`, `unreproduciblePhysiCellVersion()` flips, and no
executable exists for the dirty version. Restored in `finally`.

`PhysiCellVersionTests.jl` already dirties the repository exactly this way — it just
re-initializes afterwards, which is why the gap was never caught.

Not covered: the checked-out-a-different-commit case, which needs a second commit available in
`test/PhysiCell`. It drives the identical code path as the dirty case.

---

## 2026-08-05 — `-march` selection: investigation only, implementation deferred

### Motivation
`PhysiCellSimulator()` picks `march_flag` as `isRunningOnHPC() ? "x86-64" : "native"`
(`src/physicell_simulator.jl:46`). `isRunningOnHPC()` is `which sbatch` (ModelManager
`src/hpc.jl:19`), so the question was whether a better check exists. Investigated; a design brief
was written and then deliberately shelved. Nothing implemented.

### The predicate is about scheduler presence, not architecture
`-march` is not about "am I on an HPC" and not about a login/compute split at compile time. The
compiled executable is persisted to `inputs/custom_codes/<folder>/` and reused on any later session
unless the macros or the PhysiCell commit hash changed. **The cache key contains no ISA or march
component.** (Updated 2026-08-19: the executable is now named `project_<physicell-version>` rather
than a single overwritten `project`, so the PhysiCell version *is* the cache key — still with no ISA
or march component. Line references in this entry predate that change.) So the
real question is "will this on-disk binary ever be executed by a machine that did not build it,"
which cannot be answered from the current session:

- Compile on a login node with `useHPC(false)` for a local test → `native` bakes in that node's ISA
  → a later session flips `useHPC(true)` and `sbatch` ships the *same cached binary* to compute nodes.
- Compile inside an allocation on compute node A → `native` is node A's ISA → the next array job
  lands on older node B.

Presence of a batch scheduler is a good proxy for that, because a scheduler is precisely the thing
that hands a binary to a different machine. On a laptop the binary only ever runs on that laptop.

Compilation is a plain `run(...)` from the Julia process (`src/compilation.jl:52`) and is never
submitted through a scheduler — it always happens on whatever node Julia occupies. That does not make
`native` safe on a cluster; it makes the binary arbitrarily tied to whichever node happened to run
Julia.

### Three distinct failure classes — only two are `-march`-addressable
| Case | build → run | fails at | fixable by `-march`? |
|---|---|---|---|
| mixed µarch, one ISA | Haswell → Ivy Bridge | run (SIGILL) | yes — already fixed by the `x86-64` default |
| uniform non-x86 cluster | aarch64 → aarch64 | compile (`unknown value 'x86-64' for -march`) | yes — needs an arch-aware fallback |
| mixed-ISA cluster | x86 login → aarch64 nodes | run (`ENOEXEC`, "Exec format error") | **no** |

The third row is real hardware (Ookami pairs x86 login nodes with A64FX compute nodes; Grace-Hopper
partitions bolted onto x86 clusters are appearing). No `-march` value helps — an x86-64 ELF cannot
exec on aarch64 regardless of ISA baseline. It is a cross-compilation problem, and PCMM's
compile-then-submit structure cannot support it without an `sbatch`'d compile step on the target
partition plus an ISA-keyed executable cache. **Recommendation: document as unsupported** ("run Julia
on a node with the same architecture as your compute partition"). The failure is immediate and
legible at job launch, not silent. Slurm does expose `Arch=` per node in `scontrol show nodes` if a
warning is ever wanted, but it is not worth the parsing.

### Findings that constrain any future design
- **There is no public API for this.** `setMarchFlag` (`src/compilation.jl:415`) is not exported and
  has no `@compat public`; the test suite reaches for it as
  `PhysiCellModelManager.setMarchFlag` (`test/test-scripts/ClassesTests.jl:63`). A user whose
  auto-detection guesses wrong has no supported recourse. This, not ergonomics, is the gap a
  `PCMM_MARCH` env var closes.
- **`run_on_hpc` and the march flag are already decoupled.** `isRunningOnHPC()` has exactly one
  caller in either repo — the march default. `mm_globals().run_on_hpc` defaults to `false`
  (ModelManager `globals.jl:52`) and is mutated only by `useHPC`, so `useHPC(false)` cannot affect
  compilation. Using the global *would* be wrong, but for a subtler reason than "the user might turn
  it off": its value at compile time does not constrain its value at run time, and the cached binary
  spans both.
- ModelManager's `globals.jl:24` still documents `run_on_hpc` as "`true` when `sbatch` is available
  (auto-detected)". Stale — nothing wires the probe to it. ModelManager fix, different repo.
- **`x86-64-v3` is exactly the Haswell feature level** (AVX2/FMA/BMI2). It is therefore the *risky*
  choice on the cluster whose pre-Haswell nodes originally broke `native`. Never make it a default;
  opt-in only after checking the oldest node in the target partition.
- **`-m64` is hardcoded** in `cflags` (`src/compilation.jl:95`) and is x86-only. Fixing `-march` alone
  will not make an ARM Linux cluster compile — the two must move together.
- An env var override does not solve the arch problem (a dotfile follows you onto any machine). The
  mitigation is to **validate the resolved flag against the actual compiler** before `make` runs —
  `g++ -march=<flag> -fsyntax-only -x c++ /dev/null`, nonzero exit means unusable here. One cheap
  subprocess that catches a stale dotfile, a typo, *and* an auto-detected `x86-64` on an ARM cluster,
  turning an error buried in `compilation.err` into an actionable message.

### Deferred design (PCMM side, ~70 lines src / ~50 test / ~15 docs, risk low–medium)
1. `_defaultMarchFlag()` — `get(ENV, "PCMM_MARCH")` then fall back to the probe.
2. `_mayRunOnOtherHosts()` — ``isRunningOnHPC() || shellCommandExists(`qsub`) || shellCommandExists(`bsub`)``
   (Slurm / PBS-Torque-SGE / LSF). Keep it internal and ~6 lines: it is **deliberately disposable
   scaffolding**, to be replaced by `scheduler() !== :none` once ModelManager grows a real scheduler
   abstraction. Say so in a source comment so it is not preserved out of misplaced respect.
3. `_marchFlagSupported(compiler, flag)` — validate at first compile (not `__init__`, where the
   compiler may not be configured), memoized per `(compiler, flag)`; skip entirely when
   `shellCommandExists(compiler)` is false so `make` keeps producing the error it always has.
4. Promote `setMarchFlag` with `@compat public` — an env var for a knob whose function form is
   internal is incoherent, and public status is what lets new docstrings `@ref` it.
5. Docs: short section in `docs/src/man/installation.md` (there is no central env-var page —
   `PCMM_PYTHON_PATH` is documented only in `physicell_studio.md` and `PHYSICELL_CPP` nowhere), plus
   two lines in `known_limitations.md` for the mixed-ISA case.

Behavioral break to call out in a release note: PBS/LSF/SGE users move from `native` to `x86-64` —
correct, but slower for anyone on a homogeneous non-Slurm cluster who was getting away with `native`.
`PCMM_MARCH=native` restores it.

### Rejected
- **Widening `isRunningOnHPC` itself.** That name honestly means "Slurm is available," and
  `useHPC`/`prepareHPCCommand` are Slurm-specific; widening it would be wrong the moment anything
  else consumes it. The march decision wants its own predicate.
- **An Lmod / `MODULESHOME` check.** Proposed early, then dropped: it is a proxy for a proxy (Lmod ⇒
  cluster ⇒ binary may relocate), it adds a false positive for Homebrew-Lmod workstations, and any
  cluster with Lmod has a scheduler the three command probes already catch.
- **Parsing `scontrol show nodes` to detect a genuinely heterogeneous partition.** Fragile, slow at
  load, needs permissions.
- **Compiling inside the job so `native` is safe and optimal.** Compilation already happens wherever
  Julia is; the missing piece is that the cached executable is not keyed on the ISA it was built for.
  Making `native` safe means keying the artifact on the march flag / detected ISA instead of
  overwriting a single `project`. The `rand_suffix` temp dir already anticipates concurrent
  compilation from multiple nodes, so the groundwork is half there — but this is a real feature, and
  `x86-64-v3` gets most of the performance for a fraction of the work.
  *(2026-08-19: the artifact is now keyed, on the PhysiCell version. Adding a march/ISA component to
  `executableName` is the remaining step.)*

### Open questions
- Why deferred: the `x86-64` default is correct for the common case and has held up across all three
  major OSes in the field. The live gap is only the silent `native` on non-Slurm sites.
- **Multi-scheduler submission is a separate repo and a separate brief.** `prepareHPCCommand`
  (ModelManager `src/runner.jl:79`) builds `sbatch --wrap="<command>"`, and **PBS has no `--wrap`** —
  `qsub` requires an actual job script, so a per-simulation script file must be written to disk. That
  is structural, not a flag rename. On top of it: `push!(flags, "--$k=$v")` (`runner.jl:96`) is Slurm
  long-option syntax applied to every user option; `--output`/`--error`/`--chdir`/`--wait` map to
  `-o`/`-e`/`-d`/`-W block=true` (PBS) and `-o`/`-e`/`-cwd`/`-K` (LSF); `defaultJobOptions()`'s
  `"job-name"` and `"mem"` are Slurm key names. Needs a semantic job-options layer (portable keys →
  per-scheduler rendering), a rename of `sbatch_options`, and a deprecation path, since
  `defaultJobOptions` and `prepareHPCCommand` are both `@compat public`.
- Ordering: the PCMM march branch is self-contained (needs only exported `isRunningOnHPC` and
  already-public `ModelManager.shellCommandExists`), so it can land first with no compat bound bump —
  at the cost of ~6 lines of throwaway. Doing ModelManager first yields no throwaway but leaves the
  non-Slurm SIGILL live.

---

## 2026-08-03 — Stop `__init__` from auto-initializing during precompilation

### Motivation
The logo + status banner was being printed repeatedly — apparently once per package in the environment that did `using PhysiCellModelManager`.

### The premise was wrong, and that determined the fix
Julia runs a module's `__init__` **at most once per process per load** (`run_module_init` is reached only from the cache-deserialization path in `loading.jl`; `canstart_loading` short-circuits an already-loaded module). Verified: loading three separate packages that each `using` a banner-printing base package ran `__init__` exactly once.

The repeats came from **separate processes** — specifically the precompilation subprocess of each *dependent* package. Only the package being precompiled has its own `__init__` skipped; its dependencies are loaded normally, so PCMM's `__init__` runs in every such worker. Julia 1.12 hands the worker the same pipe for stdout and stderr and surfaces it, live when a single package was requested and otherwise replayed boxed under `┌ <DependentPkg>` — which is why it looked like the *other* package was printing.

### Rejected: guarding on `mm_globals_ref` being non-`nothing`
The first attempt was `!isnothing(ModelManager.mm_globals_ref[]) && isInitialized() && return`. It cannot work: `mm_globals_ref` is a `const Ref` initialized to `nothing` and PCMM's own `__init__` is its only assignment site, so in a fresh precompile worker it is always `nothing` and the guard falls through. Measured directly — every reproduced duplicate had `ref == nothing` on entry. It was also doubly narrow, since it additionally required `isInitialized()`, which is false in a worker whose working directory holds no project (the common case).

Worse, keying on `mm_globals_ref` alone introduced a regression. `ModelManagerGlobals` holds exactly one `simulator`, and the ref is shared by every ModelManager backend. If another backend had already initialized, PCMM's `__init__` would return **before** registering its own `PhysiCellSimulator`, leaving PCMM running against a foreign one: `simulator().compiler` throws `FieldError`, and `runSimulation`/`setupMonad` dispatch to the other backend. On the base commit PCMM's unconditional assignment always won, so the guard only flipped *which* package silently lost.

### Chosen: gate on `jl_generating_output`, and check the simulator type
Two helpers in `src/PhysiCellModelManager.jl`:
- `_generatingOutput()` — true exactly while a cache file or sysimage is being written. Verified true in the worker, false in a real session. `@static if isdefined(Base, :generating_output)` prefers Base's wrapper, falling back to `ccall(:jl_generating_output, Cint, ()) == 1`. Reviewer (Copilot) suggested that as a stability win over the raw `ccall`; that premise is wrong — `Base.generating_output` is neither exported nor `public` (`ispublic` false on 1.12.6), and called with no argument its body *is* that same `ccall` (`base/runtime_internals.jl`). Adopted anyway, on the weaker but real ground that Base then owns the mapping to the C entry point. Written `@static` rather than as a runtime ternary, matching `DocstringRefTests.jl`'s `@static if isdefined(Base, :ispublic)`. Behaviour re-verified after the swap: a pure `Pkg.precompile()` from inside a project directory stayed silent and left `data/` empty.
- `_pcmmGlobalsRegistered()` — `!isnothing(globals) && globals.simulator isa PhysiCellSimulator && globals.initialized`. The simulator-type conjunct is what closes the multi-backend hole above.

Ordering matters: the globals are registered *before* the `_generatingOutput()` return, because registering them is pure in-memory work and keeps `mm_globals()` usable by any `PrecompileTools` workload in a dependent package. Only `initializeModelManager()` — which resolves `PhysiCell`/`data` from `pwd()`, opens the database, and prints the banner — is skipped.

### Side effect this fixes, beyond the noise
Because the worker inherits the parent's working directory, precompiling an unrelated package *from inside a project folder* had PCMM open the real project. Demonstrated: a worker created `data/pcmm.db` (12 KB) in a directory containing bare `PhysiCell/` and `data/` folders. With a real project it would also run `resolvePackageVersion` (which has an auto-upgrade path) and `initializeDatabase()` schema writes from a throwaway process. Investigated and ruled out: the `@async databaseDiagnostics` task does *not* trigger Julia's `waiting for IO to finish` precompile warning — zero occurrences across three forced recompiles with a faithful stub; it only appears if the async body is slow.

### On "if the globals change, that should print"
Read as an implication, not a biconditional — so no change needed. `postInitDisplay` already prints whenever `initializeModelManager` succeeds, which is exactly when the globals change. In the two paths that now return early, nothing changes, so printing nothing is correct.

### Open questions
- Whether two ModelManager backends should ever coexist in one process. Today they cannot (one `simulator` field); PCMM now reliably claims the globals instead of silently deferring. If coexistence is ever wanted, `ModelManagerGlobals` needs a per-backend registry, which is a ModelManager change.

---

## 2026-08-02 — Absorb ModelManager's docs-findability pass; declare PCMM's public API

### Motivation
`HANDOFF-modelmanager-docs.md` arrived from a ModelManager session after MM's docs-findability pass (MM HEAD `7c91292`), framed as "opportunity, not repair." Audited against PCMM `main` (`10a65877d`), that framing is wrong: one item is a latent **build break**, two findings are false, one transfers only in a different form, and four problems the handoff never mentions turned up.

### The build break (the reason this is not optional)
MM's `src/tags.jl` exports 17 names. `docs/make.jl` sets `modules=[PhysiCellModelManager, ModelManager]` and `checkdocs=:exports` with no `warnonly`, so Documenter's `missingdocs` requires every docstring on an exported name in *either* module to be rendered — and no PCMM `Pages` entry matches `tags.jl` (all 42 enumerated). It passes today only because `tags.jl` is unreleased: `git rev-parse v0.8.2^{tree}` equals the `git-tree-sha1` registered for 0.8.2, and that tree has no `tags.jl`. PCMM's docs CI `Pkg.develop`s PCMM only, so MM comes from the registry. **The day MM cuts 0.8.3, the docs job goes red.** Since `src/PhysiCellModelManager.jl:4` does `@reexport using ModelManager`, users already get all 17 tag names — with no page and no mention anywhere.

### Handoff findings corrected
- (c) "`up.md` does not render `up.jl`" — **false**; `lib/up.md:11-19` renders it for both modules.
- (d) "`project_configuration.jl` is not rendered" — **false**; `lib/globals.md:26-33` renders it.
- (f) self-resolving "See the *X* API reference" links — **does not transfer** in that form (PCMM has no man/lib H1 collisions). The live bug is **backticked sub-headings shadowing docstrings**: the `Header` resolver (order 1.0) precedes `Docs` (3.0), and PCMM has ~17 headings that are bare backticked names. Builds stay green, so this needs a deliberate slug-intersection check.
- (b) the `utilities.md` glob — **real**. `Pages` matching is `endswith(path, p)`; an exhaustive sweep of 42 globs × 65 files found three cross-suffix collisions, but only `utilities.jl` ← MM `xml_utilities.jl` is live (only `utilities.md` lists both modules).

### Newly found
`src/deletion.jl`'s docstring is **orphaned**: Julia stores a docstring in `Docs.meta` of the module whose *source contains it*, keyed by the owner binding — so a PCMM-authored docstring on `ModelManager.clearSimulatorArtifacts` lives in `meta(PhysiCellModelManager)`, while `lib/deletion.md` lists `Modules = [ModelManager]` only. Also: a dead `@autodocs` block at `lib/calibration.md:82-86` (PCMM has no `calibration.jl`; the `AutoDocsBlocks` runner has no emptiness check, so glob typos fail silently), `man/index.md`'s unfiltered `@index` contradicting `index.md:27`, and sidebar labels drifting from their H1s.

### Key decision — do **not** mirror MM on the public-API question
PCMM has 234 documented bindings, 177 non-public, only 3 underscore-prefixed. MM resolved its equivalent by *promoting* 35 names on the rule "none is underscore-prefixed, so by this repo's convention they were never internals." Applied here that promotes ~174 of 177 and makes the index cut pointless.

Chosen instead: **reachability defines the public API** — a name is public if we tell users how to use it, or if it is passed to or returned from a non-internal. Internals do not appear in the docs at all; a developer who wants them reads the source. The first-order closure over public PCMM docstrings is **six names**, not 177: `AgentDict`, `MonadPopulationTimeSeries`, `SimulationPopulationTimeSeries`, `PCMMPCFResult` (all documented return types, constructed in doctests → promote), plus `prepareSimulationCommand` and `resolvePhysiCellVersionID` (named only in prose, and their callers are legitimately public → rewrite the prose instead of promoting plumbing).

Two supporting rules: run the closure to a fixpoint, since a newly-public type's docstring can name further internals; and count types users *receive or pass*, but **not** types that merely appear in a dispatching method's signature.

### Rejected — per-method docstring splitting
Considered splitting a public function's docstring so internal-dispatch methods stay unrendered. Not viable: `@autodocs` computes `APIStatus` and applies `Filter` **per binding, not per signature**, so `Public`/`Private`/`Filter` cannot exclude one method — the only lever is `Pages`, i.e. relocating source files to satisfy Documenter. Worse, `missingbindings` removes one signature at a time, so for an *exported* function, rendering only some method docstrings makes the rest count as missing → `:missing_docs` → build error. Fallback adopted: leave the internal internal, strip the `@ref`, keep plain backticks. The one place the pattern exists (`getMeanCounts`, documented once against `AbstractPopulationTimeSeries`) already does the right thing and is itself internal.

### Sequencing
Registered MM 0.8.2 contains **zero** `@compat public` — all 16 sites postdate the tag. Against it, MM's public set is 134 vs 213 at dev HEAD. So dropping the `Public = false` blocks before 0.8.3 would de-render most of MM's API on PCMM's site. Stages A–C (docs-only) land now; Stage D (public-API declaration + index cut) is **hard-gated on MM 0.8.3**. Nothing merges or releases until 0.8.3 is out.

### Scope notes
Docs-only for Stages A–C. Stage D touches `src/` (`@compat public`, docstring rewrites) and `test/` (guard testset); the promotion list goes up for review before any source edit. Following the 2026-06-12 precedent: progress.md entry, no PRD entry, no README Implementation Status row.

### Open questions
- Whether MM will fold `_resolveVerbosity`'s behaviour into `runCalibration`'s docstring once PCMM drops the explicit `@docs` that currently renders it (handback item).

---

## 2026-07-23 — Migrate `src/loader.jl` onto PhysiCellOutput.jl

### Motivation
`src/loader.jl` (~865 lines) duplicated logic that now lives in the standalone **PhysiCellOutput.jl** (BergmanLabRegistry). PhysiCellOutput owns path-based, stateless loading (types keyed on `folder::String`, no database identity). PCMM should depend on it and delete the ported code, keeping only its database-identity layer.

### Design decision — §5 (preserve API via extension) over §4 (wrapper)
`PCMM_MIGRATION.md` offered two paths: (§4) a piracy-free PCMM-owned wrapper type carrying `simulation_id` and restoring `SimID=…` display, or (§5) `import` the PhysiCellOutput functions and add `::Integer`/`::Simulation` methods routed through `pathToOutputFolder`. The doc *recommends* §4, but that recommendation predates PCMM's actual shape:

- The only internal callers of the loader API are `src/analysis/*.jl`; they are **heavily typed on the concrete `PhysiCellSnapshot`/`PhysiCellSequence`/`AbstractPhysiCellSequence` types** and read their fields directly.
- The public API (`PhysiCellSnapshot(id, index)`, `PhysiCellSequence(id)`, `cellDataSequence(id, …)`) is exercised by tests and docs.
- §4's wrapper must **not** subtype `AbstractPhysiCellSequence` (a documented gotcha — internal `getfield` use bypasses `getproperty` forwarding), so it would not flow through the analysis signatures without re-typing every one; and it renames the public constructors. Net: §4 is the *more* invasive option here.
- §5 preserves the exact public API and keeps all analysis code working unchanged, because id-based constructors return the *real* folder-based PhysiCellOutput objects. Piracy is confined to one file and is tolerable because PCMM is the terminal application in the stack (the doc says as much).

Chosen: **§5**, plus keep `assertInitialized()` at PCMM's id-based entry points (PhysiCellOutput doesn't assert).

### The one real friction: `sequence.simulation_id`
PhysiCellOutput's `PhysiCellSequence` has no `simulation_id` field. Three sequence-typed builders read it to stamp results: `SimulationPopulationTimeSeries` (`population.jl`), `AverageSubstrateTimeSeries` and `ExtracellularSubstrateTimeSeries` (`substrate.jl`). Every public/test path reaches these via an id/`Simulation`/run-output entry point (no bare-sequence call in tests), so the id is threaded explicitly from the entry point into the sequence-typed builder instead of being read off the sequence.

### Consequences
- `show(::PhysiCellSnapshot)` now prints `Folder=…` (PhysiCellOutput's display) instead of `SimID=…`. No test asserts the old text; accepted.
- `getCellDataSequence` deprecation now comes from PhysiCellOutput (re-exported); PCMM's own copy deleted.
- `_safe_matread` zero-cell workaround dropped; relies on `MAT ≥ 0.12.1`.

### Open questions
- None blocking. Optional future: an additive SimID-carrying convenience type if users want `SimID=…` display back.

---

## 2026-07-22 — Vector/range dispatch for `makeMovie`

### Motivation
`makeMovie(4:7)` (a `UnitRange{Int}`) and `makeMovie(Simulation.(4:7))` (a `Vector{Simulation}`) both threw `MethodError` — only the scalar `Int`, single `AbstractTrial`, and `PCMMOutput` forms existed. Batching over an explicit collection of IDs or trials is a natural call and should mirror the existing `AbstractTrial` batching.

### Design
- Added `makeMovie(simulation_ids::AbstractVector{<:Integer}; kwargs...)`, reusing the "announce → loop → delegate" shape of the `AbstractTrial` method.
- Added `makeMovie(Ts::AbstractVector{<:AbstractTrial}; kwargs...) = makeMovie(simulationIDs(Ts); kwargs...)`, flattening to IDs via `simulationIDs` (already accepts a vector of trials) so it reuses the integer-vector path.
- Broadened the worker signature from `simulation_id::Int` to `simulation_id::Integer`: elements of `AbstractVector{<:Integer}` / the output of `simulationIDs` aren't guaranteed to be `Int`, and downstream (`trialFolder`, etc.) already accept `Integer`. Purely additive — no behavior change for existing callers.

### Testing
Extended `test/test-scripts/MovieTests.jl` (Apple branch) with `makeMovie(1:1)` and `makeMovie(Simulation.(1:1))`, each a no-op (`out.mp4` already exists) returning `nothing`.

---

## 2026-07-08 — Expose Makefile animation parameters (`framerate`, `magick_density`, `magick_resize_x/y`) in `makeMovie`

### Motivation
`makeMovie` (`src/movie.jl`) only ever forwarded `OUTPUT=` to the PhysiCell Makefile's `jpeg`/`movie` targets, even though that Makefile also reads `FRAMERATE`, `MAGICK_DENSITY`, `MAGICK_RESIZE_X`, `MAGICK_RESIZE_Y` (defaults 24 fps / 96 dpi / 1024×1024). Users had no way to control frame rate or JPEG resolution/density from Julia.

### Design
- Added four new keyword arguments to `makeMovie(simulation_id::Int; ...)`, each `Union{Missing,Int}=missing`, mirroring the existing `magick_path`/`ffmpeg_path` sentinel pattern already in this function rather than inventing a new convention.
- Each is only appended as a `"VAR=value"` string to the relevant `Cmd` when not `missing` — an unset keyword falls through to whatever the target project's own Makefile defines for that variable, rather than PCMM silently overriding a user's project-level Makefile customization.
- `framerate` targets the `movie` command; `magick_density`, `magick_resize_x`, `magick_resize_y` target the `jpeg` command (matches which Makefile target actually reads which variable).
- `makeMovie(T::AbstractTrial; kwargs...)` / `makeMovie(T::PCMMOutput; kwargs...)` needed no changes — they already forward `kwargs...` untouched.

### Testing
Extended `test/test-scripts/MovieTests.jl` with a case passing non-default values for all four new keywords and confirming `out.mp4` is still produced; existing no-kwargs path is unchanged and still covered.

### Docs
- `docs/src/lib/movie.md` needed no edit — it's an `@autodocs` page over `movie.jl`, so the updated docstring flows through automatically.
- Added a "Movies" section to `docs/src/man/analyzing_output.md` (before "Post-processing during a run") documenting `makeMovie` and a table mapping each new keyword to its Makefile variable and default.
- Added a matching recipe to the `examples.md` cookbook, linking back to that new section, following the existing task → minimal code → link pattern.

---

## 2026-07-08 — Task B: `populationCountQoI`, a ready-made `post_processor` builder

### Motivation
Task A made `post_processor` usable (intact output guaranteed), but a user still had to know
which PCMM loader to call and how to shape its return value. Task B (deferred from the
original post-processing handoff, "optional/nice-to-have") closes that gap: a one-line
`post_processor` for the most common QoI, per-cell-type population counts, at the final
snapshot or any indexed save (the user asked for both explicitly).

### Design
- New file `src/analysis/post_processor_qois.jl` (included from `analysis.jl`), kept
  separate from `src/analysis/standard_qois.jl` on purpose: that file's functions are
  calibration summary statistics keyed by `monad_id` and averaged across replicates (for
  `CalibrationProblem`); `populationCountQoI` returns a closure keyed by `SimulationProcess`
  for ModelManager's post-processing sink (one row per simulation). Different shape, different
  consumer — conflating them in one file would blur that distinction.
- `populationCountQoI(; index=:final, cell_types=nothing, include_dead=false)` mirrors the
  existing `cell_types`/`include_dead` keyword convention from `endpointPopulationCounts`
  (`standard_qois.jl`) for consistency rather than inventing new names.
- Returns `Dict("count_$(name)" => n for ...)` rather than a `NamedTuple`: cell type names
  can contain spaces (e.g. `"fast T cell"`), which aren't valid `NamedTuple` field names: a
  `Dict` sidesteps that identifier-validity problem entirely.
- Missing snapshot (e.g. pruned) → `populationCount`/`PhysiCellSnapshot` already return
  `missing` for that case; the builder checks for it and returns `nothing` (no QoI recorded)
  rather than propagating an error, matching the "prefer `nothing` for the no-data case"
  guidance from the original handoff.

### Testing
New `test/test-scripts/PostProcessorQoITests.jl` (added to `runtests.jl` after
`PopulationTests.jl`, so `finalPopulationCount`/`populationCount`/`pruned_simulation_id`
semantics are already established). Constructs a `SimulationProcess` directly (plain struct,
default positional constructor) to unit-test the returned closure — index default, integer
index, `cell_types` filter, `include_dead`, and the pruned/missing-snapshot path — without
needing a live run for each case, plus one full `run(...; post_processor=populationCountQoI())`
integration test asserting the sink DB (`postProcessingTable`) is populated correctly.

### Docs
- API reference: `docs/src/lib/analysis.md`, new "Ready-made `post_processor` builders"
  subsection with an explicit `@docs populationCountQoI` block (mirrors how
  `calibration.md` documents `standard_qois.jl`'s functions individually rather than via a
  blanket `@autodocs` page, since `checkdocs=:exports` requires every export to be
  documented somewhere).
- User guide: also wrote the "Post-processing during a run" section in
  `analyzing_output.md` that was deferred from the original docs handoff (gated on Task B
  landing) — hook description, the three return patterns with real PhysiCell loaders (not
  ModelManager's stand-ins), the `populationCountQoI` builder, and reading results back.
  Cross-linked from a new `examples.md` cookbook entry.

---

## 2026-07-08 — Docs for batch `run(Vector)` and the calibration evaluation budget (D5/D6)

### Source
Third handoff from the ModelManager session (`handoff-pcmm-batch-and-budget.md`), completing the story started by the post-processing handoffs. Both ModelManager changes are inherited via `@reexport using ModelManager` — no PCMM code change, doc-only.

### D6 — `max_evaluations` enforcement (`docs/src/man/calibration.md`)
Verified against the ModelManager dev checkout (`_capBatchToBudget`, applied before dispatch in both `_runFirstGeneration` and `_runSubsequentGeneration`, `src/calibration/abc_smc.jl`). Rewrote the "Evaluation budget" section to state, as current behavior, that the cap is enforced before each batch (never overshoots) and the final generation may be partial. Added a callout that `max_evaluations` counts particles (monads), not simulations — a calibration launches up to `max_evaluations × n_replicates` PhysiCell simulations, since PCMM's `CalibrationProblem` runs `n_replicates` simulations per particle.
Deliberately wrote this as "how it behaves," not "here's what changed" — a reader who never saw the old overshooting behavior shouldn't have to parse a before/after diff to understand the current contract.

### D5 — batching pre-built trials (`docs/src/man/examples.md`)
PCMM has no page equivalent to ModelManager's `running_simulations.md`, so the cookbook-style `examples.md` (task → minimal code → link) was the right home instead of forcing a new page. Added a "Batch pre-built trials into one run" recipe linking to `Your first project`, since that page already documents the `PCMM_NUM_PARALLEL_SIMS` parallel-pool knob — ties the "one parallel pool across the whole batch" behavior to a concept the reader has already seen.

### Style note (user feedback, applies going forward)
Don't over-explain decisions in docs pages by referencing prior versions or the conversations that produced them — a reader new to PCMM has no context for "used to be X, now Y." State current behavior directly; save the before/after narrative for this file.

---

## 2026-07-07 — Post-processing hook: move pruning to `postSimulationCleanup` (Task A)

### Motivation
ModelManager (0.7.x, dev) added a user `post_processor` callback and split the single per-simulation post hook into `postSimulationProcessing` (non-destructive, before the callback) → `post_processor` → `postSimulationCleanup` (destructive, after). PCMM was pruning inside `postSimulationProcessing`, so under the reordered ModelManager a user callback would be handed an already-gutted output folder. This session moves PCMM's destructive work to `postSimulationCleanup` so a `post_processor` always reads intact output.

### Synthesis source
Planned from two handoff docs from the ModelManager session (`handoff-pcmm-postprocessing.md` = code, `handoff-pcmm-docs.md` = docs). Their inferred PCMM specifics were re-verified against source before coding: `postSimulationProcessing(::PhysiCellSimulator, …)` was at `src/simulator_interface.jl:246` with exactly the described body (err handling + `pruneSimulationOutput(simulation, prune_options)`).

### Decisions
- **Moved the whole body**, not just pruning: the err-file handling (rm `output.err`/`hpc.err` on success; annotate on failure) runs equally well after the callback, and a callback has no reason to read `output.err`. Cleanest split — leaves `postSimulationProcessing` at ModelManager's no-op default, so PCMM no longer defines it at all.
- **Import wiring:** swapped `postSimulationProcessing` → `postSimulationCleanup` in the `import ModelManager:` (extend) list; kept `postSimulationProcessing` in the non-extending `using ModelManager:` line so its docstring `@ref` still resolves (ModelManager doesn't export the hooks and PCMM has no DocumenterInterLinks, so a referenced symbol must be in PCMM's namespace).
- **Testing:** dev-checked-out the local ModelManager worktree (v0.7.5, which already has the reordering + no-op `postSimulationCleanup` default) so the reordered contract is exercised locally. Confirmed method resolution: PCMM owns `postSimulationCleanup(::PhysiCellSimulator, …)`; `postSimulationProcessing` falls through to ModelManager's no-op.
- **No compat change:** PCMM pins `ModelManager = "0.7"`; the feature ships in a `0.7.x` bump, still in range.

### New export the handoffs missed — `monadsTable`
ModelManager also just added `monadsTable`/`printMonadsTable` (monad-level analogue of `simulationsTable`), re-exported by PCMM. Documented this session:
- **API reference:** no change needed — `docs/src/lib/database.md` already autodocs `Modules = [PhysiCellModelManager, ModelManager], Pages = ["database.jl"]`, and `monadsTable` lives in ModelManager's `database.jl`, so it's auto-included once docs rebuild against the updated ModelManager.
- **User prose:** added a "Monad-level: `monadsTable`" subsection to `man/querying_parameters.md` (next to `simulationsTable`), not `analyzing_output.md` — querying_parameters is where `simulationsTable` is already explained, so the analogue belongs there.

### Docs nav rename (same session, user request)
Renamed the docs nav section `"Experiments"` → `"Uncertainty Quantification"` in `docs/make.jl` to match ModelManager's naming (both group Sensitivity analysis + Calibration). Nav-label-only; no prose referenced "Experiments".

### Test strategy
Appended to `PrunerTests.jl`: a run with a `post_processor` that records whether `output*.mat` files exist in `pathToOutputFolder(sp)` during the callback (must be intact), then asserts they're gone after the run (cleanup pruned them). No-regression "pruning without a callback" is already covered by existing `pruned_simulation_id` assertions in Loader/Population/Substrate tests, fed by the existing no-callback run in `PrunerTests.jl`.

### Open questions
- Task B (QoI builders): design `populationCountQoI(; index=:final)` on `PhysiCellSnapshot(sim_id, index)` — the user asked for final counts *and* any indexed save.
- Release lockstep: PCMM Task A must not ship against a ModelManager that still has the old single-hook ordering.

---

## 2026-06-15 — Upgrade-path CI for `src/up.jl`

### Motivation
`src/up.jl` (cross-version DB/file migrations) was untested. It can't live in `Pkg.test()` because exercising a migration needs *two* package versions present: an old one to write legacy data and a new one to upgrade it. Goal: a dedicated workflow that replays real version history.

### Findings that shaped the design
- **`v0.0.1`/`v0.0.2` were never released.** Registry floor is `pcvct@0.0.3` (UUID `3c374bc7…`); the package was renamed to `PhysiCellModelManager` (UUID `7582d1aa…`) at `0.1.0`. So the harness derives the package name from the source version, and "start at v0.0.1" is impossible via `Pkg`.
- The upgrade driver (`ModelManager.upgradePackage`) always upgrades to the runtime `pkg_version`; there is **no "stop at version X" knob**, and ModelManager is out of scope (separate repo). So "one milestone hop" is controlled by *which version performs the upgrade*, not by capping.
- `upgradeToV0_3_0` only adds the `calibrations` table, which `initializeDatabase` also creates on every init — so that migration's effect is shadowed and not independently observable. Early hops therefore assert **data preservation**, not migration-specific deltas.

### Decision: "go backwards"
Rather than start at the oldest release and upgrade with an *intermediate released* version (which would test released code, not the repo), generate with an older release and **upgrade with the dev checkout** — this exercises the repo's actual `src/up.jl`.
- **Concrete goal (this session):** support upgrading a **`0.1.7`** project — the version a real user (the repo owner) is currently on — to `HEAD`. `0.1.7` → `HEAD` crosses `0.2.0` (the `upgradeToV0_2_0` par_key binary rewrite) and `0.3.0`.
- CI matrix source versions: `0.1.7` (primary) and `0.2.2` (isolates the `0.3.0` hop for diagnosis). Verified against the `v0.1.7`/`v0.2.2` tags that the generation API — `createProject`, `InputFolders(...; rulesets_collection)`, `DiscreteVariation`, `configPath` shortcuts, `createTrial(...; n_replicates)`, `run` → `PCMMOutput` — is unchanged, so one `generate.jl` covers both.
- `verify.jl` asserts the distinguishing `par_key` column on every varied-location variations table when the `0.2.0` milestone is crossed (not produced by normal init, unlike `0.3.0`'s `calibrations` table).
- Source version is a single parameter so we can keep walking back into the `pcvct` era, ideally to `0.0.3`.

### Rejected
- *Generate@0.0.3 → upgrade@0.0.10 (released)* — tests the released migration code, not the repo's `up.jl`; also can't reach the pre-0.0.3 functions anyway. Kept as a possible future "released-vs-released" cross-check, not the primary path.
- *Adding a `target_version` cap to `initializeModelManager`* — would let the dev version do a single hop from old data, but requires editing ModelManager (out of scope).

### Design
New workflow `.github/workflows/UpgradeCI.yml` (same triggers as `CI.yml`; ubuntu-latest; Julia `lts` + `1`). Two isolated Julia envs under `test/upgrade/tmp/`: a generation env with the pinned old release, and the dev checkout for the upgrade. Scripts `test/upgrade/generate.jl` and `test/upgrade/verify.jl`, parameterized by `PCMM_UPGRADE_SOURCE_VERSION`. Verification reads the SQLite DB directly so it's independent of either package's API.

### First CI run — caught a real bug (the harness paid off immediately)
The very first `0.1.7` → `HEAD` run failed at the `0.2.0` milestone with `UndefVarError(:validateParsBytes)`. Root cause: `upgradeToV0_2_0` (`src/up.jl`) calls `validateParsBytes` unqualified, but the `bafb5b528` modularization moved that helper into ModelManager (`variations.jl`) and it is **not exported**. The other non-exported MM helpers `up.jl` needs were explicitly imported at the top (`using ModelManager: continueMilestoneUpgrade, populateTableOnFeatureSubset`); `validateParsBytes` was missed.
- **Impact:** this is a real shipping bug — any user on `0.1.7` (incl. the repo owner) could not upgrade to `0.2.0+`; the migration threw and rolled back every time.
- **Fix:** added `validateParsBytes` to that explicit import. Chose the in-repo import over exporting from ModelManager (out of scope) and to match the existing pattern in the file.
- Only this one surfaced because it is the last statement in the migration's `try` block — everything before it resolved, so the rest of the chain is exercised.

### Open questions
- How far back can generation's API be reused? `0.2.x`→`0.3.x` should share the `createProject` / `run(sampling)` API; the `pcvct` era will likely need an older generation script.
- Does `pcvct@0.0.3` stamp a version table the newer code can read? (Resolved only when we walk back that far.)

---

## 2026-06-12 — Documentation restructure for clarity & discoverability

### Motivation
Users repeatedly asked how to use PCMM. The docs were accurate but dense and poorly catalogued: a flat 17-item "Manual" in arbitrary order (led with *Best practices*, not *Getting started*), a 34-page alphabetical API "Documentation" dump, a getting-started page that buried the happy path under the optional `importProject` workflow, and no Julia environment-management guidance.

### What changed
- **Sidebar regrouped by user intent** (`docs/make.jl`): Getting Started → Building & Varying Models → Experiments → Analyzing Results → Examples → Tools & Integrations → Reference → Contributing → API Reference → Miscellaneous.
- **Getting-started split** into focused pages: `installation.md`, `julia_environments.md` (new — per-project envs as a Julia best practice), `getting_started.md` retitled *Your first project* (happy path only), and `importing_projects.md` (the extracted `importProject` workflow).
- **New `examples.md` cookbook hub**: task-oriented catalog ("I want to… → snippet + link"). `index.md` rewritten as a hub with a "Where do I look?" table.
- **API reference grouped by code family** (Core / Project & inputs / Running / Analysis / Management), explicitly *not* mirroring the Manual; alphabetical Index kept for name lookup. List is now hand-maintained (noted in a `make.jl` comment).
- **Editorial concision pass** over every manual page — cut filler/hedging, collapsed restatements, listified dense paragraphs; no facts, examples, `@ref`s, or doctests removed.

### Key decisions
- **Manual vs API reference kept independent.** Considered mirroring their structure (user asked); rejected as redundant and high-maintenance — they serve different purposes (intent-ordered narrative vs. lookup-optimized exhaustive docstring home).
- Renamed the XML-path-helpers page H1 from "Helper functions to define targets" → "XML path helpers" to match its sidebar label; updated the one referrer.
- Disambiguated colliding section refs: `[Examples]` and `[Calibration]` resolved via explicit `@id` (`examples_cookbook`, `calibration_section_man`) because duplicate/`@id`-bearing headers exist.

### Verification
Built docs locally with `julia --project=docs docs/make.jl`. Cross-reference and nav validation pass (no broken `@ref`, no unlisted pages). The pre-existing `src/analysis/pcf.jl` doctests fail locally only because the optional `PairCorrelationFunction` package isn't in the local docs env — unrelated to this change and green on CI. Validated links by building once with `doctest=false` (temporary, reverted).

### Scope notes
Docs-only; no source/PRD/behavior changes. README Implementation Status unaffected (tracks features, not docs structure).

---

## 2026-05-17 — MM 0.7.0 calibration features; CI registration gap

### Status
All calibration infrastructure is now in ModelManager 0.7.0 (branch `feature/latent-inverse-maps`, ready to merge). PCMM's `Project.toml` already pins `ModelManager = "0.7.0"`.

### CI failure
PCMM CI is failing because ModelManager 0.7.0 is not yet registered in BergmanLabRegistry (latest registered is 0.6.0). Fix sequence:
1. Merge MM `feature/latent-inverse-maps` → `main`.
2. Register `ModelManager 0.7.0` in BergmanLabRegistry (add entry to `Versions.toml` with the git-tree-sha1 of the new `main` tip).
3. Re-run PCMM CI — the resolver should pick up 0.7.0 immediately.

### What's in MM 0.7.0
- `LatentVariation.target_names` for user-supplied LV parameters
- `inverse_maps` validation and auto-construction for DV/CVSource; user-supplied + round-trip check for LVSource
- `resumeABC` structural validation extended to LVSource (non-stripped)
- Scan-based `_loadGenerations` (padding-agnostic on resume)
- `generation_cdfs/` stored as subdirectory of `generations/`
- Posterior visualization recipes: `:corner`, `:ridgeline`, `:convergence`, `:transition`
- `short_names=false` kwarg on `simulationsTable`
- Kernel type hierarchy: `GaussianKernel`, `ComponentwiseKernel`, `LocalNNKernel`, `LocalNNCovKernel`

---

## Rollback anchor — last commit with functioning pyabc backend

If the native Julia ABC-SMC implementation proves non-functional or needs a side-by-side comparison, the last commit with the fully-wired PythonCall/pyabc backend is the tip of the `feature-par-naming` branch at the point of the merge into `feature/julia-native-abc`:

- **Commit:** `9d9dda07aa1464db02a9aeb1d0171d3f32db15f0`
- **Subject:** "Merge branch 'main' into feature-par-naming"
- **Last substantive pyabc change:** commit `2d575527` ("Refactor calibration integration from PyCall to PythonCall")

To restore the working pyabc state: `git checkout 9d9dda07aa1464db02a9aeb1d0171d3f32db15f0 -- ext/PCMMCalibrationExt.jl CondaPkg.toml Project.toml src/calibration/` (adjust paths as needed) or branch from that commit directly.

---

## 2026-04-24 — Remove PythonCall / pyabc deprecation residue

Executed the cleanup promised in the 2026-04-22 entry and in [PRD.md](PRD.md). Native ABC-SMC passed the full test suite (107/107 CalibrationTests; overall 581/2/4 matching pre-merge baseline), so the deprecated pyabc surface is now deleted:

- `ext/PCMMCalibrationExt.jl` — deleted. The stub only emitted a `Base.depwarn`; it added no methods. Removal has no runtime effect.
- `CondaPkg.toml` — deleted. No longer needed since no Python deps remain.
- `Project.toml` — removed `PythonCall` from `[weakdeps]`, `[extensions]`, `[compat]`, `[extras]`, and the `test` target list.
- `docs/src/man/calibration.md` — removed the "Deprecated pyabc backend" trailer section.
- `PRD.md` — removed the "Sub-feature: Deprecated pyabc backend" subsection.

Rollback is via the commit hash recorded above, if ever needed.

---

## 2026-04-24 — `AbstractSimulationSpec` / `SimulationSpec` refactor

Replaced the calibration's `redirect_stdout(devnull)` stopgap with a real `quiet=true` kwarg on `run` by completing the SimulationSpec refactor across MM and PCMM.

### Architecture

- **`AbstractSimulationSpec`** (in MM, `src/runner.jl`): abstract type, extension point for future simulators with distinctive per-spec state. Not a dispatch axis.
- **`SimulationSpec`** (in MM): concrete default subtype with just two fields: `simulation::Simulation` + `monad_id::Union{Missing,Int}`. PCMM uses this directly — no PCMM-specific spec needed because the spec is truly framework-agnostic.
- **One dispatch axis: simulator type.** No separate `dispatchSimulation` function. The existing `runSimulation(::AbstractSimulator, ...)` does all simulator-specific routing. Its signature is now `runSimulation(::AbstractSimulator, spec::AbstractSimulationSpec) → SimulationProcess`.
- **Setup hooks** (`setupMonad`, `setupSampling`) remain the simulator-specific injection point. They run once at the right level in `collectPendingSimulations`. Simulator-specific flags like PhysiCell's `force_recompile` flow as kwargs through `run` → setup hooks AND through `run` → per-spec `runSimulation`.
- **`do_full_setup` is encoded implicitly** in `ismissing(spec.monad_id)`: solo specs need full setup, monad-collected specs don't. PCMM's `runSimulation` derives this. Removed the explicit `do_full_setup` kwarg from the spec.

### Why drop `dispatchSimulation`

The earlier draft had `dispatchSimulation(::AbstractSimulationSpec; kwargs...)` as an interface stub for spec-type dispatch. Removed because: (a) for the common case of one spec type per simulator, it's redundant with simulator dispatch; (b) the user's intuition was right — by spec time, all simulator-specific routing should be done. `runSimulation(simulator, spec)` is the only dispatch we need.

### Restored: per-simulation `println`

The "Running simulation: N..." line was lost in modularization (verified by grep). Now restored, living inside the `@task begin … end` body in MM's `run` so it prints when the task is *scheduled* (i.e. when the simulation actually starts), not when the list comprehension constructs the task. Gated by the `quiet` kwarg.

### Files touched

- `~/.julia/dev/ModelManager/src/runner.jl`: defined `SimulationSpec <: AbstractSimulationSpec`; `collectPendingSimulations` now returns `Vector{<:AbstractSimulationSpec}` and forwards kwargs to setup hooks; `runSimulation` interface stub takes `(::AbstractSimulator, spec; kwargs...)`; removed old `dispatchSimulation(::Simulation; ...)`; `run(T; quiet=false, kwargs...)` builds `@task` wrappers itself with per-sim println inside, gated by `quiet`.
- `src/simulator_interface.jl`: deleted local `SimulationSpec`; imports `SimulationSpec`/`AbstractSimulationSpec` from MM; `runSimulation(::PhysiCellSimulator, spec; force_recompile, kwargs...)` derives `monad_id` and `do_full_setup` from `spec.monad_id`.
- `src/calibration/abc.jl`: replaced `redirect_stdout(devnull) do run(monad) end` with `run(monad; quiet=true)`.
- CLAUDE.md: removed the "Port `quiet` kwarg" to-do.

---

## 2026-04-22 — Julia-native ABC-SMC (replacing pyabc)

### Context

The pyabc backend (via PythonCall/CondaPkg) worked but carried baggage: conda environment management, `SingleCoreSampler` constraint (Julia closures can't be pickled), and a deep PythonCall bridge. Goal: replace with a native Julia implementation.

### Julia ABC ecosystem survey

- **ApproxBayes.jl** — 56 stars, compatible with Julia 1.9+, but last substantive commit Sept 2024 (license update). Parallelism via `Distributed.jl` conflicts with PCMM's Channel-based runner.
- **KissABC.jl** — ARCHIVED Dec 2025, redirects to ABCdeZ.jl (unproven).
- **GpABC.jl** — 58 stars, actively developed (CI runs on Julia 1.12). The `julia = "1.6, 1.7"` compat string parses as intersection = `>=1.7.0`, so it *is* compatible with modern Julia. Initial survey misread this. Has GP emulation — worth revisiting for future surrogate work.
- **SimulationBasedInference.jl** — early stage, ABC-SMC not fully implemented.

Decision: implement directly. ABC-SMC is ~250 lines of algorithm code (Toni et al. 2009 / Beaumont et al. 2009), no new dependencies, integrates cleanly with PCMM's Monad/runner infrastructure.

### Key design decisions

**Framework-agnostic algorithm core**
`src/calibration/abc_smc.jl` operates on a generic `evaluate_particle(params) → (distance, metadata)` callback. All PhysiCell-specific wiring (Monad creation, addVariations, run) is isolated in `src/calibration/abc.jl`. This makes the upcoming extraction to ModelManager.jl straightforward — the algorithm core moves to the base package, and PCMM provides the PhysiCell adapter.

**Extensible `AbstractCalibrationMethod` hierarchy**
Added `AbstractCalibrationMethod` supertype with `ABCSMC <: AbstractCalibrationMethod`. Future methods (GP-accelerated ABC, Bayesian optimization) are additional concrete subtypes. `runCalibration(problem, method)` is the dispatch point; `runABC` is a convenience wrapper that constructs an `ABCSMC` from keywords.

**No warm-start from existing simulations**
An earlier design seeded gen 1 with all existing monads for this InputFolders. Rejected because it biases the gen-1 population away from the prior (the prior samples need to be truly random for the ABC-SMC weights to be correct). Instead, `Monad(...; use_previous=true)` in every particle evaluation still reuses exact-match parameter points transparently — no statistical bias, and zero cost when matches exist.

**Quiet mode for `run`**
Added `pcmm_globals.quiet_run::Bool` flag and `quiet::Bool=false` kw on `run`. When true, suppresses the "Running Sampling/Simulation..." and "Finished..." output. The calibration loop sets it so console output stays focused on per-generation progress.

**pyabc extension: depwarn, then delete**
User decision: deprecate and remove, but wait to confirm native works before deleting. The extension (`PCMMCalibrationExt`) is now a one-line `__init__` that emits `Base.depwarn` and adds no methods. The pyabc-specific code (runABC override, prior builder, etc.) has been removed from the extension entirely — rollback is via `git checkout` if needed.

**Result persistence**
Each generation is saved as `generations/generation_{t}.csv` with columns = param names + weight + distance + monad_id. Settings saved as `method.toml`. Together these support `resumeABC(calibration, problem)` for crash/stop recovery.

### Correctness verification

- Toy test: recover the mean of a Normal distribution via ABC-SMC. Posterior mean converged to ~2.15 against observed ~2.14 (true=2.0) over 5 generations, with epsilon shrinking 7.17 → 0.27 as expected.
- Full test suite: 107 calibration tests pass (algorithm unit tests, PhysiCell end-to-end, resume).

### Open questions

- GP emulation (GpABC.jl or custom): would reduce expensive PhysiCell evaluations. The `AbstractCalibrationMethod` hierarchy is ready for this — add `GPAcceleratedABC <: AbstractCalibrationMethod` without restructuring.

---

## 2026-03-29 — Analysis naming decisions

**`finalPopulationCount(Monad)` placement**
Added to `src/analysis/population.jl` (not a calibration file) because it is a general analysis utility. The summary statistics in `standard_qois.jl` delegate to it.

**`meanPopulationTimeSeries` naming**
Rejected "endpointPopulationTimeSeries" (contradictory terms). Chose `meanPopulationTimeSeries` wrapping `MonadPopulationTimeSeries.mean` field.

---

## Test infrastructure — 2026-03-30

### Decisions made

- Cleanup runs at the **start** of `runtests.jl`, not the end. Artifacts remain after a run for manual inspection; they are cleared before the *next* run.
- Artifacts list is maintained in sync between `test/.gitignore` and the cleanup block in `runtests.jl`. Both must be updated when a new test adds output paths.
- `test.out` (redirected stdout from manual runs) added to `.gitignore`.
- `InvalidRulesetExport` (generated by `ExportTests.jl`) was missing from `.gitignore` — added.

### Pre-existing test failures (not related to calibration)

These existed before this feature branch and should be tracked separately:
- `PhysiCellVersionTests` — HTTP 401 from GitHub API (rate limit in CI).
- `PhysiCellStudioTests` — likely same network dependency.
- Several test suites require a downloaded PhysiCell binary; they fail locally when it is absent but pass on GitHub runners.

---

## 2026-03-31 — Optional names for variations

### Decisions made

- Added optional `name` fields to all concrete `AbstractVariation` subtypes: `DiscreteVariation`, `DistributedVariation`, `CoVariation`, and `LatentVariation`.
- Introduced `variationName(::AbstractVariation subtype)` as the unified accessor for display labels.
- Chose keyword argument `name=...` for constructors to preserve existing positional APIs.
- For omitted names, defaults follow `shortVariationName(location, columnName(target))` conventions so labels align with existing summary table naming.
- `CoVariation` stores a single name for the combined variation; child variation names remain on each entry in `cv.variations`.
- Sensitivity scheme headers now naturally inherit variation names because `LatentVariation(dv|cv)` uses `variationName(...)` for `latent_parameter_names`.

### Notes

- This change is metadata-only for display and reporting; it does not alter variation keys in SQLite tables, which remain XML-path-based.

---

## 2026-04-25 — PCMM side of SimulationSpec flatten / setup-collect split

Counterpart to the MM refactor of the same date. See MM `progress.md` for the design rationale.

### Changes in PCMM

- **`setupSampling`**: type annotation `Sampling` → `AbstractSampling`. No logic change — `loadCustomCode(S::AbstractSampling)` already works.
- **`setupMonad`**: removed `do_full_setup::Bool` kwarg and its `if do_full_setup ... loadCustomCode ... end` guard. `setupSampling` always runs before `setupMonad` now, so compilation is always covered. Type annotation `Monad` → `AbstractMonad`.
- **`runSimulation`**: removed `ismissing(spec.monad_id)` branch. `spec.monad_id` is always `Int` post-refactor.
- **`prepareSimulationCommand`**: removed `do_full_setup::Bool` parameter and the setup branch it guarded. Signature is now `(simulation, monad_id, force_recompile)`.
- **`HPCTests.jl`**: `SimulationSpec(simulation, missing)` → `SimulationSpec(simulation, monad.id)`.
- **Imports**: removed `AbstractSimulationSpec` from `using ModelManager: ...` line.

### Files touched
- `src/simulator_interface.jl`
- `test/test-scripts/HPCTests.jl`
