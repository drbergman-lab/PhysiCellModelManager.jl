# progress.md — PCMM Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

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
