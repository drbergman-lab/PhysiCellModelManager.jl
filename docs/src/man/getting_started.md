# Your first project

Once PhysiCellModelManager.jl is installed (see [Installation](@ref)), this page walks you from an empty folder to your first simulations. Skim [Best practices](@ref) first.

## Create a project

Load the package and create a project:

```julia-repl
julia> using PhysiCellModelManager
julia> createProject() # uses the current directory by default
```

This creates three folders inside the project folder: `data/`, `PhysiCell/`, and `scripts/`. Pass a path to `createProject` to use a different folder. See [Data directory structure](@ref) for what lives in `data/`.

!!! note
    A PhysiCellModelManager.jl project is distinct from PhysiCell's `sample_projects` and `user_projects`.

Already have a PhysiCell project to bring in? See [Importing a project](@ref).

## Run your first trial

`createProject` puts a single script at `scripts/GenerateData.jl` (the folder and file names are convention — rename them freely). Run it from the shell:
```sh
julia scripts/GenerateData.jl
```
You can also run it from the REPL.

To parallelize the runs, set `PCMM_NUM_PARALLEL_SIMS` to the number of parallel simulations:
```sh
export PCMM_NUM_PARALLEL_SIMS=9
julia scripts/GenerateData.jl
```
Or as a one-off:
```sh
PCMM_NUM_PARALLEL_SIMS=9 julia scripts/GenerateData.jl
```

Run the script a second time: no new simulations run. PhysiCellModelManager.jl matches existing simulations before running new ones, so re-running a script is cheap. Use the `use_previous` keyword argument to override this.
