# Getting started
Read [Best practices](@ref) before using PhysiCellModelManager.jl.
## Install PhysiCellModelManager.jl
### Download julia
The easiest way to install julia is to use the command line. On Linux and MacOS, you can run:
```sh
$ curl -fsSL https://install.julialang.org | sh
```

On Windows, you can run:
```powershell
> winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore
```

Note: this command also installs the [JuliaUp](https://github.com/JuliaLang/juliaup) installation manager, which will automatically install julia and help keep it up to date.

See [here](https://julialang.org/install) for the Julia installation home page. See [here](https://julialang.org/downloads/) for more download options.

### Add the PCVCTRegistry
Launch julia by running `julia` in a shell.
Then, enter the Pkg REPL by pressing `]`.
Finally, add the PCVCTRegistry by running:
```julia-repl
pkg> registry add https://github.com/drbergman/PCVCTRegistry
```

### Install PhysiCellModelManager.jl
Still in the Pkg REPL, run:
```julia-repl
pkg> add PhysiCellModelManager
```

Troubleshoot: If this fails, it may be because the General registry is not set up correctly. The output of `] registry status` should show the PCVCTRegistry and General registry. If it does not, you can add the General registry by running:
```julia-repl
pkg> registry add General
```

## Set up a PhysiCellModelManager.jl project
Leave the Pkg REPL by pressing the `delete` or `backspace` key (if still in it from the previous step).
Load the PhysiCellModelManager.jl module by running:
```julia-repl
julia> using PhysiCellModelManager
```
Then, create a new project by running:
```julia-repl
julia> createProject(path_to_project_folder) # createProject() will use the current directory as the project folder
```
This creates three folders inside the `path_to_project_folder` folder: `data/`, `PhysiCell/`, and `VCT/`.
See [Data directory structure](@ref) for information about the `data/` folder.

## (Optional) Import from `user_projects`
### Inputs
If you have a project in the `PhysiCell/user_projects/` folder that you would like to import, you can do so by running [`importProject`](@ref):
```julia-repl
julia> importProject(path_to_project_folder)
```
The `path_to_project_folder` string can be either the absolute path (recommended) or the relative path (from the directory julia was launched) to the project folder.

Note: This function assumes your project files are in the standard `PhysiCell/user_projects/` format.
See the table below for the standard locations of the files.
Note the `Default location` column shows the path relative to `path_to_project_folder`.

| Input | Default location | Key | Optional |
| --- | --- | --- | :---: |
| config | `config/PhysiCell_settings.xml` | `config` | |
| main | `main.cpp` | `main` | |
| Makefile | `Makefile` | `makefile` | |
| custom modules | `custom_modules/` | `custom_modules` | |
| rules | `config/cell_rules.csv` | `rules` | X |
| cell initial conditions | `config/cells.csv` | `ic_cell` | X |
| substrate initial conditions | `config/substrates.csv` | `ic_substrate` | X |

If any of these files are not located in the standard location, you can define a dictionary with keys taken from the table above to specify the location of each file.
For example, if the config file is instead located at `PhysiCell/user_projects/[project_name]/config/config.xml`, you would run:
```julia-repl
julia> src = Dict("config" => "config/config.xml")
```
Additional entries can be added in a comma-separated list into `Dict` or added later with `src[key] = rel_path`.
Pass the dictionary in as the second argument as follows:
```julia-repl
julia> importProject(path_to_project_folder, src)
```

### Outputs
If you use this option, then the GenerateData.jl script must be updated to reflect the new project folders.
By default, the folder names are taken from the name of the project with an integer appended if it already exists.
If you want to use a different name, you can pass 

## Running first trial
The `createProject()` command creates three folder, including a `VCT` folder with a single file: `VCT/GenerateData.jl`.
The name of this folder and this file are purely convention, change them as you like.
To run your first PhysiCellModelManager.jl trial, you can run the GenerateData.jl script from the shell:
```sh
$ julia VCT/GenerateData.jl
```
Note: if you want to parallelize these 9 runs, you can set the shell environment variable `PCMM_NUM_PARALLEL_SIMS` to the number of parallel simulations you want to run. For example, to run 9 parallel simulations, you would run:
```sh
$ export PCMM_NUM_PARALLEL_SIMS=9
$ julia VCT/GenerateData.jl
```
Or for a one-off solution:
```sh
$ PCMM_NUM_PARALLEL_SIMS=9 julia VCT/GenerateData.jl
```
Alternatively, you can run the script via the REPL.

Run the script a second time and observe that no new simulations are run.
This is because PhysiCellModelManager.jl looks for matching simulations first before running new ones.
The `use_previous` optional keyword argument can control this behavior if new simulations are desired.