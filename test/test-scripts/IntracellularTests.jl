filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config = "template-combined"
custom_code = "template-combined"
cell_to_components_dict = Dict("default" => PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml"))
intracellular = assembleIntracellular!(cell_to_components_dict; name="template-combined")
inputs = InputFolders(config, custom_code; intracellular=intracellular)

dv1 = DiscreteVariation(["overall", "max_time"], 12.0)
xml_path = ["intracellulars", "intracellular:ID:1", "sbml", "model", "listOfReactions", "reaction:id:Aerobic", "kineticLaw", "math", "apply", "apply", "cn"]
dv2 = DiscreteVariation(xml_path, [5, 6])
pcvct_output_intracellular = run(inputs, [dv1, dv2]) #! save for later use
@test pcvct_output_intracellular.n_success == 2

macros_lines = pcvct.readMacrosFile(pcvct_output_intracellular.trial)
@test "ADDON_ROADRUNNER" in macros_lines

#! more test coverage
new_intracellular = assembleIntracellular!(cell_to_components_dict; name="template-combined")
@test intracellular == new_intracellular #! should not need to make a new folder, the assembly.toml file should show they match