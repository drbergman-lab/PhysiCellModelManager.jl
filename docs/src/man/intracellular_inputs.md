# Intracellular inputs

PhysiCellModelManager.jl currently only supports ODE intracellular models using libRoadRunner.
It uses a specialized format to achieve this, creating the SBML files needed by libRoadRunner at PhysiCell runtime.
Briefly, the `intracellular.xml` file defines a mapping between cell definitions and intracellular models.
See the template provided [here](https://github.com/drbergman/PhysiCell/blob/my-physicell/sample_projects_intracellular/combined/template-combined/config/sample_combined_sbmls.xml).

To facilitate creation of such files, and to make it easy to mix-and-match intracellular models, users can place the SBML files that define the ODEs into `data/components/roadrunner` and then simply reference those to construct the specialized XMLs needed.
For example, place the `Toy_Metabolic_Model.xml` from [sample_projects_intracellular/ode/ode_energy/config/](https://github.com/drbergman/PhysiCell/blob/my-physicell/sample_projects_intracellular/ode/ode_energy/config) into `data/components/roadrunner` and assemble the XML as follows

```julia
cell_type = "default" # name of the cell type using this intracellular model
component = PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml") # pass in the type of the component and the name of the file to use
cell_type_to_component = Dict{String, PhysiCellComponent}(cell_type => component) # add other entries to this Dict for other cell types using an intracellular model
intracellular_folder = assembleIntracellular!(cell_type_to_component; name="toy_metabolic") # will return "toy_metabolic" or "toy_metabolic_n"
```

This creates a folder at `data/inputs/intracellulars/` with the name stored in `intracellular_folder`.
Also, the `!` in `assembleIntracellular!` references how the components in the `cell_type_to_component` `Dict` are updated to match those in `data/inputs/intracellulars/$(intracellular_folder)/intracellular.xml`.
Use these IDs to make variations on the components by using

```julia
xml_path = ["intracellulars", "intracellular:ID:$(component.id)", ...]
```

where the `...` is the path starting with the root of the XML file (`sbml` for SBML files).

Finally, pass this folder into `InputFolders` to use this input in simulation runs:
```julia
inputs = InputFolders(...; ..., intracellular=intracellular_folder, ...)
```