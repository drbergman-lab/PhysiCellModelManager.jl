# progress.md — PCMM Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

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
