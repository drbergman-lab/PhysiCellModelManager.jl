using Documenter, PhysiCellModelManager, ModelManager

DocMeta.setdocmeta!(PhysiCellModelManager, :DocTestSetup, :(using PhysiCellModelManager); recursive=true)
DocMeta.setdocmeta!(ModelManager, :DocTestSetup, :(using ModelManager); recursive=true)

makedocs(;
    modules=[PhysiCellModelManager, ModelManager],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="PhysiCellModelManager.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman-lab.github.io/PhysiCellModelManager.jl",
        edit_link="main",
        assets=String[],
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
        "Uncertainty Quantification" => Any[
            "Sensitivity analysis" => "man/sensitivity_analysis.md",
            "Calibration" => "man/calibration.md",
        ],
        "Analyzing Results" => Any[
            "Analyzing output" => "man/analyzing_output.md",
            "Querying parameters" => "man/querying_parameters.md",
        ],
        "Examples" => "man/examples.md",
        "Tools & Integrations" => Any[
            "PhysiCell Studio" => "man/physicell_studio.md",
        ],
        "Reference" => Any[
            "Best practices" => "man/best_practices.md",
            "Data directory" => "man/data_directory.md",
            "Project configuration" => "man/project_configuration.md",
            "Known limitations" => "man/known_limitations.md",
        ],
        "Contributing" => Any[
            "Developer guide" => "man/developer_guide.md",
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
                "variations.md", "ic_cell.md", "ic_ecm.md",
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
                "database.md", "deletion.md", "pruner.md", "up.md", "deprecate_keywords.md",
                "pcmm_version.md", "physicell_version.md", "physicell_studio.md",
            ]),
            "Alphabetical index" => "man/index.md",
        ],
        "Miscellaneous" => Any[
            "Database upgrades" => "misc/database_upgrades.md",
        ],
    ],
    checkdocs=:exports,
)

deploydocs(;
    repo="github.com/drbergman-lab/PhysiCellModelManager.jl",
    devbranch="main",
    push_preview=true,
)
