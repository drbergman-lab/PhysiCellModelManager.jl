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
- Delegates statistical computation to SALib (Python) via PythonCall.

**Acceptance criteria:**
- Sensitivity indices sum to approximately 1 for well-behaved models.
- Results are reproducible given the same seed.

**Edge cases:**
- Fewer samples than recommended for reliable indices → warn.
- Output quantity is constant across all runs → indices are all zero, no error.

---

## Feature: Calibration (ABC-SMC)

**One-line description:** Fit model parameters to observed data using Approximate Bayesian Computation Sequential Monte Carlo.

**Priority:** Must-have (core functionality); Should-have (depth — extensible objective functions, robustness improvements)

**User story:** As a researcher, I want downstream calibration tooling so that I can connect my model to experimental data, estimate parameters, and extract quantitative biological insights.

**Behavioral specification:**
- Requires loading both `PythonCall` and `PhysiCellModelManager` (in either order) to activate `PCMMCalibrationExt`.
- `CalibrationProblem` holds: parameters (name, prior distribution), distance function, observed data reference, and number of populations.
- `runABC(problem; ...)` runs ABC-SMC via `pyabc`, using `SingleCoreSampler` to avoid pickling Julia closures across Python processes.
- `posterior(result)` → `(DataFrame, weights)` for the final or a specified intermediate generation.
- CondaPkg manages the Python environment; `pyabc` is installed automatically from `CondaPkg.toml`.

**Acceptance criteria:**
- Extension is not loaded unless `PythonCall` is also loaded; no runtime error in its absence.
- `posterior` returns a DataFrame with one column per calibrated parameter.
- A smoke-test run with a trivial distance function completes without error.
- `runABC` with `max_populations=1` produces a non-empty posterior.

**Edge cases:**
- `pyabc` not installed → descriptive error pointing to CondaPkg.
- Parameter prior is improper (infinite support with no normalization) → delegate error to pyabc.
- Distance function returns `NaN` → pyabc raises; surface the error clearly.
- Monad referenced by distance function has no completed simulations → error before ABC starts.

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

**Edge cases:**
- Schema version mismatch → migrate up, never silently corrupt.
- Database file locked by another process → error with message, not silent hang.

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

### Phase 1 — Calibration & Workflow Templates *(current focus)*
- **Goal:** Complete and stabilize Calibration (ABC-SMC); ship predefined workflow templates for common study types.
- **In scope:** Calibration depth improvements, extensible objective/distance functions, at least one reproducible end-to-end tutorial workflow.
- **Acceptance gate:** Calibration smoke test passes on all supported platforms; at least one tutorial workflow runs end-to-end from a clean checkout.

### Phase 2 — Import Wizard
- **Goal:** Ship an interactive GUI for the model import process to support less experienced users.
- **In scope:** `importProject` wizard with browse/validate/status table UI (see Feature: Model Import Wizard).
- **Acceptance gate:** Wizard surfaces validation feedback correctly; import result is equivalent to CLI behavior.

### Phase 3 — HPC Enhancements (qsub + Generalized Scheduler)
- **Goal:** Add PBS/`qsub` support alongside existing Slurm/`sbatch`; unify the HPC job submission API.
- **In scope:** `qsub` submission backend, generalized cluster workflow support.

### Phase 4 — Julia-Native Calibration
- **Goal:** Replace or supplement Python-backed ABC-SMC with Julia-native calibration workflows, removing the `PythonCall` dependency for calibration.

### Future (v2) — Framework Generalization
- Generalize PCMM to support ABM frameworks beyond PhysiCell.
- Could-have features revisited: interactive dashboards, automated report generation.

---

## Open Questions & Assumptions

### Open Questions
1. **Calibration extensibility:** How should users define custom objective/distance functions beyond population counts? The API must remain open to arbitrary Julia functions over simulation outputs.
2. **Model Manager Studio scope:** The PCMM GUI companion (Model Manager Studio) is partially implemented. Which PCMM features should be accessible through it, and in what release phase?
3. **Windows CI validation:** Windows support is targeted but not yet validated in CI. Build environment and compiler chain need to be confirmed.

### Assumptions
1. PhysiCell is the only supported ABM framework in this release; generalization is deferred to v2.
2. No user-facing telemetry or usage tracking will be implemented. Success is measured through test pass rates, tutorial reproducibility, and failure isolation rates.
3. `qsub` (PBS) is not required for the current release; Slurm (`sbatch`) and local execution are the supported execution paths.
4. Users are responsible for providing a working `g++` compiler; PCMM does not manage compiler installation.
5. Primary deployment is on researcher workstations or HPC clusters; cloud-native execution is not targeted in this release.
