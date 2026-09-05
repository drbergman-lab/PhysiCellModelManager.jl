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

Seven release-backlog items arrived with the ModelManager 0.9 bump. Two — a compile error leaving a stale
executable, and re-checking the PhysiCell version mid-session — were already done in the 2026-08-19 entry and
should not be re-investigated; PhysiPKPD inputs was deferred to a CLAUDE.md to-do. ModelManager #46, #47 and
0.9.1 landed mid-session and are absorbed here.

**Decisions**
- **Version 0.4.0, not 0.3.4.** `runStudio`'s error type, `configPath` rejecting unrecognised tokens, and
  `plotbycelltype`'s corrected numbers are breaking on their own terms. Compat bound `"0.9.1"`, not `"0.9"`:
  `"0.9"` resolves to `[0.9.0, 0.10.0)` and would let a project resolve 0.9.0 while the docs promise behaviour it
  lacks.
- **ModelManager 0.9 mechanics.** `pcmmVersion()`'s docstring says *installed* version, following
  `getInstalledVersion`. `rm_hpc_safe`'s new contract (remove first, stage the residue, return `:removed`/`:staged`)
  is a test-side change; the staging path is left uncovered rather than faked, since on a healthy filesystem nothing
  is ever staged.
- **`runStudio` wraps both failure types** in `PCMMStudioLaunchError`: `Base.IOError` (has `.code`) when the binary
  cannot be spawned, `ProcessFailedException` (has `.procs`, no `.code`) when Studio exits non-zero.
- **`prepareBaseFile` on an unselected `:rulesets_collection`.** The `AssertionError` was PhysiCellXMLRules being
  right about its own contract; PCMM should never have made the call. `src/configuration.jl` tested
  `location == :rulesets_collection` before the `ismissing(input_folder.basename)` guard; reordering the two
  branches is the whole fix.
- **`PCMM_PUBLIC_REPO_AUTH`: bound the cascade, do not fix the token.** A set-but-empty token sends
  `Authorization: token ` and GitHub answers 401. Leave the token a GitHub secret and accept the local failure, on
  condition that it costs exactly one error. (Superseded 2026-09-05: an empty value is now treated as unset.)
- **Missing data is audible.** `finalPopulationCount(::Monad)`, `endpointPopulationFractions`,
  `MonadPopulationTimeSeries` and `plotbycelltype` each report a dropped replicate with `@info ... maxlog=1`.
  `@info`, not `@warn`: pruning is a deliberate user action. `maxlog=1` is load-bearing — calibration calls these
  once per monad across thousands of particles — and Julia scopes it per callsite, so each site still reports.
  `plotbycelltype` re-implements the aggregation and divided by the unfiltered replicate count while filling only
  the loaded replicates; now the filtered count. The four sites share no implementation, so each needs its own `@info`.
- **`configPath("<cell type>", "motility", <tag>)` closes the class, not the instance.** A footgun rather than a
  correctness bug (the variation write path throws "Element not found" rather than writing), but a natural guess
  must resolve or be rejected by name. `<motility>` and `<chemotaxis>` have closed tag sets, so an unrecognised
  third token raises an `ArgumentError` naming the valid ones; `advanced_chemotaxis` stays open-ended because its
  third token is a substrate name. The regression test asserts the two-token and three-token spellings agree.
- **One `Dict`-valued `QoI` per calibration statistic**, not a `Vector{QoI}` with one per cell type. Merged
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

  Each reducer filters `missing` itself (ModelManager hands it every replicate's value). One deliberate deviation
  from bit-exactness: where every replicate is missing, `meanPopulationTimeSeriesQoI` returns `missing` where
  `meanPopulationTimeSeries` raises an incidental `KeyError`.
- **Every measurement function receives a `Simulation` (#46)** — `summary_statistic`, `functions=`,
  `post_processor` and a `QoI`'s `compute` — and ModelManager reduces the replicates. PCMM's three monad-level
  statistics are no longer valid `summary_statistic` arguments; the `QoI` builders are the migration path, and the
  monad-level functions stay for monad-level analysis. Every measurement function in PCMM's tests and docs is
  annotated `::Simulation`: ModelManager warns when it is absent, because an untyped monad-level statistic returns
  a different number rather than erroring, and `mseDistance` treats absent keys as zero with one warning.
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
- **`populationCountQoI` returns a `QoI`** — the existing closure wrapped in `QoI("population_count", …)` rather
  than a rename, now that ModelManager expands a `Dict` return into sink columns and drops a `nothing`. One QoI
  covers every cell type, read from the simulation's own output; it works because the sink never calls `reduce`.
- **GSA labels are `"<qoi name>.<key>"`** and `GSASampling.results` is keyed by label. `gsaLabels` is public in
  ModelManager but not exported, and `@reexport` forwards exports only, so it needs the `ModelManager.` prefix.
- **`meanPopulationTimeSeriesQoI` is GSA-incompatible.** Its `Dict` clears the key check and each value is then
  refused per label as a `Vector` rather than a `Real`; a `Vector` is deliberately not spread by index (equal
  length is not equal meaning).
- **Key sets come from the model's roster.** Sensitivity analysis requires every parameter set to reduce to the
  same keys, with no fill. PCMM's builders key off `cellTypeToNameDict` of the **initial** snapshot — the roster
  the model defines — so a cell type driven extinct by some parameter set still reports zero. Keying off observed
  cells would have hit the refusal on every sweep that kills a population.
- **Bare cell-type keys in `populationCountQoI`.** Sink columns are namespaced `"<qoi name>.<key>"`, so the
  `count_` prefix (which existed only because the old sink was one flat namespace) is dropped, riding along with
  the compat bump so a stored column is renamed once. No `up.jl` milestone: `postprocessing.db` is ModelManager's
  sink, not PCMM's schema, and a migration could not tell this builder's `count_<x>` columns from a user's own
  `QoI("count_foo")`. Old rows keep the old columns and new rows fill the new ones; `post_processing.md` says so.
- **Anonymous `post_processor`s that store anything are refused** (the derived `anon_N` name changes between
  sessions). The `post_processing.md` examples of that shape are wrapped in a named `QoI`; the
  `function (sim) … return nothing end` examples are untouched because the guard sits after the `isnothing` skip.

**Rejected**
- A typed `PCMMMissingInputFile` for a *selected* rulesets folder holding neither `base_rulesets.csv` nor
  `base_rulesets.xml`: unreachable, because `InputFolder`'s constructor already refuses such a folder.
- Guarding a ragged cell-type roster (a type present in some replicates of a monad but not others). It cannot occur
  without editing files under `data/`, which `best_practices.md` already forbids; the trust boundary sits at the
  data directory, and guarding one tampering route implies guarding them all. A comment at the aggregation site
  records the assumption. (A stale `summary/population_time_series.csv` is not a route: it lives inside one
  simulation's folder, whose config is fixed.)
- Falling back to the last row of `summary/population_time_series.csv` in `finalPopulationCount` when
  `final.xml`/`final.mat` are pruned. `PhysiCellSequence` enumerates only indexed outputs and never `final`, so that
  row is the last full-save interval, not the true end; the fallback would return an earlier time point
  undetectably. If a cache is ever wanted, write one for the final snapshot at run time.

**Traps**
- `PhysiCellVersionTests.jl` restores the original project *after* a download that 401s without a token, so one
  401 silently disabled every later testset, `PhysiCellStudioTests` and `DocstringRefTests` included. The download
  section is wrapped so the restore always runs.
- `PhysiCellStudioTests` only ever passed a nonexistent `fake_python_path`, so the branch where Studio runs and
  exits non-zero had never been exercised. Both branches are now tested.
- The summation-order test input must cross Julia's pairwise-summation blocksize (1024), e.g. `fill(0.1, 1200)`, so
  the divergence follows from the algorithm. Below it, divergence comes from SIMD reassociation, which is
  CPU-dependent — a vector that diverges on an ARM Mac need not diverge on CI — and a random search found nothing.
- A test that prunes a replicate must build a monad nothing else can match. PCMM reuses matching simulations, so
  `Monad(1; n_replicates=3)` was *the same monad* `PopulationTests` builds, which then failed on the missing output.
  The fixture is distinguished by a phase duration no other test uses.
- `PostProcessorQoITests` constructed a `SimulationProcess` by hand and passed it to the then-untyped
  `populationCountQoI` closure, so the suite kept passing against a contract ModelManager had already replaced. An
  untyped measurement function is what lets a stale contract keep looking healthy.

**Open questions**
- **PhysiPKPD inputs.** Deferred deliberately. Needs a design brief covering how dosing schedules are represented,
  where they live under `inputs/`, and how they are varied.
- The `InputFolder` rejection of a rulesets folder with no rules file *is* reachable by ordinary user error and
  raises a bare `ErrorException`; if typed errors for GUI consumption are wanted, it belongs in ModelManager.
- **ModelManager is still moving.** `main` advanced 13 commits during this work and broke two calibration tests
  mid-review; the suite catches drift only where it exercises it.

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
  a rebuild. `clearSimulatorArtifacts` (via `resetDatabase`) deletes them all.
- Legacy `project` and `physicell_commit_hash.txt` are removed by `removeLegacyBuildArtifacts` after the first
  successful compile, not by an `up.jl` milestone: the upgrade is self-healing, since the first run recompiles.
- Executables live in a `pcmm_build/` subfolder PCMM owns, so clearing them needs no name match:
  `clearSimulatorArtifacts` removes the directory and matches each legacy name exactly (`isCompilationArtifact`).
- A build that does not finish deletes the executable it was replacing (`abandonBuild`). The recompile may have
  been forced by changed macros, `force_recompile`, or a dirty tree with the current version's executable still
  present; in the `force_recompile` case the next run would otherwise reuse a binary the user asked to replace.
- The version string is sanitized before it becomes a file name; `VERSION.txt` from a download is not guaranteed tame.
- `make` exiting 0 without producing the executable is a failure return, not an unhandled `mv` error.
- `refreshPhysiCellVersion()` runs as the first statement of `loadCustomCode` — the single funnel for compilation,
  once per sampling, before recording. With the version in the executable name, re-resolving it *is* the guard: a
  moved HEAD changes the name, a dirty tree flips `unreproduciblePhysiCellVersion()`, and the recorded version
  reads the same field. Cost: one `git status --porcelain` per sampling (~30 ms).
- Resolve quietly, report in one line: `resolvePhysiCellVersionID` and `gitDirectoryIsClean` gained `verbose`
  kwargs; the refresh prints `PhysiCell version changed. Now using <info>.` only when the id moved.
- No opt-out: recording the wrong commit hash is corruption, not a preference. A failed compile after a version
  change is safe — the refreshed id is in place but `setupSampling` returns false.
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
  reuses an unrunnable binary (`known_limitations.md`; `force_recompile=true`). For the deferred `-march` work
  (2026-08-05), a march/ISA component in `executableName` is the remaining step.

---

## 2026-08-05 — `-march` selection: investigation only, implementation deferred

`PhysiCellSimulator()` picks `march_flag` as `isRunningOnHPC() ? "x86-64" : "native"`, and `isRunningOnHPC()` is
`which sbatch`. Investigated whether a better check exists; a design brief was written and deliberately shelved.
Nothing implemented. Read this entry before touching `march_flag`.

### The predicate is about scheduler presence, not architecture
The compiled executable is persisted and reused by later sessions, and its cache key (the PhysiCell version, since
2026-08-19) has no ISA or march component. The real question is "will this on-disk binary ever be executed by a
machine that did not build it", which the current session cannot answer:
- Compile on a login node with `useHPC(false)` → `native` bakes in that node's ISA → a later session flips
  `useHPC(true)` and `sbatch` ships the same cached binary to compute nodes.
- Compile inside an allocation on node A → the next array job lands on older node B.

A batch scheduler is precisely the thing that hands a binary to a different machine, so its presence is a good
proxy. Compilation is a plain `run(...)` from the Julia process, never submitted through a scheduler.

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
  `sbatch --wrap="<command>"`, and PBS has no `--wrap` — `qsub` needs a job script on disk. On top of it, `--$k=$v`
  is Slurm long-option syntax applied to every user option (`--output`/`--error`/`--chdir` map to `-o`/`-e`/`-d` on
  PBS and `-o`/`-e`/`-cwd` on LSF), and `defaultJobOptions()`'s `"job-name"`/`"mem"` are Slurm key names. Needs a
  semantic job-options layer, a rename of `sbatch_options`, and a deprecation path (`defaultJobOptions` is public).
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

A ModelManager handoff framed its docs pass as "opportunity, not repair". It is not optional: ModelManager's
`src/tags.jl` exports 17 names, PCMM's `docs/make.jl` uses `checkdocs=:exports` over both modules with no
`warnonly`, and no PCMM `Pages` entry matches `tags.jl`. The build passes only because registered ModelManager
0.8.2 predates `tags.jl`; it goes red when 0.8.3 is cut.

**Decisions**
- **Reachability defines the public API**, not ModelManager's rule ("not underscore-prefixed, so never internal",
  which here would promote ~174 of 177 non-public bindings). A name is public if we tell users how to use it, or
  if it is passed to or returned from a non-internal. Internals do not appear in the docs at all. Run the closure
  to a fixpoint; count types users receive or pass, not types that merely appear in a dispatching method's signature.
- The first-order closure is six names: `AgentDict`, `MonadPopulationTimeSeries`, `SimulationPopulationTimeSeries`,
  `PCMMPCFResult` (documented return types → promote), and `prepareSimulationCommand`,
  `resolvePhysiCellVersionID` (named only in prose → rewrite the prose).
- Stages A–C (docs-only) land now; Stage D (public-API declaration and index cut) is hard-gated on ModelManager
  0.8.3, because registered 0.8.2 has zero `@compat public` and dropping the `Public = false` blocks against it
  would de-render most of ModelManager's API on PCMM's site.

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

**Open questions**
- Whether ModelManager will fold `_resolveVerbosity`'s behaviour into `runCalibration`'s docstring once PCMM drops
  the explicit `@docs` that renders it.

---

## 2026-07-23 — Migrate `src/loader.jl` onto PhysiCellOutput.jl

`src/loader.jl` (~865 lines) duplicated the path-based, stateless loading that now lives in PhysiCellOutput.jl.
PCMM keeps only its database-identity layer.

**Decisions**
- Preserve the API via extension (`PCMM_MIGRATION.md` §5), not a PCMM-owned wrapper type (§4): the only internal
  callers are `src/analysis/*.jl`, heavily typed on the concrete `PhysiCellSnapshot`/`PhysiCellSequence` types and
  reading their fields; a wrapper must not subtype `AbstractPhysiCellSequence` and would rename the public
  constructors, so §4 is the more invasive option here. Id-based constructors return the real PhysiCellOutput
  objects. The piracy is confined to one file and tolerable because PCMM is the terminal application in the stack.
- `assertInitialized()` stays at PCMM's id-based entry points; PhysiCellOutput does not assert.
- PhysiCellOutput's `PhysiCellSequence` has no `simulation_id`, so the three sequence-typed builders that stamp
  results with it (`SimulationPopulationTimeSeries`, `AverageSubstrateTimeSeries`,
  `ExtracellularSubstrateTimeSeries`) receive the id threaded from the entry point.
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
- New file `src/analysis/post_processor_qois.jl`, separate from `standard_qois.jl` (a different consumer); the
  keyword convention mirrors `endpointPopulationCounts`.
- Returns a `Dict`, not a `NamedTuple`: cell type names can contain spaces, which are not valid field names. (The
  `count_` key prefix chosen here was dropped on 2026-09-02.)
- A missing snapshot (e.g. pruned) → the builder returns `nothing` so no QoI is recorded, matching the "prefer
  `nothing` for the no-data case" guidance.

---

## 2026-07-08 — Docs for batch `run(Vector)` and the calibration evaluation budget (D5/D6)

Third handoff from the ModelManager session; both changes are inherited via `@reexport`, so this is doc-only.

**Decisions**
- `max_evaluations` is documented as current behaviour (cap applied before each batch, final generation may be
  partial), with a callout that the budget counts particles, so a calibration launches up to
  `max_evaluations × n_replicates` simulations. Verified against `_capBatchToBudget`.
- Batching pre-built trials lives in `examples.md` (PCMM has no `running_simulations.md`), linking to *Your first
  project*, which already documents `PCMM_NUM_PARALLEL_SIMS`.
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
  repo's actual `up.jl` is exercised. `.github/workflows/UpgradeCI.yml`, same triggers as `CI.yml`; scripts under
  `test/upgrade/` parameterized by `PCMM_UPGRADE_SOURCE_VERSION`; verification reads SQLite directly.
- Matrix: `0.1.7` (the version a real user is on; crosses the `0.2.0` par_key rewrite and `0.3.0`) and `0.2.2`
  (isolates the `0.3.0` hop). The generation API is unchanged across both tags, so one `generate.jl` serves.
  `verify.jl` asserts the `par_key` column when `0.2.0` is crossed.
- Early hops assert data preservation, not migration-specific deltas (`upgradeToV0_3_0`'s `calibrations` table is
  also created by `initializeDatabase`). `< 0.1.0` was `pcvct`; `0.0.1`/`0.0.2` were never released, so
  `pcvct@0.0.3` is the floor.
- The first run caught a shipping bug: `upgradeToV0_2_0` called `validateParsBytes` unqualified after the
  modularization moved it, unexported, into ModelManager, so every `0.1.7` upgrade threw and rolled back. Fixed by
  adding it to `up.jl`'s explicit `using ModelManager:` import.

**Rejected**
- Generate@0.0.3 → upgrade@0.0.10 (released): tests released migration code, not the repo's.
- A `target_version` cap on `initializeModelManager`: `upgradePackage` always upgrades to the runtime version, and
  adding a cap is a ModelManager change.

**Open questions**
- How far back the generation API can be reused; the `pcvct` era will likely need an older script.
- Whether `pcvct@0.0.3` stamps a version table the newer code can read.

---

## 2026-06-12 — Documentation restructure for clarity & discoverability

Users repeatedly asked how to use PCMM. The docs were accurate but a flat 17-item manual in arbitrary order, a
34-page alphabetical API dump, and a getting-started page that buried the happy path under `importProject`.

**Decisions**
- Sidebar regrouped by user intent; getting-started split into `installation.md`, `julia_environments.md` (new),
  `getting_started.md` (*Your first project*, happy path only) and `importing_projects.md`; new `examples.md`
  cookbook hub; `index.md` as a hub with a "Where do I look?" table.
- API reference grouped by code family, hand-maintained, with the alphabetical Index kept for name lookup.
- Colliding section refs resolved with explicit `@id`s (`examples_cookbook`, `calibration_section_man`); the
  XML-path-helpers H1 renamed to match its sidebar label. Docs-only: no PRD entry, no README row.

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

If the native Julia ABC-SMC implementation proves non-functional or needs a side-by-side comparison, the last commit with the fully-wired PythonCall/pyabc backend is the tip of the `feature-par-naming` branch at the point of the merge into `feature/julia-native-abc`:

- **Commit:** `9d9dda07aa1464db02a9aeb1d0171d3f32db15f0`
- **Subject:** "Merge branch 'main' into feature-par-naming"
- **Last substantive pyabc change:** commit `2d575527` ("Refactor calibration integration from PyCall to PythonCall")

To restore the working pyabc state: `git checkout 9d9dda07aa1464db02a9aeb1d0171d3f32db15f0 -- ext/PCMMCalibrationExt.jl CondaPkg.toml Project.toml src/calibration/` (adjust paths as needed) or branch from that commit directly.

---

## 2026-04-25 — PCMM side of SimulationSpec flatten / setup-collect split

Counterpart to the ModelManager refactor of the same date; see ModelManager's `progress.md` for the rationale.

**Decisions**
- `setupSampling` accepts `AbstractSampling`; `setupMonad` accepts `AbstractMonad` and loses its `do_full_setup`
  kwarg, since `setupSampling` always runs first and covers compilation.
- `runSimulation` drops the `ismissing(spec.monad_id)` branch (`monad_id` is always `Int`);
  `prepareSimulationCommand` drops `do_full_setup` and is `(simulation, monad_id, force_recompile)`.

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
- The per-simulation "Running simulation: N..." line, lost in modularization, is restored inside the `@task` body
  in ModelManager's `run` so it prints when the simulation starts, gated by `quiet`.

**Rejected**
- A separate `dispatchSimulation(::AbstractSimulationSpec)` stub: redundant with simulator dispatch for one spec
  type per simulator, and by spec time all simulator-specific routing is done.

---

## 2026-04-22 — Julia-native ABC-SMC (replacing pyabc)

The pyabc backend (PythonCall/CondaPkg) worked but carried conda environment management, a `SingleCoreSampler`
constraint (Julia closures cannot be pickled), and a deep bridge.

**Decisions**
- Implement ABC-SMC directly (~250 lines, Toni et al. 2009 / Beaumont et al. 2009), no new dependencies, on PCMM's
  Monad/runner infrastructure.
- Framework-agnostic core: `abc_smc.jl` operates on an `evaluate_particle(params) → (distance, metadata)`
  callback; PhysiCell wiring is isolated in `abc.jl`, so the core can move to ModelManager.
- `AbstractCalibrationMethod` supertype with `ABCSMC` as the first subtype; `runCalibration` dispatches on it and
  `runABC` is the keyword convenience.
- No warm-start from existing simulations: seeding generation 1 biases it away from the prior.
  `Monad(...; use_previous=true)` still reuses exact-match points transparently.
- The pyabc extension is reduced to a `Base.depwarn` stub now and deleted once native is confirmed.
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
