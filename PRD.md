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

**Acceptance criteria:**
- A fresh directory becomes a valid project after one `createProject` call.
- Re-initializing an already-initialized project does not corrupt the database.
- `databaseDiagnostics()` passes with no errors after initialization.

**Edge cases:**
- Path does not exist → create it.
- Path already contains a PCMM database → re-attach, do not reinitialize.
- Called without any path → use current working directory.

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
- `GridVariation([dv1, dv2, ...])` — full Cartesian product of multiple `DiscreteVariation`s.
- `LHSVariation`, `SobolVariation`, `RBDVariation` — space-filling designs over continuous ranges.
- `DistributedVariation` — sample from a probability distribution.
- `LatentVariation` — parameterize multiple XML paths through a single latent scalar.
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
- Local execution: spawns PhysiCell subprocesses, up to `n_parallel` at a time.
- HPC execution: generates job scripts and submits via `sbatch` (Slurm); PBS/`qsub` support is deferred to Phase 3.
- Returns a `Trial` (or `Sampling`/`Monad`) object referencing database IDs.

**Acceptance criteria:**
- Completed simulations write output to `outputs/<simulation_id>/`.
- Database records each simulation with status (queued / running / completed / failed).
- Rerunning an already-completed simulation with identical inputs is a no-op.

**Edge cases:**
- PhysiCell binary not compiled → error with instructions.
- Simulation process exits non-zero → mark as failed in database, do not crash caller.
- `n_replicates=0` → error.

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

**Acceptance criteria:**
- Results match values read directly from PhysiCell SVG/output files.
- Empty monad (no simulations) → error, not silent zero.

**Edge cases:**
- Simulation has no output files → error with simulation ID.
- Requested cell type not present in output → return 0 / empty entry.
- `include_dead=false` is default; dead cells excluded from all counts unless specified.

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
- All calibration infrastructure (ABC-SMC algorithm, `CalibrationProblem`, `runABC`, `resumeABC`, kernels, posterior visualization) lives in ModelManager. PCMM contributes only the PhysiCell-specific summary statistics passed as `summary_statistic` in a `CalibrationProblem`.
- `endpointPopulationCounts(monad_id; cell_types, include_dead)` → `Dict{String,Float64}` mapping cell type → mean final count across replicates. Returns `missing` if no simulation output is available.
- `endpointPopulationFractions(monad_id; cell_types, include_dead)` → `Dict{String,Float64}` mapping cell type → mean fraction of total live cells. Returns `missing` if no output available.
- `meanPopulationTimeSeries(monad_id; cell_types, include_dead)` → `Dict{String,Vector{Float64}}` mapping cell type → mean count over time across replicates.
- Future PhysiCell-specific statistics (spatial metrics, intracellular state distributions, etc.) would be added here.

**Acceptance criteria:**
- `endpointPopulationCounts(monad_id)` returns a `Dict{String,Float64}` for a monad with completed simulations.
- `endpointPopulationCounts` returns `missing` gracefully when simulation output files are absent.
- Fractions sum to 1.0 (within floating-point tolerance) when `include_dead=false`.
- `cell_types` filter restricts output to only the requested types.

**Edge cases:**
- All replicates in a monad have missing output → return `missing`, not an error.
- `cell_types` filter names a type not present in the simulation → entry is omitted from result.

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

**Background:** ModelManager (0.7.x) runs three per-simulation post steps in order:
`postSimulationProcessing` (non-destructive) → user `post_processor` (successful sims only) → `postSimulationCleanup` (destructive). PCMM implements the destructive step (err-file handling + `pruneSimulationOutput`) as `postSimulationCleanup` so a `post_processor` always reads an un-pruned output folder. `postSimulationProcessing` is left as ModelManager's no-op default.

**Behavioral specification:**
- `run(T; post_processor = sp -> …)` calls the callback once per successful simulation, after the simulation finishes and before pruning.
- The callback receives a `SimulationProcess`; use accessors `simulationID`, `monadID`, `wasSuccessful`, `pathToOutputFolder(sp)` (not `sp.simulation.id`).
- Return patterns: `nothing` (side effects only — must be explicit), a `NamedTuple`, or a `Dict` of `name => scalar` (`Real`/`Bool`/`String`). Non-scalar returns throw `ArgumentError` (ModelManager-side).
- Stored QoIs land in `data/outputs/postprocessing.db`; read back with `postProcessingTable(T)` or `simulationsTable(T; post_processing=true)`.
- **QoI builder:** `populationCountQoI(; index=:final, cell_types=nothing, include_dead=false)` returns a ready-made `post_processor` recording one `count_<cell_type>` quantity per cell type, read from the snapshot at `index` (`:final`, `:initial`, or an integer snapshot index).

**Acceptance criteria:**
- A `post_processor` reading `pathToOutputFolder(sp)` sees output files present; those files are pruned only after it returns.
- A run without `post_processor` prunes exactly as before (no regression).
- `postSimulationCleanup` runs for every completed simulation, including failures.
- `populationCountQoI()` matches `finalPopulationCount` at the default `:final` index and `populationCount` at any integer index; an optional `cell_types` filter restricts which cell types are recorded.

**Edge cases:**
- Callback on a failed simulation → not called (successful sims only); cleanup still runs.
- Callback returns a non-scalar → `ArgumentError`.
- Un-updated PCMM against reordered ModelManager → still prunes, but in the earlier hook, so a `post_processor` would see already-pruned output. Task A removes this gap.
- `populationCountQoI`'s requested snapshot doesn't exist (e.g. pruned) → returns `nothing` for that simulation instead of throwing.

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
3. **QoI builders for sensitivity/calibration:** `post_processor` QoI builders (e.g. `populationCountQoI`) currently only target `run(...; post_processor=...)` and its sink DB. Not yet done: wiring their output into sensitivity analysis or `CalibrationProblem` workflows (which currently take separate `summary_statistic`/`functions` callbacks of their own).

### Assumptions
1. PhysiCell is the only supported ABM framework in this release; generalization is deferred to v2.
2. No user-facing telemetry or usage tracking will be implemented. Success is measured through test pass rates, tutorial reproducibility, and failure isolation rates.
3. `qsub` (PBS) is not required for the current release; Slurm (`sbatch`) and local execution are the supported execution paths.
4. Users are responsible for providing a working `g++` compiler; PCMM does not manage compiler installation.
5. Primary deployment is on researcher workstations or HPC clusters; cloud-native execution is not targeted in this release.

