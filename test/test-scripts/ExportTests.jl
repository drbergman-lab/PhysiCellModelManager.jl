using LightXML

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

export_test(folder) = begin
    @test isdir(folder)
    @test isfile(joinpath(folder, "config", "PhysiCell_settings.xml"))
    @test isfile(joinpath(folder, "main.cpp"))
    @test isfile(joinpath(folder, "Makefile"))
    @test isfile(joinpath(folder, "custom_modules", "custom.cpp"))

    @test begin
        lines = readlines(joinpath(folder, "main.cpp"))
        return !any(contains.(lines, "argument_parser"))
    end

    @test begin
        lines = readlines(joinpath(folder, "custom_modules", "custom.cpp"))
        return !any(contains.(lines, "load_initial_cells"))
    end
end

export_folder = exportSimulation(1)
export_test(export_folder)

ic_cell_xml_folder = exportSimulation(simulation_with_ic_cell_xml_id)
export_test(ic_cell_xml_folder)

# make sim with ic substrate
config = "0_template"
custom_code = "0_template"
ic_substrate = "0_template"
inputs = InputFolders(config, custom_code; ic_substrate=ic_substrate)
dv = DiscreteVariation(["overall", "max_time"], 12)
out = run(inputs, dv)
@test out.trial isa Simulation
export_folder = exportSimulation(PhysiCellModelManager.trialID(out))
export_test(export_folder)

# make sim with ic ecm
config = "template-ecm"
custom_code = "template-ecm"
ic_ecm = "template-ecm"
inputs = InputFolders(config, custom_code; ic_ecm=ic_ecm)
dv = DiscreteVariation(["overall", "max_time"], 12)
out = run(inputs, dv)
@test out.trial isa Simulation
export_folder = exportSimulation(PhysiCellModelManager.trialID(out))
export_test(export_folder)

# make sim with id dc
config = "dirichlet_from_file"
custom_code = "dirichlet_from_file"
ic_dc = "dirichlet_from_file"
inputs = InputFolders(config, custom_code; ic_dc=ic_dc)
dv = DiscreteVariation(["overall", "max_time"], 12)
out = run(inputs, dv)
@test out.trial isa Simulation
export_folder = exportSimulation(PhysiCellModelManager.trialID(out))
export_test(export_folder)

# export with intracellulars
simulation_id = pcmm_output_intracellular |> simulationIDs |> first
path_to_exported_folder = exportSimulation(simulation_id, "IntracellularTestExport")
path_to_xml = joinpath(path_to_exported_folder, "config", "PhysiCell_settings.xml")
@test isfile(path_to_xml)
xml_doc = parse_file(path_to_xml)
path_to_intracellular = ["cell_definitions", "cell_definition:name:default", "phenotype", "intracellular"]
intracellular_element = PhysiCellModelManager.retrieveElement(xml_doc, path_to_intracellular)
@test attribute(intracellular_element, "type") == "roadrunner"
sbml_filename_element = find_element(intracellular_element, "sbml_filename")
@test !isnothing(sbml_filename_element)
filename = content(sbml_filename_element)
@test isfile(joinpath(path_to_exported_folder, filename))