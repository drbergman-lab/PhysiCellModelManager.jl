# Product Requirements Document — PhysiCellModelManager.jl (PCMM)

> **Purpose:** This document defines the complete feature set of PCMM in behavioral terms. It is the authoritative answer to "what should this system do?" Read this at the start of any feature session to establish alignment between intent and implementation plan.

---

## Product Overview

**Vision:** PCMM eliminates manual file I/O and workflow overhead in PhysiCell agent-based modeling studies. It manages simulation runs and their provenance in a structured database, enabling reproducible parameter exploration, sensitivity analysis, and calibration with minimal boilerplate.

**Target Framework:** PhysiCell only. Generalization to other ABM frameworks is explicitly deferred to v2.

**Business Objectives:**
1. Reduce time spent on manual file management and simulation bookkeeping.
2. Enable reproducible workflows that collaborators and reviewers can re-run and validate.
3. Lower the barrier to structured parameter studies, sensitivity analysis, and calibration.

**Quality Success Metrics (no user telemetry):**
- Test pass rate on all supported platforms (macOS, Linux, Windows).
- Number of reproducible end-to-end tutorial workflows available.
- Failure isolation rate in batch campaigns: a single failed simulation must not halt remaining queued runs.

---

## User Personas

### Persona 1: Research Lead
- **Role:** PI or senior researcher running a computational biology lab.
- **Technical proficiency:** High — comfortable with Julia, PhysiCell, and HPC environments.
- **Goals:** Reproducible simulation workflows; publication-quality data generation; model calibration to experimental data.
- **Pain points:** Managing hundreds of output files manually; avoiding duplicate runs; linking simulation batches to analysis code.
- **Key flow:** Import project → define variation → run campaign → sensitivity analysis → calibrate to data.

### Persona 2: Research Trainee
- **Role:** PhD student, undergraduate, or advanced high-school researcher in the lab.
- **Technical proficiency:** Variable — may be new to Julia and PhysiCell.
- **Goals:** Run guided parameter studies; visualize outputs quickly; identify which parameters matter.
- **Pain points:** Manual PhysiCell setup; not knowing which outputs to analyze; file path errors.
- **Key flow:** Import project (via wizard when available) → run a grid search → inspect population time series → share results.

---

## Feature: Project Initialization

**One-line description:** Create and configure a PCMM project in a user-chosen directory.

**Priority:** Must-have

**Behavioral specification:**
- `createProject(path)` initializes a PCMM project folder with the canonical subdirectory layout and an SQLite database.
- `initializeModelManager(path)` connects an existing PCMM project to the current Julia session; sets module-level globals.
- After initialization, all subsequent PCMM calls operate relative to that project root.
- `using PhysiCellModelManager` registers the module globals and then auto-initializes from the working directory. Whenever that succeeds — and therefore whenever the globals change — the initialization banner is printed.
- Loading the package does **not** auto-initialize while Julia is generating a precompilation cache file or a system image.

**Acceptance criteria:**
- A fresh directory becomes a valid project after one `createProject` call.
- Re-initializing an already-initialized project does not corrupt the database.
- `databaseDiagnostics()` passes with no errors after initialization.
- A redundant `__init__` in a process that already initialized a PCMM project is a no-op: the existing globals object and database handle are kept, not rebuilt.
- Precompiling a package that depends on PCMM emits no banner and touches no project database.

**Edge cases:**
- Path does not exist → create it.
- Path already contains a PCMM database → re-attach, do not reinitialize.
- Called without any path → use current working directory.
- Another ModelManager backend already owns `mm_globals_ref` → PCMM claims it and registers its own `PhysiCellSimulator`, rather than deferring and then running against a foreign simulator. (`ModelManagerGlobals` holds exactly one `simulator`, so the two backends cannot coexist in one process; the last one loaded wins.)
- Loaded inside a precompilation subprocess → globals are registered (cheap, in-process) but no project is initialized, so `mm_globals()` still works for any downstream precompilation workload.
- An **unselected** (`""`) optional input folder → `prepareBaseFile` returns `nothing`, for every location including `:rulesets_collection`. Nothing is generated and no error is raised, because there is no folder to prepare.
- A **selected** `:rulesets_collection` folder containing neither `base_rulesets.csv` nor `base_rulesets.xml` is rejected by `InputFolder` construction, before `prepareBaseFile` runs. PCMM adds no second check for it.

---

## Feature: Model Import

**One-line description:** Import a PhysiCell project folder into PCMM's input management system.

**Priority:** Must-have

**User story:** As a researcher, I want to import a PhysiCell project so that I can use PCMM tooling for parameter sweeps, analysis, and calibration without managing file I/O or simulation bookkeeping manually.

**Behavioral specification:**
- `importProject(path)` copies config, custom modules, rulesets, and IC files into PCMM's versioned `inputs/` tree.
- Returns the folder names assigned to each input type (config, custom code, rules, IC cell, IC ECM).
- `InputFolders` struct ties those names together for use in downstream calls.

**Acceptance criteria:**
- After import, the copied files are reachable through `InputFolders`.
- Import is idempotent: re-importing the same folder produces the same folder name.

**Edge cases:**
- Missing optional input types (rules, IC files) → omit from `InputFolders` gracefully.
- Source folder has no XML config → error with descriptive message.

---

## Feature: Model Import Wizard

**One-line description:** Support the model import process with an interactive GUI that guides users through selecting input folders and validating their contents.

**Priority:** Could-have

**Behavioral specification:**
- update `importProject(path)` to launch a GUI; use `importProject(path; interactive=false)` to retain CLI behavior.
- GUI prompts user to select folders all available input types in a table of `| Input Type | File Path | Browse Button | Destination | Status |` rows.
- For each input type, user clicks "Browse" to select the corresponding folder; PCMM validates the selection (e.g., config folder must contain an XML file).
  - Destination column shows the assigned folder name in `inputs/` after successful validation.
    - This defaults to the name of the subdirectory of `user_projects/` that was selected (if on the path) or a sanitized version of the input type (e.g., "config" → "config_1").
    - If the destination folder already exists in `inputs/`, the wizard will skip copying and use the existing folder, but show a warning in the "Status" column.
  - Validation status is shown in the "Status" column (e.g., "Valid", "Missing XML", "File not found").
    - green if valid, yellow if warning (e.g., destination folder already exists), red if invalid.
- Only after all required inputs are valid can the user click "Import" to perform the copying and finalize the import process.
- After import, shows the code snippet to access the imported folders via `InputFolders` and a button to copy it to clipboard.

---

## Feature: Parameter Variation

**One-line description:** Specify multi-dimensional parameter sweeps over PhysiCell XML config values.

**Priority:** Must-have

**User story:** As a researcher, I want to run structured parameter variations so that I can understand how input parameters affect model outputs such as cell counts, time series, and spatial metrics.

**Behavioral specification:**
- `DiscreteVariation(xml_path, values)` — explicit list of values for one parameter.
- `GridVariation()` — a method singleton, passed as the *leading* argument to `createTrial`/`run` to take the full Cartesian product of the variations that follow. It is the default, so it is usually omitted.
- `LHSVariation`, `SobolVariation`, `RBDVariation` — space-filling designs over continuous ranges.
- `DistributedVariation` — sample from a probability distribution.
- `LatentVariation` — parameterize one or more XML paths through one or more latent parameters (each a value vector or a distribution) via user-supplied maps.
- `CoVariation` — link multiple parameters so they vary together.
- Variation objects accept an optional `name` field for user-defined display names in parameter DataFrames and sensitivity scheme outputs.
- If `name` is omitted, defaults follow `shortVariationName` conventions based on location + target XML path.
- Variations are passed to `run()` to generate a `Monad`/`Sampling`/`Trial` hierarchy.

**Acceptance criteria:**
- A `GridVariation` over N×M discrete values produces exactly N×M distinct `Monad`s.
- `xml_path` helpers (`configPath`, `behaviorPath`, etc.) produce valid XPath-like strings accepted by variation constructors.
- Sensitivity scheme CSV/DataFrame headers use variation names (user-specified when present; convention-based defaults otherwise).

**Edge cases:**
- Duplicate parameter paths in a single variation → error.
- LHS/Sobol/RBD with n_samples=0 → error.

---

## Feature: Simulation Execution

**One-line description:** Compile and run PhysiCell simulations, locally or on an HPC cluster.

**Priority:** Must-have

**Behavioral specification:**
- `run(inputs; n_replicates=1)` runs a single parameter point with replication.
- `run(inputs, variation; n_replicates=N)` sweeps over all variation points.
- Local execution: spawns PhysiCell subprocesses, up to `setNumberOfParallelSims` (or `PCMM_NUM_PARALLEL_SIMS`) at a time.
- HPC execution: PCMM supplies the simulation command via `simulationCommand`; ModelManager submits it (`sbatch --wrap`, no script file is written) and detects completion with a filesystem sentinel. PBS/`qsub` support is deferred — see the `-march` to-do in CLAUDE.md.
- PCMM adds one SLURM default of its own at initialization: `cpus-per-task` resolves per simulation to that simulation's `parallel/omp_num_threads` (so a varied thread count is honoured), because PhysiCell starts that many threads regardless of what SLURM allocated. It is not installed when the user has already set `cpus-per-task`; a config whose element cannot be read falls back to 1 with one warning.
- A submission `sbatch` refuses is ModelManager's to handle (retried when transient, otherwise the run stops with the scheduler's message); it is never recorded as a failed PhysiCell simulation.
- Returns an `MMOutput` (alias `PCMMOutput`) wrapping the trial object, with the counts of simulations scheduled and completed.

**Acceptance criteria:**
- Completed simulations write PhysiCell output to the folder `pathToOutputFolder` returns — `data/outputs/simulations/<simulation_id>/output/` — with `output.log`/`output.err` beside it in the simulation folder. Use the accessor rather than the literal path; the layout is ModelManager's.
- Database records each simulation with status (queued / running / completed / failed).
- Rerunning an already-completed simulation with identical inputs is a no-op.
- The compiled executable is named for the PhysiCell version it was built against (`pcmm_build/project_<physicell-version>` inside the custom code folder), and its presence is the only record that a build for that version succeeded. Recompilation happens when that file is absent, when the required macros differ from those recorded by the last successful compilation, or when the PhysiCell version cannot be pinned down (a dirty or downloaded PhysiCell).
- The PhysiCell version is re-resolved from disk before every compilation, not only at initialization. A PhysiCell that is pulled, checked out, or edited mid-session is compiled for — and recorded as — what it is at that moment, with no restart required.

**Edge cases:**
- PhysiCell binary not compiled → error with instructions.
- Simulation process exits non-zero → mark as failed in database, do not crash caller.
- `n_replicates` < 0 → `AssertionError`. Zero is legal: it registers the monad without launching simulations, which is what the calibration reference-monad idiom relies on.
- Compilation fails → the run fails, and nothing is left that a later run could read as a finished build: any executable for this PhysiCell version is deleted, including one that predated this compilation, and the macros file is left as the last successful compilation wrote it. The next run recompiles instead of reusing a stale executable. `compilation.log` / `compilation.err` are left in place for inspection.
- Compilation reports success but produces no executable → treated as a failure.
- A `data/` folder is moved to a machine with a different OS, architecture, or compiler → **not** detected; the executable name carries no ISA component. See [Known limitations](docs/src/man/known_limitations.md).
- PhysiCell changes mid-session → detected at the next compilation. The check runs once per sampling, so a `Trial` spanning several samplings can straddle two PhysiCell versions; each sampling records the version it was actually built against.

---

## Feature: Simulation Output Loading

**One-line description:** Load PhysiCell simulation output (cells, substrates, mesh, attachment/spring/neighbor graphs) into Julia objects, addressable by simulation ID.

**Priority:** Must-have

**Behavioral specification:**
- Path-based loading is provided by the external **PhysiCellOutput.jl** package (re-exported): `PhysiCellSnapshot`, `PhysiCellSequence`, `AbstractPhysiCellSequence`, `cellDataSequence`, `cellLabels`, `cellTypeToNameDict`, `substrateNames`, `loadCells!`, `loadSubstrates!`, `loadMesh!`, `loadGraph!`, `pathToOutputFileBase`, `pathToOutputXML`, `AgentID`, `AgentDict`.
- PCMM adds database-identity entry points on top of these: the same functions accept a `simulation_id::Integer` or a `Simulation`, converting to an output folder via `pathToOutputFolder` before delegating to PhysiCellOutput. Examples: `PhysiCellSnapshot(sim_id, index; include_cells=true)`, `PhysiCellSequence(simulation)`, `cellDataSequence(sim_id, ["position", "total_volume"])`.
- `include_*` keyword arguments (`include_cells`, `include_substrates`, `include_mesh`, `include_attachments`, `include_spring_attachments`, `include_neighbors`) control eager loading; omitted data can be loaded later with the `load*!` mutators.

**Acceptance criteria:**
- The id-/`Simulation`-based API behaves identically to the pre-migration in-repo loader for all existing callers and tests.
- Loaded values match the raw PhysiCell `.mat`/`.xml` output.

**Edge cases:**
- Missing output file (e.g. a pruned simulation) → returns `missing` with a printed message rather than throwing.
- A project must be initialized before id-based loading; PCMM's entry points call `assertInitialized()` first so the error is clear.
- Zero-cell snapshots load correctly (relies on `MAT ≥ 0.12.1`).

---

## Feature: Analysis — Population Dynamics

**One-line description:** Compute cell population counts and time series from completed simulations.

**Priority:** Must-have

**Behavioral specification:**
- `finalPopulationCount(sim_id)` → `Dict{String,Int}` of cell type → count at final time point.
- `finalPopulationCount(monad)` → `Dict{String,Float64}` averaged across replicates.
- `populationTimeSeries(sim_id)` → time-indexed counts per cell type.
- `meanPopulationTimeSeries(monad_id)` → mean time series across replicates.
- `populationCount(sim_id, t)` → counts at a specific time point.
- All functions accept `include_dead=true` to include dead cells.
- Replicates whose output is no longer on disk (deleted or pruned) are **excluded** from monad-level aggregates, and their exclusion is reported once per call site with `@info ... maxlog=1`. Pruning is a deliberate user action, so this is informational, not a warning.
- Plot recipes are provided for `Simulation`, `Monad`, `Sampling`, `Trial`, `run` results, and `plotbycelltype`. The manual shows rendered figures for three of these — the per-monad, per-cell-type, and single-simulation plots — generated by `docs/generate_figures.jl`; the rest are described in prose.

**Acceptance criteria:**
- Results match values read directly from PhysiCell SVG/output files.
- Empty monad (no simulations) → error, not silent zero.
- A monad with some replicates' output removed still returns a value, computed over the survivors, and says so once.
- The user manual displays at least one rendered figure per plot recipe.

**Edge cases:**
- Simulation has no output files → error with simulation ID.
- Requested cell type not present in output → return 0 / empty entry.
- `include_dead=false` is default; dead cells excluded from all counts unless specified.
- Replicates of a monad are **assumed** to declare the same cell-type roster, because they share a config and the roster is read from the output XML. PCMM does not verify this: producing a ragged roster requires editing files inside the data directory, which `best_practices.md` already forbids, and PCMM trusts its own data directory rather than guarding each way a user could corrupt it by hand.
- A monad-level plot with some replicates' output removed averages over the survivors only; the removed replicates are not counted in the denominator.
- Pruning degrades the analysis functions asymmetrically, and this is accepted: `meanPopulationTimeSeries` reads a `summary/population_time_series.csv` cache that survives any prune, while `finalPopulationCount` reads `final.xml`/`final.mat` and has no cache. `finalPopulationCount` does **not** fall back to the time series' last row — that row is the last full-save interval, not the simulation's true end, so the substitution would be undetectable.

---

## Feature: Sensitivity Analysis

**One-line description:** Compute global sensitivity indices (Sobol, RBD-FAST) linking parameters to simulation outputs.

**Priority:** Must-have

**Behavioral specification:**
- User constructs a `SobolVariation` or `RBDVariation`, runs simulations, then calls sensitivity analysis functions.
- Returns first- and total-order Sobol indices (or FAST indices) per parameter.

**Acceptance criteria:**
- Sensitivity indices sum to approximately 1 for well-behaved models.
- Results are reproducible given the same seed.

**Edge cases:**
- Fewer samples than recommended for reliable indices → warn.
- Output quantity is constant across all runs → indices are all zero, no error.

---

## Feature: Calibration Summary Statistics

**One-line description:** PhysiCell-specific summary statistics for use with ModelManager's `CalibrationProblem`.

**Priority:** Must-have

**Behavioral specification:**
- All calibration infrastructure (ABC-SMC algorithm, `CalibrationProblem`, `runABC`, `resumeABC`, kernels, posterior visualization) lives in ModelManager. PCMM contributes only the PhysiCell-specific measurements passed as `summary_statistic` in a `CalibrationProblem`.
- **A summary statistic measures one simulation.** Since ModelManager 0.9 every measurement function — `summary_statistic`, sensitivity analysis's `functions=`, a `post_processor`, a `QoI`'s `compute` — receives a `Simulation`, and ModelManager reduces a parameter set's replicates. The three monad-level functions below take a monad ID and are therefore **no longer valid `summary_statistic` arguments**; the `QoI` builders are that role's replacement. The monad-level functions remain supported for direct monad-level analysis.
- `endpointPopulationCounts(monad_id; cell_types, include_dead)` → `Dict{String,Float64}` mapping cell type → mean final count across replicates. Returns `missing` if no simulation output is available.
- `endpointPopulationFractions(monad_id; cell_types, include_dead)` → `Dict{String,Float64}` mapping cell type → mean fraction of total live cells. Returns `missing` if no output available.
- `meanPopulationTimeSeries(monad_id; cell_types, include_dead)` → `Dict{String,Vector{Float64}}` mapping cell type → mean count over time across replicates.
- Each statistic also has a builder returning a single `QoI` — `endpointPopulationCountQoI`, `endpointPopulationFractionQoI`, `meanPopulationTimeSeriesQoI` — whose value is a `Dict` keyed by cell type, the same shape as the monad-level statistic, so `observed_data` does not change. A single QoI's value is passed through unwrapped by ModelManager, which is what keeps that dict flat for `mseDistance`.
- `cell_types` is optional: omitted, the builder measures every cell type in the output, exactly as the monad-level function does.
- From ModelManager 0.9.1, sensitivity analysis spreads a `Dict`-valued measurement into one analysis per key, labelled `<qoi name>.<key>` and retrieved from `results` by that label (`gsaLabels` lists them). So `endpointPopulationCountQoI` and `endpointPopulationFractionQoI` serve all three consumers. Two builders do not: `meanPopulationTimeSeriesQoI`, because a `Vector` is deliberately not spread by index (equal length is not equal meaning), and `populationCountQoI`, because it defines no `reduce` and the default `mean` cannot combine a vector of `Dict`s.
- Sensitivity analysis requires every parameter set in a design to reduce to the *same* keys. PCMM's builders satisfy this by construction: the key set is the model's own cell-type roster from the snapshot metadata, not the set of types with living cells, so a type driven extinct by some parameter set still reports zero rather than dropping its key.
- **Which builder reaches which consumer.** `endpointPopulationCountQoI` and `endpointPopulationFractionQoI` reach all three (calibration, the post-processing sink, sensitivity analysis). `meanPopulationTimeSeriesQoI` reaches calibration only: its `compute` returns a `SimulationPopulationTimeSeries`, which is not a scalar, `NamedTuple` or `AbstractDict` and so cannot be stored by the sink, and its `reduce` yields vectors, which GSA does not spread by index.
- **`cell_types` is applied by `compute`, not only by `reduce`.** The sink calls `compute` and never `reduce`, so a builder filtering in its reducer alone would write a column per cell type and silently ignore the argument. For fractions the denominator is still every live cell: the total is summed before the restriction, matching `endpointPopulationFractions`.
- Future PhysiCell-specific statistics (spatial metrics, intracellular state distributions, etc.) would be added here.

**Acceptance criteria:**
- `endpointPopulationCounts(monad_id)` returns a `Dict{String,Float64}` for a monad with completed simulations.
- `endpointPopulationCounts` returns `missing` gracefully when simulation output files are absent.
- Fractions sum to 1.0 (within floating-point tolerance) when `include_dead=false`.
- `cell_types` filter restricts output to only the requested types.

**Edge cases:**
- All replicates in a monad have missing output → return `missing`, not an error.
- `cell_types` filter names a type not present in the simulation → entry is omitted from result.
- Some replicates missing output → averaged over the survivors, reported once via `@info ... maxlog=1`. `maxlog` is required: calibration evaluates these once per monad across thousands of particles.
- A builder must return **exactly** what its monad-level counterpart returns, asserted with `==` rather than `isapprox`. The three statistics disagree with one another about whether an absent cell type is zero-filled and about summation order, so each builder carries its own reducer; a shared one would silently change results. The one deliberate difference: where every replicate is missing, `meanPopulationTimeSeriesQoI` returns `missing` while `meanPopulationTimeSeries` raises a `KeyError`.

---

## Feature: Database Management

**One-line description:** Maintain an SQLite database recording all simulations, variations, and their relationships.

**Priority:** Must-have

**Behavioral specification:**
- Schema is created on `createProject` and migrated forward on `initializeModelManager` via `src/up.jl`.
- Every simulation, monad, sampling, and trial is assigned a stable integer ID.
- `databaseDiagnostics()` validates referential integrity.

**Acceptance criteria:**
- No orphaned records after normal use.
- `up.jl` migrations are idempotent.
- Migrations are exercised end-to-end in CI: a project created by an older released version can be opened by a newer version with `auto_upgrade=true` without data loss (see *Upgrade-path CI* below).

**Edge cases:**
- Schema version mismatch → migrate up, never silently corrupt.
- Database file locked by another process → error with message, not silent hang.

### Sub-feature: Upgrade-path CI

**One-line description:** A dedicated GitHub Actions workflow that replays real version history — generate a project with an older *released* package version, then upgrade it with a newer version — to guard `src/up.jl` against regressions.

**Why a separate workflow:** the test needs two different package versions present (one to write legacy data, one to upgrade it), which cannot coexist inside a single `Pkg.test()` environment. It runs on the same triggers as `CI.yml`.

**Behavioral specification:**
- A *generation* step installs a pinned older release in an isolated environment and produces a real `data/` project (DB + simulation outputs) stamped at that older version.
- An *upgrade + verify* step opens that same project with the **dev checkout** (`auto_upgrade=true`), which runs every `src/up.jl` milestone between the source version and dev `HEAD`, then asserts data integrity directly against the SQLite database.
- The source version is a single parameter (a CI matrix entry) so the upgrade history can be "walked back" incrementally. The primary target is `0.1.7` → `HEAD` (the oldest version a real user is currently on; crosses the `0.2.0` par_key rewrite and `0.3.0`), with `0.2.2` → `HEAD` kept to isolate the `0.3.0` hop. Eventual target: back to the oldest installable release `pcvct@0.0.3`.

**Acceptance criteria:**
- After upgrade, `simulations` / `monads` / `samplings` row counts equal the pre-upgrade snapshot (no data loss).
- The version table is stamped with the dev `HEAD` version.
- Output folders referenced by surviving simulations still exist on disk.
- The upgrade completes without error crossing each milestone in range.

**Edge cases / notes:**
- Versions `< 0.1.0` were published under the package name `pcvct` (UUID `3c374bc7…`); `≥ 0.1.0` under `PhysiCellModelManager` (UUID `7582d1aa…`). The harness derives the package name from the source version. `0.0.1`/`0.0.2` were never released, so `pcvct@0.0.3` is the floor.
- Some milestone effects are also produced by normal `initializeDatabase` (e.g. `upgradeToV0_3_0`'s `calibrations` table), so the primary guarantee of the early hops is data preservation, not migration-specific schema deltas; the latter become testable as the source version moves back through data-transforming milestones (`upgradeToV0_2_0`, the `vct.db`→`pcmm.db` rename, etc.).

---

## Feature: Export & Pruning

**One-line description:** Export simulation outputs to portable formats and prune redundant data.

**Priority:** Must-have (core); Should-have (polish and additional visualization tools)

**Behavioral specification:**
- `exportSimulation(sim, dest)` copies output files to a named destination folder.
- `pruner` removes intermediate output snapshots to reduce disk usage while retaining final state.

**Acceptance criteria:**
- Exported folder is self-contained (no references back to PCMM database).
- Pruning does not delete the final time-point output.

**Edge cases:**
- Destination folder already exists → error or overwrite depending on flag.
- Pruning a not-yet-completed simulation → error.

---

## Feature: Movie Generation

**One-line description:** Render a simulation's SVG snapshots into a movie via the PhysiCell Makefile's `jpeg`/`movie` targets.

**Priority:** Should-have

**Behavioral specification:**
- `makeMovie(simulation_id)` invokes `make jpeg` then `make movie` in `physicellDir()`, deletes the intermediate JPEGs, and leaves `out.mp4` in the simulation's output folder.
- `makeMovie(T::AbstractTrial)` / `makeMovie(out::PCMMOutput)` batch this over every simulation in the trial/output.
- `makeMovie(simulation_ids::AbstractVector{<:Integer})` (e.g. `makeMovie(4:7)`) and `makeMovie(Ts::AbstractVector{<:AbstractTrial})` (e.g. `makeMovie(Simulation.(4:7))`) batch over an explicit collection; the trial-vector form flattens to IDs via `simulationIDs`.
- Keyword arguments `framerate`, `magick_density`, `magick_resize_x`, `magick_resize_y` forward directly to the Makefile's `FRAMERATE`, `MAGICK_DENSITY`, `MAGICK_RESIZE_X`, `MAGICK_RESIZE_Y` variables (`movie`/`jpeg` targets respectively). Each defaults to `missing`, in which case the Makefile's own default for that variable is used unchanged.
- `magick_path`/`ffmpeg_path` locate the ImageMagick/FFmpeg executables; `verbose` prints the underlying `make` command output.

**Acceptance criteria:**
- Omitting the new framerate/density/resize keywords reproduces the exact previous behavior (Makefile defaults).
- Passing any of the four keywords changes the corresponding `make` invocation's variable assignment and is reflected in the produced movie.
- Re-running `makeMovie` when `out.mp4` already exists is a no-op (`false` return), regardless of these keywords.

**Edge cases:**
- No `s*.svg` files in the output folder → warn and skip (`false` return), independent of these keywords.
- ImageMagick or FFmpeg not discoverable on `PATH` → throws `ErrorException`.

---

## Feature: Post-Processing Hook & Quantities of Interest

**One-line description:** Let users compute per-simulation quantities of interest (QoIs) from intact output via a `post_processor` callback, and guarantee that PCMM's destructive pruning runs only after that callback.

**Priority:** Must-have (hook ordering guarantee); Should-have (ready-made QoI builders — implemented).

**Background:** ModelManager runs three per-simulation post steps in order:
`postSimulationProcessing` (non-destructive) → user `post_processor` (successful sims only) → `postSimulationCleanup` (destructive). PCMM implements the destructive step (err-file handling + `pruneSimulationOutput`) as `postSimulationCleanup` so a `post_processor` always reads an un-pruned output folder. `postSimulationProcessing` is left as ModelManager's no-op default.

**Behavioral specification:**
- `run(T; post_processor = f)` calls the callback once per successful simulation, after the simulation finishes and before pruning.
- The callback receives a `Simulation` — the same argument a `QoI`'s `compute` gets, since ModelManager 0.9 made one contract of every measurement function. Most loader and analysis functions take it directly; `simulationID(sim)` and `pathToOutputFolder(sim)` give the ID and the folder.
- Return patterns: `nothing` (side effects only — must be explicit), a bare scalar (`Real`/`Bool`/`String`, stored under the QoI's own name), or a `NamedTuple`/`Dict` of `name => scalar`. Non-scalar returns throw `ArgumentError` (ModelManager-side).
- From ModelManager 0.9.1 a spread return writes one column per key named `<qoi name>.<key>`, and a callback that stores anything must therefore carry a stable name — an anonymous `sim -> …` is refused, since its derived name varies between sessions. Wrap it in a `QoI` or pass a named function; a callback returning `nothing` is unaffected.
- Stored QoIs land in `data/outputs/postprocessing.db`; read back with `postProcessingTable(T)` or `simulationsTable(T; post_processing=true)`.
- **QoI builder:** `populationCountQoI(; index=:final, cell_types=nothing, include_dead=false)` returns a ready-made `post_processor` recording one `population_count.<cell_type>` column per cell type, read from the snapshot at `index` (`:final`, `:initial`, or an integer snapshot index). The key is the bare cell type: ModelManager 0.9.1 supplies the namespace, so the `count_` prefix the builder used to carry would only produce `population_count.count_<cell_type>`.

**Acceptance criteria:**
- A `post_processor` reading `pathToOutputFolder(sim)` sees output files present; those files are pruned only after it returns.
- A run without `post_processor` prunes exactly as before (no regression).
- `postSimulationCleanup` runs for every completed simulation, including failures.
- `populationCountQoI()` matches `finalPopulationCount` at the default `:final` index and `populationCount` at any integer index; an optional `cell_types` filter restricts which cell types are recorded. Its sink columns are `population_count.<cell_type>`.

**Edge cases:**
- Callback on a failed simulation → not called (successful sims only); cleanup still runs.
- Callback returns a non-scalar → `ArgumentError`.
- Anonymous callback returns something storable → `ArgumentError` (ModelManager 0.9.1), because every column is named after its QoI and a derived name is not stable across sessions. Returning `nothing` is unaffected.
- Un-updated PCMM against reordered ModelManager → still prunes, but in the earlier hook, so a `post_processor` would see already-pruned output. Task A removes this gap.
- `populationCountQoI`'s requested snapshot doesn't exist (e.g. pruned) → returns `nothing` for that simulation instead of throwing.

---

## Feature: PhysiCell Studio Integration

**One-line description:** Launch PhysiCell Studio against a completed simulation's output for interactive inspection.

**Priority:** Should-have

**Behavioral specification:**
- `runStudio(simulation_id | Simulation | PCMMOutput{Simulation})` writes temporary config and rules files into the simulation's output folder, launches Studio, and removes the temporary files afterwards.
- The Python interpreter and Studio directory come from `PCMM_PYTHON_PATH` / `PCMM_STUDIO_PATH`, or from the `python_path` / `studio_path` keywords, which are then remembered for the session.
- The intent is visualization of results, not modification of the simulation.

**Acceptance criteria:**
- Temporary files are cleaned up whether or not the launch succeeds.
- A launch failure raises a typed PCMM error carrying the command and the underlying cause.

**Edge cases:**
- `python_path` or `studio_path` unset and not supplied → `ArgumentError` naming the missing one.
- The Python executable cannot be spawned (bad path) → typed PCMM error.
- Studio runs but exits non-zero → typed PCMM error. Both failure modes must be covered; `run` raises a different exception type for each (`Base.IOError` vs `ProcessFailedException`), and only the first was previously handled.
- The simulation's parsed rules file is absent → Studio still launches, without rules.

---

## Feature: Error Handling — Typed Exceptions

**One-line description:** PCMM's own failure modes raise typed exceptions so that a GUI can catch them programmatically.

**Priority:** Should-have

**Behavioral specification:**
- `PCMMException` is an abstract supertype; every PCMM-specific exception subtypes it. A caller can catch `PCMMException` for "PCMM said no" or a concrete type for a specific condition.
- Concrete types cover: no project found; PhysiCell Studio failed to launch. The set grows only when a genuinely reachable failure needs to be distinguished.
- Each carries the identifiers a caller needs to act rather than only a message string, to the extent its condition has any: `PCMMStudioLaunchError` carries the `Cmd` and the underlying `cause`, while `PCMMMissingProject` carries only a message, because "no project here" has no further identifier to report.

**Acceptance criteria:**
- Every PCMM-specific exception is catchable both as its concrete type and as `PCMMException`.
- Adding the supertype does not break existing code catching a concrete type.
- Failures originating in a dependency's own contract (e.g. a PhysiCellXMLRules assertion) are either prevented by PCMM checking first, or wrapped in a typed PCMM error — they do not escape raw.

**Edge cases:**
- A dependency assertion that fires because PCMM called it with input it should have rejected is a PCMM bug, not a candidate for wrapping; the call is prevented instead.

---

## Non-Functional Requirements

### Performance
- PCMM's own execution overhead is not a performance concern; ABM simulations dominate wall-clock time.
- PCMM scheduling, bookkeeping, and analysis functions must not measurably delay simulation campaigns.

### Reliability
- **Failure isolation:** A single failed simulation must not halt remaining queued simulations in a campaign. Failed runs are marked in the database; the run loop continues.
- **Idempotency:** Import, compilation, and database migrations must be safe to re-run against already-processed inputs without side effects.
- **Atomic status tracking:** Partial simulation output must never be treated as a completed run. Database status is the authoritative source of truth.

### Platform Compatibility
| Platform | Support Level |
|---|---|
| macOS | Fully supported |
| Linux | Fully supported (primary CI target) |
| Windows | Fully supported |
| Slurm HPC (`sbatch`) | Fully supported (current release) |
| PBS HPC (`qsub`) | Deferred — Phase 3 |

### Framework Scope
- PhysiCell is the only supported ABM framework in this release. Generalization to other frameworks is explicitly deferred to v2.

---

## Release Plan

### Phase 1 — Workflow Templates *(current focus)*
- **Goal:** Ship predefined workflow templates for common study types (parameter sweeps, sensitivity analysis, calibration to population data).
- **In scope:** At least one reproducible end-to-end tutorial workflow usable from a clean checkout.
- **Acceptance gate:** Tutorial workflow runs end-to-end on all supported platforms.

### Phase 2 — Import Wizard
- **Goal:** Ship an interactive GUI for the model import process to support less experienced users.
- **In scope:** `importProject` wizard with browse/validate/status table UI (see Feature: Model Import Wizard).
- **Acceptance gate:** Wizard surfaces validation feedback correctly; import result is equivalent to CLI behavior.

### Phase 3 — HPC Enhancements (qsub + Generalized Scheduler)
- **Goal:** Add PBS/`qsub` support alongside existing Slurm/`sbatch`; unify the HPC job submission API.
- **In scope:** `qsub` submission backend, generalized cluster workflow support.

### Future (v2) — Framework Generalization
- Generalize PCMM to support ABM frameworks beyond PhysiCell.
- Split ModelManager.jl exports into a developer API (for building simulator packages like PCMM) and a user API (re-exported by simulator packages for end users running campaigns). Consider a `ModelManager.UserAPI` submodule pattern so simulator packages can selectively re-export.
- Could-have features revisited: interactive dashboards, automated report generation.

---

## Open Questions & Assumptions

### Open Questions
1. **Model Manager Studio scope:** The PCMM GUI companion (Model Manager Studio) is partially implemented. Which PCMM features should be accessible through it, and in what release phase?
2. **Windows CI validation:** Windows support is targeted but not yet validated in CI. Build environment and compiler chain need to be confirmed.
3. **PhysiPKPD inputs:** PhysiPKPD is not yet representable as a PCMM input location. Needs a design covering how dosing schedules are described, where they live under `inputs/`, and how they participate in parameter variation.

### Assumptions
1. PhysiCell is the only supported ABM framework in this release; generalization is deferred to v2.
2. No user-facing telemetry or usage tracking will be implemented. Success is measured through test pass rates, tutorial reproducibility, and failure isolation rates.
3. `qsub` (PBS) is not required for the current release; Slurm (`sbatch`) and local execution are the supported execution paths.
4. Users are responsible for providing a working `g++` compiler; PCMM does not manage compiler installation.
5. Primary deployment is on researcher workstations or HPC clusters; cloud-native execution is not targeted in this release.

