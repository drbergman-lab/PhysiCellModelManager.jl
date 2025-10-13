# Best practices

## Do NOT manually edit files inside `inputs`.
If parameter values need to be changed, use variations as shown in `scripts/GenerateData.jl`.
Let PhysiCellModelManager.jl manage the databases that track simulation parameters.

If you need to change the structure of an input file, e.g., adding a new rule or editing custom code, create an entire new subdirectory within the relevant `inputs` subdirectory.
If you anticipate doing a lot of this, consider using PhysiCell Studio for your first round of model development and refinement. <!-- PhysiCellModelDeveloper.jl could be made to address this though... -->

# Suggested practices

## Use `createProject` to create a new PCMM project.
This will create a new PCMM project directory with the necessary structure and files.
*Note: This is a distinct folder from a PhysiCell sample project or user project.*
If you do not want the template PhysiCell project copied over, use the keyword argument `template_as_default=false`, i.e.,
```julia-repl
createProject("MyNewProject"; template_as_default=false)
```

## Be slow to delete simulations and scripts.
PhysiCellModelManager.jl tracks simulations in a database so that it does not have to re-run simulations that have already been run.
This means that adding new simulations to a script and re-running the entire script, including on an HPC, will not run extraneous simulations.
Thus, the script can serve as a record of the simulations that have been run, and can be used to reproduce the results at a later date.

## Use version control on `inputs` and `scripts` directories.
Alone, these two directories along with the version of PhysiCell can be used to reproduce the results of a project.
The `createProject` function will create a `.gitignore` file in the data directory to make sure the appropriate files are tracked.
