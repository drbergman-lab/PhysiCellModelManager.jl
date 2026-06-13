# Intracellular inputs

PhysiCellModelManager.jl currently supports only ODE intracellular models (via libRoadRunner). An `intracellular.xml` file maps cell definitions to intracellular models; the SBML files libRoadRunner needs are generated at PhysiCell runtime. See the [template file](https://github.com/drbergman/PhysiCell/blob/my-physicell/sample_projects_intracellular/combined/template-combined/config/sample_combined_sbmls.xml).

To build these files and mix-and-match models, place the SBML files defining your ODEs in `data/components/roadrunner` and reference them. For example, copy `Toy_Metabolic_Model.xml` from [sample\_projects\_intracellular/ode/ode\_energy/config/](https://github.com/drbergman/PhysiCell/blob/my-physicell/sample_projects_intracellular/ode/ode_energy/config) into `data/components/roadrunner` and assemble:

```julia
cell_type = "default" # name of the cell type using this intracellular model
component = PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml") # pass in the type of the component and the name of the file to use
cell_type_to_component = Dict{String, PhysiCellComponent}(cell_type => component) # add other entries to this Dict for other cell types using an intracellular model
intracellular_folder = assembleIntracellular!(cell_type_to_component; name="toy_metabolic") # will return "toy_metabolic" or "toy_metabolic_n"
```

This creates `data/inputs/intracellulars/$(intracellular_folder)/intracellular.xml`. The `!` in `assembleIntracellular!` signals that the components in `cell_type_to_component` are updated in place to match those written to the XML. Use their IDs to vary the components:

```julia
xml_path = ["intracellulars", "intracellular:ID:$(component.id)", ...]
```

where the `...` is the path starting with the root of the XML file (`sbml` for SBML files).

Finally, pass this folder into `InputFolders` to use this input in simulation runs:
```julia
inputs = InputFolders(...; ..., intracellular=intracellular_folder, ...)
```