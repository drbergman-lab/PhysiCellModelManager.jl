# progress.md — PCMM Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

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

- Batch-parallel particle evaluation: currently particles are evaluated sequentially (PhysiCell parallelizes within each particle). Future optimization: build a `Sampling` containing multiple particles' Monads and run them together so PCMM's max_number_of_parallel_simulations parallelizes across particles.
- GP emulation (GpABC.jl or custom): would reduce expensive PhysiCell evaluations. The `AbstractCalibrationMethod` hierarchy is ready for this — add `GPAcceleratedABC <: AbstractCalibrationMethod` without restructuring.
- Extension cleanup: once native is battle-tested, delete `ext/PCMMCalibrationExt.jl`, remove `PythonCall` from `[weakdeps]`, and delete `CondaPkg.toml`.

---

## 2026-03-29 — Calibration (ABC-SMC) via PythonCall

### Decisions made

**PyCall → PythonCall migration**
Started with PyCall for pyabc integration. Switched to PythonCall + CondaPkg because:
- PyCall uses a depot-global Python environment (`~/.julia/conda/3/`), making per-project Python deps unreliable.
- PythonCall uses CondaPkg for per-project environments; `CondaPkg.toml` lives in the repo and installs automatically.
- PythonCall always returns `Py` objects (no silent Julia-type coercion), removing the need for `pycall(f, PyObject; ...)` workarounds.

**Julia 1.9+ native extension (not Requires.jl)**
The calibration code requires `PythonCall`, which is heavy and optional. Used `[weakdeps]` + `[extensions]` in `Project.toml` and placed code in `ext/PCMMCalibrationExt.jl`. The extension activates automatically when both `PhysiCellModelManager` and `PythonCall` are loaded (order is irrelevant). Requires.jl was explicitly rejected.

**SingleCoreSampler**
pyabc defaults to `MulticoreEvalParallelSampler`, which pickles the model function across Python processes. Julia closures cannot be pickled. Fixed by passing `sampler = pyabc.sampler.SingleCoreSampler()` to `ABCSMC`. This is a hard constraint — any multi-core sampler will fail.

**Dict iteration in PythonCall**
Iterating a Python dict directly in PythonCall yields keys only (unlike PyCall which yielded key-value pairs). Must use `d.items()` and index as `item[0]`, `item[1]`.

**`finalPopulationCount(Monad)` placement**
Added to `src/analysis/population.jl` (not `src/calibration/distance.jl`) because it is a general analysis utility. The distance helpers in calibration delegate to it. `endpointPopulationCounts` in `distance.jl` is now a thin wrapper.

**`meanPopulationTimeSeries` naming**
Rejected "endpointPopulationTimeSeries" (contradictory terms). Chose `meanPopulationTimeSeries` wrapping `MonadPopulationTimeSeries.mean` field.

**`path_to_uq_python` / `PCMM_UQ_PYTHON_PATH` removed**
These globals were needed when manually pointing PCMM to a conda env for PyCall. Obsolete with CondaPkg — removed from `src/globals.jl` and the module initializer.

### Approaches tried and rejected

- `DataFrame(py_df)` via Tables.jl — fails because PythonCall doesn't implement the Tables.jl interface for pandas DataFrames. Fixed by extracting columns manually via `py_df.columns` + `py_df[c].to_numpy()`.
- `pairs(prior)` to iterate a pyabc `Distribution` — fails because it is a dict subclass and `pairs()` gives Julia key-value pairs of the wrapper, not the Python contents. Call `.rvs()` directly instead.
- `pycall(pyabc.Distribution, PyObject; rv_dict...)` — this was the PyCall workaround to prevent dict auto-conversion. Not needed in PythonCall.

### Open questions

- Parallelism: `SingleCoreSampler` is correct but slow. Longer-term, consider wrapping the simulation call in a Python-side subprocess or using a Julia-native ABC implementation that doesn't require pickling.
- CondaPkg install timing: pyabc is large. First-time `using PythonCall; using PhysiCellModelManager` will trigger a conda solve. Document this expected delay.
- `posterior` for intermediate generations: currently supported via `generation=:final` or `generation=k`. Unclear if `k=0` is a valid pyabc generation index — needs a test with `max_populations > 1`.

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
- `DeletionTests` — intermittent; de-initializes the project, causing `DepsTests` to fail on `assertInitialized`.
- `DepsTests` — depends on project state left by `DeletionTests`; sequencing issue.

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
