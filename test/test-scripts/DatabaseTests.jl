using SQLite

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulationsTable()
simulation_ids = 1:5
printSimulationsTable(simulation_ids)

# test required folders
config_src_folder =  joinpath(pcvct.dataDir(), "inputs", "configs")
config_dest_folder = joinpath(pcvct.dataDir(), "inputs", "configs_")
mv(config_src_folder, config_dest_folder)

custom_code_src_folder =  joinpath(pcvct.dataDir(), "inputs", "custom_codes")
custom_code_dest_folder = joinpath(pcvct.dataDir(), "inputs", "custom_codes_")
mv(custom_code_src_folder, custom_code_dest_folder)

@test pcvct.createSchema() == false

mv(config_dest_folder, config_src_folder)
mv(custom_code_dest_folder, custom_code_src_folder)

# test bad table
table_name_not_end_in_s = "test"
@test_throws ErrorException pcvct.createPCVCTTable(table_name_not_end_in_s, "")
schema_without_primary_id = ""
@test_throws ErrorException pcvct.createPCVCTTable("simulations", schema_without_primary_id)

@test_throws ArgumentError pcvct.icFilename("ecm")

# misc tests
config_db = pcvct.variationsDatabase(:config, Simulation(1))
@test config_db isa SQLite.DB

ic_cell_db = pcvct.variationsDatabase(:ic_cell, Simulation(1))
@test ic_cell_db isa Missing

ic_ecm_db = pcvct.variationsDatabase(:ic_ecm, Simulation(1))
@test ic_ecm_db isa Nothing

pcvct.variationIDs(:config, Simulation(1))
pcvct.variationIDs(:config, Sampling(1))
pcvct.variationIDs(:rulesets_collection, Simulation(1))
pcvct.variationIDs(:rulesets_collection, Sampling(1))
pcvct.variationIDs(:ic_cell, Simulation(1))
pcvct.variationIDs(:ic_cell, Sampling(1))
pcvct.variationIDs(:ic_ecm, Simulation(1))
pcvct.variationIDs(:ic_ecm, Sampling(1))

pcvct.variationsTable(:config, Sampling(1); remove_constants=true)
pcvct.variationsTable(:rulesets_collection, Sampling(1); remove_constants=true)
pcvct.variationsTable(:ic_cell, Sampling(1); remove_constants=true)
pcvct.variationsTable(:ic_ecm, Sampling(1); remove_constants=true)

# test bad folder
path_to_bad_folder = joinpath(pcvct.dataDir(), "inputs", "configs", "bad_folder")
mkdir(path_to_bad_folder)

@test pcvct.reinitializeDatabase() == false

rm(path_to_bad_folder; force=true, recursive=true)
@test pcvct.initializeDatabase() == true