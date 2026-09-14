<p align="center"><img src="docs/src/assets/logo-hero.svg" width="200" alt="PhysiCellModelManager.jl"></p>

# PhysiCellModelManager.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman-lab.github.io/PhysiCellModelManager.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman-lab.github.io/PhysiCellModelManager.jl/dev/)
[![Build Status](https://github.com/drbergman-lab/PhysiCellModelManager.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman-lab/PhysiCellModelManager.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman-lab/PhysiCellModelManager.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman-lab/PhysiCellModelManager.jl)

Check out [Getting started](https://drbergman-lab.github.io/PhysiCellModelManager.jl/stable/man/getting_started/) for a quick guide to using PhysiCellModelManager.jl.
Make sure you are familiar with the [Best practices](https://drbergman-lab.github.io/PhysiCellModelManager.jl/stable/man/best_practices/) section before using PhysiCellModelManager.jl.

# Quick start

See [Getting started](https://drbergman-lab.github.io/PhysiCellModelManager.jl/stable/man/getting_started/) for more details.

1. [Install Julia](https://julialang.org/install).
2. Ensure the general registry is added:
```julia-repl
pkg> registry add General
```
3. Add the BergmanLabRegistry:
```julia-repl
pkg> registry add https://github.com/drbergman-lab/BergmanLabRegistry
```
4. Install PhysiCellModelManager.jl:
```julia-repl
pkg> add PhysiCellModelManager
```
5. Create a new PCMM project:
```julia-repl
julia> using PhysiCellModelManager
julia> createProject() # uses the current directory as the PCMM project folder
```
> Note: A PCMM project is distinct from PhysiCell's `sample_projects` and `user_projects`.
6. Import a sample project or a user project from PhysiCell:
```julia-repl
julia> importProject("path/to/PhysiCell/user_projects/my_project") # replace with the path to your project folder
```
7. Check the output of Step 6 and record your input folders:
```julia-repl
julia> config_folder = "my_project" # replace these with the name from the output of Step 6
julia> custom_code_folder = "my_project"
julia> rules_folder = "my_project" 
julia> inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection = rules_folder) # also add ic_cell and ic_substrate if used
```
8. Run the model:
```julia-repl
julia> out = run(inputs; n_replicates = 1)
```
9. Check the output:
```julia-repl
julia> using Plots # make sure to install Plots first
julia> plot(out)
julia> plotbycelltype(out)
```
10. Vary parameters:
```julia-repl
julia> xml_path = configPath("some_cell_type", "apoptosis", "death_rate") # replace with a cell type in your model
julia> new_apoptosis_rates = [1e-5, 1e-4, 1e-3]
julia> dv = DiscreteVariation(xml_path, new_apoptosis_rates)
julia> out = run(inputs, dv; n_replicates = 3) # 3 replicates per apoptosis rate => 9 simulations total
```

---

## Implementation Status

> For Claude Code sessions: this section is the authoritative record of what has been built. Update it as features are completed. See [PRD.md](PRD.md) for behavioral specifications and [progress.md](progress.md) for decision rationale.

### Completed

- [x] Project initialization (`createProject`, `initializeModelManager`). `using PhysiCellModelManager` auto-attaches to a project in the working directory, except while Julia is writing a precompilation cache or system image
- [x] Model import from PhysiCell project folders (`importProject`, `InputFolders`)
  - [ ] Wizard for guiding users through the import process and recording their input folders
- [x] Parameter variation — discrete, grid, distributed, latent, co-variation. `configPath`/`behaviorPath` build the XML paths and reject an unrecognised tag by name
- [x] Space-filling designs — LHS, Sobol, RBD
- [x] Simulation execution — local multi-process runner. Executables are named for the PhysiCell version they were built against, in `pcmm_build/` inside the custom code folder, so the file's existence is the only record of a finished build; the PhysiCell version is re-resolved before every compilation, so pulling, checking out, or editing PhysiCell mid-session is picked up without restarting Julia
- [x] HPC job submission — ModelManager owns launching; PCMM implements `simulationCommand` (what to run) and `simulationThreads` (each simulation's `omp_num_threads`, which ModelManager requests as `cpus-per-task`, since PhysiCell sets its thread count from its config and SLURM allocates one CPU unless asked)
- [x] Analysis — population counts and time series (`finalPopulationCount`, `populationTimeSeries`, `meanPopulationTimeSeries`). Replicates whose output has been deleted or pruned are excluded from monad-level aggregates and plots, and reported once per call site (`@info ... maxlog=1`)
  - [x] Plot recipes documented with rendered figures in the manual: the population plots, and ModelManager's sensitivity-analysis and calibration plots on the template project (`docs/generate_figures.jl`)
- [x] Sensitivity analysis — MOAT, Sobol, and RBD via ModelManager; a `Dict`-valued `QoI` yields one analysis per key, labelled `<qoi name>.<key>`
- [x] Calibration — ABC-SMC, posterior visualization, and `resumeABC` live in ModelManager. PCMM contributes the PhysiCell-specific measurements: monad-level statistics (`endpointPopulationCounts`, `endpointPopulationFractions`, `meanPopulationTimeSeries`) for analysing a finished monad, and single `Dict`-valued `QoI` builders (`endpointPopulationCountQoI`, `endpointPopulationFractionQoI`, `meanPopulationTimeSeriesQoI`) to serve as a `CalibrationProblem`'s `summary_statistic`, asserted to agree with the monad-level statistics up to floating-point summation order, including on a monad with a pruned replicate
  - [x] The builders carry their keyword arguments in the QoI's `data` slot with a named `compute`, so `problem.jld2` is complete and `resumeABC(Calibration(id))` resumes without `problem=`
  - [x] No builder defines a `reduce`: all four are averaged across a monad's replicates by ModelManager's default per-key mean, whose requirement that the replicates report the same cell types is met by construction — the key set is the model's declared roster, not the types with living cells
  - [x] The two endpoint builders serve calibration, the post-processing sink and sensitivity analysis alike, as does `populationCountQoI` below. `meanPopulationTimeSeriesQoI` serves calibration alone: every component it reports is a time series rather than the `Real` a sink column or a sensitivity index is computed from
  - [ ] GP-accelerated ABC (surrogate model to reduce expensive PhysiCell evaluations)
  - [ ] Bayesian optimization
  - [ ] Additional methods (MCMC, Nelder-Mead, etc.) as subtypes of `AbstractCalibrationMethod`
- [x] Database management — SQLite schema, versioned migrations (`up.jl`), diagnostics
  - [x] Upgrade-path CI — dedicated workflow replays version history (generate with an older release, upgrade with the dev checkout) to guard `up.jl`; see [`test/upgrade/`](test/upgrade/). Source matrix `0.1.7` (the oldest version a real user is on; crosses the `0.2.0` par_key rewrite) and `0.2.2`; walks back over time toward `pcvct@0.0.3`
- [x] Export and pruning of simulation outputs. `prune_options` is documented on the post-processing page as the last step after a simulation: what each flag removes, the ordering against the `post_processor`, and what stops working afterwards
- [x] Post-processing hook (`post_processor`) — user callback runs on intact simulation output before PCMM's destructive cleanup (`postSimulationCleanup`); results stored via ModelManager's QoI sink (`postProcessingTable`, `simulationsTable(...; post_processing=true)`)
  - [x] Ready-made QoI builder `populationCountQoI` so a `post_processor` can be a one-liner — per-cell-type counts at the final snapshot or any indexed save, one `population_count.<cell_type>` sink column per cell type, the types read from the simulation's own output
- [x] Intracellular model support (custom data, rules)
- [x] IC cell and IC ECM file management
- [x] Movie generation via the PhysiCell Makefile (`makeMovie`) — `framerate`, `magick_density`, `magick_resize_x`/`magick_resize_y` keyword arguments
- [x] PhysiCell Studio integration (`runStudio`) — launches Studio against a completed simulation's output; either launch failure (interpreter not spawnable, Studio exiting non-zero) raises `PCMMStudioLaunchError`
- [x] Typed exceptions — every PCMM-specific failure subtypes `PCMMException`, so a GUI consumer can catch the family or a concrete type

### Remaining

- [ ] Support showing snapshots from a monad/sampling/trial in a single figure. Support CairoMakie (as extension) to make a movie from the snapshots.
- [ ] GP-accelerated ABC and additional calibration methods (see Calibration bullet above)
