using Documenter, DocumenterInterLinks, PhysiCellModelManager, ModelManager
using TOML

# `@extref ModelManager ...` links resolve against the ModelManager manual at the minor version
# PCMM's [compat] entry pins, so a reader on this PCMM lands in the docs for the MM they have.
# Documenter deploys one `vMAJOR.MINOR/` folder per minor, and every entry's `objects.inv`
# inventory is fetched at build time, so a renamed MM heading fails this build instead of 404-ing.
function modelManagerDocsRoot()
    compat = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))["compat"]["ModelManager"]
    lower_bounds = [VersionNumber(lstrip(strip(entry), ('^', '~', '='))) for entry in split(compat, ',')]
    v = maximum(lower_bounds) # the newest minor PCMM is tested against
    return "https://drbergman-lab.github.io/ModelManager.jl/v$(v.major).$(v.minor)/"
end

links = InterLinks("ModelManager" => modelManagerDocsRoot())

DocMeta.setdocmeta!(PhysiCellModelManager, :DocTestSetup, :(using PhysiCellModelManager); recursive=true)
DocMeta.setdocmeta!(ModelManager, :DocTestSetup, :(using ModelManager); recursive=true)

makedocs(;
    modules=[PhysiCellModelManager, ModelManager],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="PhysiCellModelManager.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman-lab.github.io/PhysiCellModelManager.jl",
        edit_link="main",
        assets=["assets/tiers.css", "assets/tiers.js"], # reader-selectable depth (Code / Brief / Full / Dev)
        collapselevel=1, # collapse all top-level sidebar sections by default; the current page's section auto-expands
    ),
    pages=[
        "Home" => "index.md",
        "Getting Started" => Any[
            "Installation" => "man/installation.md",
            "Julia environments" => "man/julia_environments.md",
            "Your first project" => "man/getting_started.md",
            "Importing a project" => "man/importing_projects.md",
        ],
        "Building & Varying Models" => Any[
            "XML path helpers" => "man/xml_path_helpers.md",
            "Varying parameters" => "man/varying_parameters.md",
            "CoVariations" => "man/covariations.md",
            "LatentVariations" => "man/latent_variations.md",
            "Intracellular inputs" => "man/intracellular_inputs.md",
        ],
        "Running Simulations" => Any[
            "Running simulations" => "man/running_simulations.md",
            "Trials, samplings, monads, simulations" => "man/trials.md",
        ],
        "Uncertainty Quantification" => Any[
            "Sensitivity analysis" => "man/sensitivity_analysis.md",
            "Calibration" => "man/calibration.md",
        ],
        "Results & Analysis" => Any[
            "Analyzing output" => "man/analyzing_output.md",
            "Post-processing and quantities of interest" => "man/post_processing.md",
            "Querying parameters" => "man/querying_parameters.md",
            "Movies" => "man/movies.md",
            "Tagging and recovery" => "man/tagging.md",
        ],
        "Examples" => "man/examples.md",
        "Tools & Integrations" => Any[
            "Using PhysiCell Studio" => "man/physicell_studio.md",
        ],
        "Reference" => Any[
            "Best practices" => "man/best_practices.md",
            "Data directory structure" => "man/data_directory.md",
            "Project configuration" => "man/project_configuration.md",
            "Managing a project" => "man/managing_a_project.md",
            "Known limitations" => "man/known_limitations.md",
        ],
        # Hidden from the sidebar below the Dev tier (see assets/tiers.js, NAV_GATES).
        "Developers" => Any[
            "Architecture" => "dev/architecture.md",
            "Simulator interface" => "dev/simulator_interface.md",
            "Utilities" => "dev/utilities.md",
        ],
        # Index: the exhaustive home for exported docstrings, grouped by code
        # family (not mirroring the Manual). NOTE: this list is maintained by
        # hand — when adding a new docs/src/lib/*.md page, add it to a group below.
        "Index" => Any[
            "Core" => map(s -> "lib/$(s)", [
                "PhysiCellModelManager.md", "user_api.md", "globals.md", "utilities.md", "classes.md",
            ]),
            "Project & inputs" => map(s -> "lib/$(s)", [
                "creation.md", "configuration.md", "components.md", "import.md",
                "variations.md", "xml_utilities.md", "ic_cell.md", "ic_ecm.md",
            ]),
            "Running simulations" => map(s -> "lib/$(s)", [
                "runner.md", "physicell_simulator.md", "abstract_simulator.md",
                "compilation.md", "recorder.md", "hpc.md",
            ]),
            "Analysis & output" => map(s -> "lib/$(s)", [
                "analysis.md", "loader.md", "export.md", "movie.md",
                "sensitivity.md", "calibration.md",
            ]),
            "Management & maintenance" => map(s -> "lib/$(s)", [
                "database.md", "tags.md", "deletion.md", "pruner.md", "up.md",
                "deprecate_keywords.md", "pcmm_version.md", "physicell_version.md",
                "physicell_studio.md",
            ]),
            "Alphabetical index" => "man/index.md",
        ],
        "Miscellaneous" => Any[
            "Database upgrades" => "misc/database_upgrades.md",
        ],
    ],
    checkdocs=:exports,
    plugins=[links],
)

deploydocs(;
    repo="github.com/drbergman-lab/PhysiCellModelManager.jl",
    devbranch="main",
    push_preview=true,
)
