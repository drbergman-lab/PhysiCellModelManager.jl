using SQLite

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulationsTable()
simulation_ids = 1:5
printSimulationsTable(simulation_ids)

# test required folders
config_src_folder =  joinpath(PhysiCellModelManager.dataDir(), "inputs", "configs")
config_dest_folder = joinpath(PhysiCellModelManager.dataDir(), "inputs", "configs_")
mv(config_src_folder, config_dest_folder)

custom_code_src_folder =  joinpath(PhysiCellModelManager.dataDir(), "inputs", "custom_codes")
custom_code_dest_folder = joinpath(PhysiCellModelManager.dataDir(), "inputs", "custom_codes_")
mv(custom_code_src_folder, custom_code_dest_folder)

@test_throws AssertionError PhysiCellModelManager.createSchema()
@test initializeModelManager() == false

mv(config_dest_folder, config_src_folder)
mv(custom_code_dest_folder, custom_code_src_folder)

@test initializeModelManager() == true

# test bad table
table_name_not_end_in_s = "test"
@test_throws ErrorException PhysiCellModelManager.createPCMMTable(table_name_not_end_in_s, "")
schema_without_primary_id = ""
@test_throws ErrorException PhysiCellModelManager.createPCMMTable("simulations", schema_without_primary_id)

@test_throws ArgumentError PhysiCellModelManager.icFilename("ecm")

# misc tests
config_db = PhysiCellModelManager.locationVariationsDatabase(:config, Simulation(1))
@test config_db isa SQLite.DB

ic_cell_db = PhysiCellModelManager.locationVariationsDatabase(:ic_cell, Simulation(1))
@test ic_cell_db isa Missing

ic_ecm_db = PhysiCellModelManager.locationVariationsDatabase(:ic_ecm, Simulation(1))
@test ic_ecm_db isa Nothing

PhysiCellModelManager.variationIDs(:config, Simulation(1))
PhysiCellModelManager.variationIDs(:config, Sampling(1))
PhysiCellModelManager.variationIDs(:rulesets_collection, Simulation(1))
PhysiCellModelManager.variationIDs(:rulesets_collection, Sampling(1))
PhysiCellModelManager.variationIDs(:ic_cell, Simulation(1))
PhysiCellModelManager.variationIDs(:ic_cell, Sampling(1))
PhysiCellModelManager.variationIDs(:ic_ecm, Simulation(1))
PhysiCellModelManager.variationIDs(:ic_ecm, Sampling(1))

PhysiCellModelManager.locationVariationsTable(:config, Sampling(1); remove_constants=true)
PhysiCellModelManager.locationVariationsTable(:rulesets_collection, Sampling(1); remove_constants=true)
PhysiCellModelManager.locationVariationsTable(:ic_cell, Sampling(1); remove_constants=true)
PhysiCellModelManager.locationVariationsTable(:ic_ecm, Sampling(1); remove_constants=true)

# test bad folder
path_to_bad_folder = joinpath(PhysiCellModelManager.dataDir(), "inputs", "configs", "bad_folder")
mkdir(path_to_bad_folder)

@test PhysiCellModelManager.reinitializeDatabase() == false

rm(path_to_bad_folder; force=true, recursive=true)
@test PhysiCellModelManager.initializeDatabase() == true

# test stmtToDataFrame error
stmt_str = "SELECT * FROM simulations WHERE simulation_id = :simulation_id;"
bad_params = (; :simulation_id => -1)
@test_throws AssertionError PhysiCellModelManager.stmtToDataFrame(stmt_str, bad_params; is_row=true)
