#! Regenerates the figures embedded in the manual: the population plots in analyzing_output.md, the
#! sensitivity-analysis plots in sensitivity_analysis.md and the calibration plots in calibration.md.
#!
#! The manual's plots are committed as PNGs under docs/src/assets/ rather than rendered during
#! `makedocs`. Rendering them live would require the docs build to have a compiled PhysiCell and
#! real simulation output, which the docs CI job does not have. Committing them keeps the docs
#! build fast and dependency-free, at the cost of regenerating by hand -- run this script when the
#! plot recipes change.
#!
#! Usage, from the repository root:
#!
#!     julia --project=docs docs/generate_figures.jl <path/to/project>
#!
#! `<path/to/project>` must be a PCMM project holding the `immune_sample` config plus the
#! `immune_function` custom code, IC cells and rulesets, and the `0_template` config, custom code and
#! rulesets; `test/` qualifies once the test suite has been run at least once.
#! The script builds its own small campaigns rather than reusing whatever simulations happen to be
#! in the database, both so the figures are reproducible and because the test suite resets its
#! database on the way out. Expect a PhysiCell compile on the first run, and a couple of hundred
#! short template-project simulations for the sensitivity and calibration figures (an hour or two).

ENV["GKSwstype"] = "100"   #! GR off-screen; the script runs headless

using PhysiCellModelManager
#! Public but not exported, so it needs qualifying (see the `@compat public` list in configuration.jl).
using PhysiCellModelManager: userParameterPath, cyclePath
using Plots, Distributions

length(ARGS) == 1 || error("usage: julia --project=docs docs/generate_figures.jl <path/to/project>")
project_dir = abspath(ARGS[1])
initializeModelManager(joinpath(project_dir, "PhysiCell"), joinpath(project_dir, "data"))

assets = normpath(joinpath(@__DIR__, "src", "assets"))
mkpath(assets)
save(name, plt) = (path = joinpath(assets, name); savefig(plt, path); println("wrote ", path))

#! `immune_sample` is PhysiCell's tumour-immune sample: six cell types with real population
#! dynamics over 24 simulated hours. The rules fixtures in this project have far more cell types
#! but run for only a minute of simulated time, so their plots are flat lines and teach nothing.
#! Two parameter values -> two monads, so the per-monad panel layout is visible; three replicates
#! per monad so the mean +/- SD ribbon has something to summarise.
inputs = InputFolders("immune_sample", "immune_function";
                      ic_cell="immune_function", rulesets_collection="immune_function")
cell_counts = [50, 200]
dv = DiscreteVariation(userParameterPath("number_of_cells"), cell_counts)
out = run(inputs, dv; n_replicates=3)
sampling = out.trial
println("ran $(length(monadIDs(sampling))) monads, $(length(simulationIDs(sampling))) simulations")

#! Restrict to cell types that actually have cells, and cap the legend so the figure stays legible.
#! Picking them here also lets the figures double as an illustration of the
#! `include_cell_type_names` keyword the surrounding text describes. The preferred three are named
#! rather than taken alphabetically: the first three by name are all T-cell subtypes, which drops
#! the tumour and makes the plot look like it is about nothing.
counts = finalPopulationCount(Monad(first(monadIDs(sampling))))
populated = [k for (k, v) in counts if v > 0]
println("populated cell types: ", join(sort(populated), ", "))
preferred = ["tumor cell", "macrophage", "effector T cell"]
selected = [ct for ct in preferred if ct in populated]
isempty(selected) && (selected = sort(populated)[1:min(3, length(populated))])
println("plotting: ", join(selected, ", "))

#! `size` matters more than it looks: these figures stack one panel per monad (or per cell type),
#! and at the default 600x400 three panels crowd their tick labels into illegibility.
common = (; include_cell_type_names=selected, time_unit=:h,
            xlabel="time (h)", ylabel="cell count", legend=:outerright,
            size=(760, 260 * max(length(monadIDs(sampling)), length(selected))),
            left_margin=5Plots.mm, bottom_margin=5Plots.mm)

save("plot_by_monad.png", plot(sampling; common...))
#! In `plotbycelltype` each panel is one cell type and the series within it are the monads -- the
#! inverse of `plot`. So the series are labelled with the varied parameter's values, not with cell
#! type names; labelling them with cell types (as the shape of the call tempts you to) mislabels
#! every series. Series follow monad order, which is the order of the variation's values.
save("plot_by_cell_type.png",
     plotbycelltype(sampling; common...,
                    labels=permutedims(["number_of_cells = $(n)" for n in cell_counts])))
#! Taller than it looks like it needs to be: at 300px the x-axis label lands outside the canvas and
#! the y-axis label is clipped at the left edge.
save("plot_single_simulation.png",
     plot(Simulation(first(simulationIDs(sampling)));
          include_cell_type_names=selected, time_unit=:h,
          xlabel="time (h)", ylabel="cell count", legend=:outerright,
          size=(760, 380), left_margin=5Plots.mm, bottom_margin=5Plots.mm))

################## Sensitivity analysis and calibration ##################
#
# The template project rather than `immune_sample`: a handful of cells whose fate two config
# parameters govern directly -- the cycle's first phase duration and the apoptosis rate -- so the
# sensitivity indices and the posterior mean something and each simulation takes seconds. Two days
# of simulated time from 50 cells gives a few hundred cells at the end, enough for the count to
# respond smoothly to both parameters.

template = InputFolders("0_template", "0_template"; rulesets_collection="0_template")
ref_variations = [DiscreteVariation(configPath("max_time"), 2880.0),
                  DiscreteVariation(userParameterPath("number_of_cells"), 50)]
#! The reference monad: the fixed settings above, no simulations of its own (`n_replicates=0`).
ref = createTrial(template, ref_variations; n_replicates=0)

phase_path     = cyclePath("default", "phase_durations", "duration:index:0")
apoptosis_path = configPath("default", "apoptosis", "rate")
phase_name, apoptosis_name = "cycle phase 0 duration", "apoptosis rate"

#! Parallelism: the template config asks for 6 OpenMP threads per simulation.
setNumberOfParallelSims(max(1, Sys.CPU_THREADS ÷ 6))

count_qoi = endpointPopulationCountQoI(; cell_types=["default"])
gsa_params = [UniformDistributedVariation(phase_path, 150.0, 600.0; name=phase_name),
              UniformDistributedVariation(apoptosis_path, 1e-5, 4e-4; name=apoptosis_name)]
gsa_kwargs = (; functions=[count_qoi], n_replicates=1)

moat = run(MOAT(8), ref, gsa_params; gsa_kwargs...)
rbd  = run(RBD(16), ref, gsa_params; gsa_kwargs...)
println("GSA done: ", length(simulationIDs(moat.sampling)) + length(simulationIDs(rbd.sampling)),
        " simulations")

gsa_size = (; size=(640, 400), left_margin=5Plots.mm, bottom_margin=5Plots.mm)
save("gsa_moat_bar.png",     plot(moat; show_sigma=true, gsa_size...))
save("gsa_moat_scatter.png", plot(moat, :scatter; gsa_size...))
save("gsa_rbd.png",          plot(rbd; gsa_size...))

#! The Sobolʼ figure is the one drawn from made-up numbers. A design small enough to run here
#! (Sobolʼ(16), 40 simulations) estimated ST below S1, which no total-order index is, and one large
#! enough to respect that (Sobolʼ(64)) is 238 simulations for a picture whose job is to show the
#! plot, not to measure anything. So the bars are illustrative values pushed through the recipe a
#! real `SobolSampling` uses. `_sobolBarData` and `SobolResult` are internals of ModelManager and
#! GlobalSensitivity; if either moves, this block is the one to fix.
sobol_bars = ModelManager._sobolBarData(
    Dict("endpoint_population_count.default" =>
         ModelManager.GlobalSensitivity.SobolResult([0.28, 0.55], nothing, nothing, nothing,
                                                    [0.41, 0.69], nothing)),
    ModelManager.DataFrames.DataFrame("A" => Int[], "B" => Int[],
                                      phase_name => Float64[], apoptosis_name => Float64[]),
    true)
save("gsa_sobol.png", plot(sobol_bars; gsa_size...))

#! The observation is one simulation at known parameter values, so the posterior can be read
#! against a truth: phase 0 of 300 minutes and an apoptosis rate of 1e-4 per minute.
truth = createTrial(template, [ref_variations..., DiscreteVariation(phase_path, 300.0),
                                DiscreteVariation(apoptosis_path, 1e-4)]; n_replicates=1)
run(truth)
observed = Dict("default" => Float64(finalPopulationCount(Monad(first(monadIDs(truth))))["default"]))
println("observed final count: ", observed["default"])

problem = CalibrationProblem(template,
                             [DistributedVariation(phase_path, Uniform(150.0, 600.0); name=phase_name),
                              DistributedVariation(apoptosis_path, Uniform(1e-5, 4e-4); name=apoptosis_name)],
                             observed, count_qoi, mseDistance;
                             reference_variation_id=ref.variation_id, n_replicates=1)
result = runCalibration(ABCSMC(population_size=16, max_nr_populations=4, minimum_epsilon=0.0), problem;
                        description="docs figures")
println("calibration ", result.calibration.id, ": ", length(result.generations), " generations")

save("calibration_corner.png",      plot(result; size=(640, 640)))
save("calibration_ridgeline.png",   plot(result, :ridgeline; size=(760, 420), left_margin=5Plots.mm))
save("calibration_convergence.png", plot(ConvergenceSummary(result); size=(760, 640), left_margin=12Plots.mm))
save("calibration_transition.png",  plot(result, :transition; size=(640, 640)))
