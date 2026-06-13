# Best practices

## Do NOT manually edit files inside `inputs`.
If parameter values need to be changed, use variations as shown in `scripts/GenerateData.jl`.
Let PhysiCellModelManager.jl manage the databases that track simulation parameters.

If you need to change the structure of an input file, e.g., adding a new rule or editing custom code, create an entire new subdirectory within the relevant `inputs` subdirectory.
If you anticipate doing a lot of this, consider using PhysiCell Studio for your first round of model development and refinement. <!-- PhysiCellModelDeveloper.jl could be made to address this though... -->

# Suggested practices

## Use [`createProject`](@ref) to create a new PCMM project.
[`createProject`](@ref) will create a new PCMM project directory with the necessary structure and files.
*Note: This is a distinct folder from a PhysiCell sample project or user project.*
If you do not want the template PhysiCell project copied over, use the keyword argument `template_as_default=false`, i.e.,
```julia-repl
createProject("MyNewProject"; template_as_default=false)
```

## Be slow to delete simulations and scripts.
PhysiCellModelManager.jl tracks simulations in a database and skips re-running ones that already exist — so adding simulations to a script and re-running it (including on an HPC) runs only the new ones. A script thus doubles as a record you can use to reproduce results later.

If you must delete simulations manually — e.g. after an error left a stale database record — use [`deleteSimulations`](@ref) so the database stays consistent.

## Use a dedicated Julia environment.
Keep each project's dependencies in its own environment and commit `Project.toml` and `Manifest.toml`. See [Julia environments](@ref).

## Use version control on `inputs` and `scripts` directories.
These two directories plus the PhysiCell version are enough to reproduce a project. `createProject` adds a `.gitignore` in the data directory so the right files are tracked.
