using Documenter, PhysiCellModelManager

DocMeta.setdocmeta!(PhysiCellModelManager, :DocTestSetup, :(using PhysiCellModelManager); recursive=true)

makedocs(;
    modules=[PhysiCellModelManager],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="PhysiCellModelManager.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman-lab.github.io/PhysiCellModelManager.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Manual" => Any[
            "Best practices" => "man/best_practices.md",
            "Getting started" => "man/getting_started.md",
            "Varying parameters" => "man/varying_parameters.md",
            "XML path helpers" => "man/xml_path_helpers.md",
            "CoVariations" => "man/covariations.md",
            "Data directory" => "man/data_directory.md",
            "Intracellular inputs" => "man/intracellular_inputs.md",
            "Known limitations" => "man/known_limitations.md",
            "PhysiCell Studio" => "man/physicell_studio.md",
            "Sensitivity analysis" => "man/sensitivity_analysis.md",
            "Analyzing output" => "man/analyzing_output.md",
            "Developer guide" => "man/developer_guide.md",
            "Index" => "man/index.md",
        ],
        "Documentation" => map(
            s -> "lib/$(s)",
            sort(readdir(joinpath(@__DIR__, "src/lib")))
        ),
        "Miscellaneous" => Any[
            "Database upgrades" => "misc/database_upgrades.md",
        ],
    ],
)

deploydocs(;
    repo="github.com/drbergman-lab/PhysiCellModelManager.jl",
    devbranch="development",
    push_preview=true,
)
