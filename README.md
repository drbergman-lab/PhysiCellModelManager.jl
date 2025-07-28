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
3. Add the PCVCTRegistry:
```julia-repl
pkg> registry add https://github.com/drbergman/PCVCTRegistry
```
4. Install PhysiCellModelManager.jl:
```julia-repl
pkg> add PhysiCellModelManager
```
5. Create a new project:
```julia-repl
julia> using PhysiCellModelManager
julia> createProject()
```
6. Import a project:
```julia-repl
julia> initializeModelManager()
julia> importProject("path/to/project_folder") # replace with the path to your project folder
```
7. Check the output of Step 5 and record your input folders:
```julia-repl
julia> config_folder = "my_project" # replace these with the name from the output of Step 5
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
