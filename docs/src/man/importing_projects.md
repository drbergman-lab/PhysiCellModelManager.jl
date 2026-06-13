# Importing a project

If you already have a PhysiCell project in `PhysiCell/user_projects/` (or `PhysiCell/sample_projects/`), import it into your PhysiCellModelManager.jl project with [`importProject`](@ref):
```julia-repl
julia> importProject(path_to_project_folder)
```
`path_to_project_folder` can be an absolute path (recommended) or a path relative to where Julia was launched.

## Input files

`importProject` assumes the standard `PhysiCell/user_projects/` layout. The `Default directory` column is relative to `path_to_project_folder`.

| Input | Default directory | Default name | Key | Optional |
| --- | --- | --- | --- | :---: |
| config | `config` | `PhysiCell_settings.xml` | `config` | |
| main | `.` | `main.cpp` | `main` | |
| Makefile | `.` | `Makefile` | `makefile` | |
| custom modules | `.` | `custom_modules/` | `custom_modules` | |
| rules | `config` | `cell_rules.{csv,xml}` | `rulesets_collection` | X |
| cell initial conditions | `config` | `cells.csv` | `ic_cell` | X |
| substrate initial conditions | `config` | `substrates.csv` | `ic_substrate` | X |
| ECM initial conditions | `config` | `ecm.csv` | `ic_ecm` | X |
| DC initial conditions | `config` | `dcs.csv` | `ic_dc` | X |
| intracellular model | `config` | `intracellular.xml` | `intracellular` | X |

If a file is not in its standard location, pass a `src` dictionary keyed by the table above with paths **relative to the `Default directory`**. For example, if the config file is at `config/config.xml`:
```julia-repl
julia> src = Dict("config" => "config.xml")
julia> importProject(path_to_project_folder; src=src)
```
Add more entries as a comma-separated list in `Dict`, or later with `src[key] = rel_path`.

### Rulesets collection

The rulesets collection can be the base PhysiCell CSV or the `drbergman/PhysiCell` XML version. `importProject` looks for `cell_rules.csv` first, then `cell_rules.xml`.

### Intracellular models

If the `intracellular` key is not provided and `config/intracellular.xml` is not found, `importProject` reads the config file for any intracellular models and assembles `intracellular.xml` from them.

## Renaming the imported folders

After importing, update `scripts/GenerateData.jl` to reference the new project folders. By default, folder names come from the project name (with an integer appended if it already exists). To choose different names, pass a `dest` dictionary keyed as below:

| Output | Key |
| --- | --- |
| config | `config` |
| custom code | `custom_code` |
| rulesets collection | `rulesets_collection` |
| cell initial conditions | `ic_cell` |
| substrate initial conditions | `ic_substrate` |
| ECM initial conditions | `ic_ecm` |
| DC initial conditions | `ic_dc` |
| intracellular | `intracellular` |
