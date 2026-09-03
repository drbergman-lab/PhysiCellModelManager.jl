#! Regenerates the figures embedded in docs/src/man/analyzing_output.md.
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
#! `immune_function` custom code, IC cells and rulesets; `test/` qualifies once the test suite has been run at least once.
#! The script builds its own small campaign rather than reusing whatever simulations happen to be
#! in the database, both so the figures are reproducible and because the test suite resets its
#! database on the way out. Expect a PhysiCell compile on the first run.

using PhysiCellModelManager
#! Public but not exported, so it needs qualifying (see the `@compat public` list in configuration.jl).
using PhysiCellModelManager: userParameterPath
using Plots

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
