# [Intracellular inputs](@id intracellular_inputs_man)
Assemble an `intracellular.xml` that maps cell definitions to intracellular models, and vary its parameters like any other input.

!!! tiergloss
    PhysiCellModelManager.jl currently supports only ODE intracellular models (via libRoadRunner).
    Put the SBML files defining your ODEs in `data/components/roadrunner`, name one in a
    [`PhysiCellComponent`](@ref), and hand
    [`assembleIntracellular!`](@ref) a dictionary from cell type to the components it uses. It writes
    `data/inputs/intracellulars/$(intracellular_folder)/intracellular.xml` and returns the folder
    name, which goes into [`InputFolders`](@ref).

!!! tierwhy
    The SBML files libRoadRunner needs are generated at PhysiCell runtime, so what PhysiCell reads is
    one assembled XML file; see the
    [template file](https://github.com/drbergman/PhysiCell/blob/my-physicell/sample_projects_intracellular/combined/template-combined/config/sample_combined_sbmls.xml)
    for its shape. Assembling it here is what lets you mix and match models per cell type without
    editing XML by hand. The example below uses `Toy_Metabolic_Model.xml`, copied into
    `data/components/roadrunner` from
    [sample\_projects\_intracellular/ode/ode\_energy/config/](https://github.com/drbergman/PhysiCell/blob/my-physicell/sample_projects_intracellular/ode/ode_energy/config).

    The `!` is there because [`assembleIntracellular!`](@ref) assigns each component an ID and writes
    the updated components back into the dictionary you passed. Read the ID from the dictionary
    afterwards to build an XML path into the assembled file: the `...` continues from the root of the
    component's own file (`sbml`, for SBML). Re-assembling the same components returns the existing
    folder rather than making a new one, with the IDs that folder already uses.

```julia
cell_type = "default"                                               # cell type using this model
component = PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml")   # component type, file name
cell_type_to_components = Dict(cell_type => [component])            # add an entry per cell type

intracellular_folder = assembleIntracellular!(cell_type_to_components; name="toy_metabolic")

id = cell_type_to_components[cell_type][1].id                       # the ID assembly assigned
xml_path = ["intracellulars", "intracellular:ID:$(id)", "sbml", ...]  # ... = path within the SBML file

inputs = InputFolders(...; ..., intracellular=intracellular_folder, ...)
```

!!! tierdev
    [`PhysiCellComponent`](@ref) is immutable and carries three fields: `type` (the subdirectory of
    `data/components/`, currently only `"roadrunner"`), `name` (the file inside it), and `id`. Only
    `type` and `name` participate in equality, because `id` is assigned during assembly — a freshly
    constructed component holds `-1` to mean "not yet set". [`assembleIntracellular!`](@ref) cannot
    therefore update a component in place; it replaces each *dictionary entry* with a vector of
    copies carrying the ids it wrote into the XML. So read the id back from the dictionary, as above:
    a variable still bound to the component you constructed keeps `-1`. A dictionary whose values are
    bare components rather than vectors is accepted, but it is wrapped in a temporary
    `Dict{String,Vector{PhysiCellComponent}}` first, and only that temporary is updated.
