using PhysiCellXMLRules

"""
    upgradePCVCT(from_version::VersionNumber, to_version::VersionNumber, auto_upgrade::Bool)

Upgrade the PCVCT database from one version to another.

The upgrade process is done in steps, where each step corresponds to a milestone version.
The function will apply all necessary upgrades until the target version is reached.
If `auto_upgrade` is true, the function will automatically apply all upgrades without prompting.
Otherwise, it will prompt the user for confirmation before large upgrades.
"""
function upgradePCVCT(from_version::VersionNumber, to_version::VersionNumber, auto_upgrade::Bool)
    println("Upgrading pcvct from version $(from_version) to $(to_version)...")
    milestone_versions = [v"0.0.1", v"0.0.3", v"0.0.10", v"0.0.11", v"0.0.13", v"0.0.15", v"0.0.16", v"0.0.24"]
    next_milestone_inds = findall(x -> from_version < x, milestone_versions) #! this could be simplified to take advantage of this list being sorted, but who cares? It's already so fast
    next_milestones = milestone_versions[next_milestone_inds]
    success = true
    for next_milestone in next_milestones
        up_fn_symbol = Meta.parse("upgradeToV$(replace(string(next_milestone), "." => "_"))")
        if !isdefined(pcvct, up_fn_symbol)
            throw(ArgumentError("Upgrade from version $(from_version) to $(next_milestone) not supported."))
        end
        success = eval(up_fn_symbol)(auto_upgrade)
        if !success
            break
        else
            DBInterface.execute(centralDB(), "UPDATE pcvct_version SET version='$(next_milestone)';")
        end
    end
    if success && to_version > milestone_versions[end]
        println("\t- Upgrading to version $(to_version)...")
        DBInterface.execute(centralDB(), "UPDATE pcvct_version SET version='$(to_version)';")
    end
    return success
end

"""
    populateTableOnFeatureSubset(db::SQLite.DB, source_table::String, target_table::String; column_mapping::Dict{String, String}=Dict{String,String}())

Populate a target table with data from a source table, using a column mapping if provided.
"""
function populateTableOnFeatureSubset(db::SQLite.DB, source_table::String, target_table::String; column_mapping::Dict{String, String}=Dict{String,String}())
    source_columns = queryToDataFrame("PRAGMA table_info($(source_table));") |> x -> x[!, :name]
    target_columns = [haskey(column_mapping, c) ? column_mapping[c] : c for c in source_columns]
    insert_into_cols = "(" * join(target_columns, ",") * ")"
    select_cols = join(source_columns, ",")
    query = "INSERT INTO $(target_table) $(insert_into_cols) SELECT $(select_cols) FROM $(source_table);"
    DBInterface.execute(db, query)
end

"""
    upgradeToX_Y_Z(auto_upgrade::Bool)

Upgrade the database to pcvct version X.Y.Z. Each milestone version has its own upgrade function.
"""
function upgradeToVX_Y_Z end

function upgradeToV0_0_1(::Bool)
    println("\t- Upgrading to version 0.0.1...")
    data_dir_contents = readdir(joinpath(dataDir(), "inputs"); sort=false)
    if "rulesets_collections" in data_dir_contents
        rulesets_collection_folders = readdir(locationPath(:rulesets_collection); sort=false) |> filter(x -> isdir(locationPath(:rulesets_collection, x)))
        for rulesets_collection_folder in rulesets_collection_folders
            path_to_rulesets_collection_folder = locationPath(:rulesets_collection, rulesets_collection_folder)
            path_to_rulesets_variations_db = joinpath(path_to_rulesets_collection_folder, "rulesets_variations.db")
            if !isfile(joinpath(path_to_rulesets_variations_db))
                continue
            end
            db_rulesets_variations = SQLite.DB(path_to_rulesets_variations_db)
            df = DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_variations (rulesets_collection_variation_id) VALUES(0) RETURNING rulesets_collection_variation_id;") |> DataFrame
            if isempty(df)
                continue
            end
            column_names = queryToDataFrame("PRAGMA table_info(rulesets_variations);"; db=db_rulesets_variations) |> x -> x[!, :name]
            filter!(x -> x != "rulesets_collection_variation_id", column_names)
            path_to_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
            if !isfile(path_to_xml)
                writeXMLRules(path_to_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
            end
            xml_doc = parse_file(path_to_xml)
            for column_name in column_names
                xml_path = columnNameToXMLPath(column_name)
                base_value = getContent(xml_doc, xml_path)
                query = "UPDATE rulesets_variations SET '$(column_name)'=$(base_value) WHERE rulesets_collection_variation_id=0;"
                DBInterface.execute(db_rulesets_variations, query)
            end
            free(xml_doc)
        end
    end
    return true
end

function upgradeToV0_0_3(auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version 0.0.3...
    \nWARNING: Upgrading to version 0.0.3 will change the database schema.
    See info at https://drbergman.github.io/pcvct/stable/misc/database_upgrades/

    ------IF ANOTHER INSTANCE OF PCVCT IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version 0.0.3? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version 0.0.3 aborted.")
        return false
    end
    println("\t- Upgrading to version 0.0.3...")
    #! first get vct.db right changing simulations and monads tables
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='config_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations RENAME COLUMN variation_id TO config_variation_id;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='config_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads RENAME COLUMN variation_id TO config_variation_id;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='ic_cell_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations ADD COLUMN ic_cell_variation_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE simulations SET ic_cell_variation_id=CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='ic_cell_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads ADD COLUMN ic_cell_variation_id INTEGER;")
        DBInterface.execute(centralDB(), "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(centralDB(), "UPDATE monads_temp SET ic_cell_variation_id=CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END;")
        DBInterface.execute(centralDB(), "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        #! drop the previous unique constraint on monads
        #! insert from monads_temp all values except ic_cell_variation_id (set that to -1 if ic_cell_id is -1 and to 0 if ic_cell_id is not -1)
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end

    #! now get the config_variations.db's right
    config_folders = queryToDataFrame(constructSelectQuery("configs"; selection="folder_name")) |> x -> x.folder_name
    for config_folder in config_folders
        path_to_config_folder = locationPath(:config, config_folder)
        if !isfile(joinpath(path_to_config_folder, "variations.db"))
            continue
        end
        #! rename all "variation" to "config_variation" in filenames and in databases
        old_db_file = joinpath(path_to_config_folder, "variations.db")
        db_file = joinpath(path_to_config_folder, "config_variations.db")
        if isfile(old_db_file)
            mv(old_db_file, db_file)
        end
        db_config_variations = db_file |> SQLite.DB
        #! check if variations is a table name in the database
        if DBInterface.execute(db_config_variations, "SELECT name FROM sqlite_master WHERE type='table' AND name='variations';") |> DataFrame |> x -> (length(x.name)==1)
            DBInterface.execute(db_config_variations, "ALTER TABLE variations RENAME TO config_variations;")
        end
        if DBInterface.execute(db_config_variations, "SELECT 1 FROM pragma_table_info('config_variations') WHERE name='config_variation_id';") |> DataFrame |> isempty
            DBInterface.execute(db_config_variations, "ALTER TABLE config_variations RENAME COLUMN variation_id TO config_variation_id;")
        end
        index_df = DBInterface.execute(db_config_variations, "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type = 'index';") |> DataFrame
        variations_index = index_df[!, :name] .== "variations_index"
        if any(variations_index)
            variations_sql = index_df[variations_index, :sql][1]
            cols = split(variations_sql, "(")[2]
            cols = split(cols, ")")[1]
            cols = split(cols, ",") .|> string .|> x -> strip(x, '"')
            SQLite.createindex!(db_config_variations, "config_variations", "config_variations_index", cols; unique=true, ifnotexists=false)
            SQLite.dropindex!(db_config_variations, "variations_index")
        end
        old_folder = joinpath(path_to_config_folder, "variations")
        new_folder = joinpath(path_to_config_folder, "config_variations")
        if isdir(old_folder)
            mv(old_folder, new_folder)
            for file in readdir(new_folder)
                mv(joinpath(new_folder, file), joinpath(new_folder, "config_$(file)"))
            end
        end
    end
    return true
end

function upgradeToV0_0_10(auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version 0.0.10...
    \nWARNING: Upgrading to version 0.0.10 will change the database schema.
    See info at https://github.com/drbergman/pcvct?tab=readme-ov-file#to-v0010

    ------IF ANOTHER INSTANCE OF PCVCT IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version 0.0.10? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version 0.0.10 aborted.")
        return false
    end
    println("\t- Upgrading to version 0.0.10...")

    createPCVCTTable("physicell_versions", physicellVersionsSchema())
    pcvct_globals.current_physicell_version_id = resolvePhysiCellVersionID()

    println("\t\tPhysiCell version: $(physicellInfo())")
    println("\n\t\tAssuming all output has been generated with this version...")

    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='physicell_version_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations ADD COLUMN physicell_version_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE simulations SET physicell_version_id=$(currentPhysiCellVersionID());")
    end

    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='physicell_version_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads ADD COLUMN physicell_version_id INTEGER;")
        DBInterface.execute(centralDB(), "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(centralDB(), "UPDATE monads_temp SET physicell_version_id=$(currentPhysiCellVersionID());")
        DBInterface.execute(centralDB(), "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end

    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('samplings') WHERE name='physicell_version_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE samplings ADD COLUMN physicell_version_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE samplings SET physicell_version_id=$(currentPhysiCellVersionID());")
    end
    return true
end

function upgradeToV0_0_11(::Bool)
    println("\t- Upgrading to version 0.0.11...")
    query = constructSelectQuery("samplings")
    samplings_df = queryToDataFrame(query)
    for row in eachrow(samplings_df)
        if !ismissing(row.physicell_version_id)
            continue
        end
        monads = getMonadIDs(Sampling(row.sampling_id))
        query = constructSelectQuery("monads", "WHERE monad_id IN ($(join(monads, ",")))"; selection="physicell_version_id")
        monads_df = queryToDataFrame(query)
        monad_physicell_versions = monads_df.physicell_version_id |> unique
        if length(monad_physicell_versions) == 1
            DBInterface.execute(centralDB(), "UPDATE samplings SET physicell_version_id=$(monad_physicell_versions[1]) WHERE sampling_id=$(row.sampling_id);")
        else
            println("WARNING: Multiple PhysiCell versions found for monads in sampling $(row.sampling_id). Not setting the sampling PhysiCell version.")
        end
    end
end

function upgradeToV0_0_13(::Bool)
    println("\t- Upgrading to version 0.0.13...")
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
    end
    rulesets_collection_folders = queryToDataFrame(constructSelectQuery("rulesets_collections"; selection="folder_name")) |> x -> x.folder_name
    for rulesets_collection_folder in rulesets_collection_folders
        path_to_rulesets_collection_folder = locationPath(:rulesets_collection, rulesets_collection_folder)
        path_to_new_db = joinpath(path_to_rulesets_collection_folder, "rulesets_collection_variations.db")
        if isfile(path_to_new_db)
            continue
        end
        path_to_old_db = joinpath(path_to_rulesets_collection_folder, "rulesets_variations.db")
        if !isfile(path_to_old_db)
            error("Could not find a rulesets collection variation database file in $(path_to_rulesets_collection_folder).")
        end
        mv(path_to_old_db, path_to_new_db)
        db_rulesets_collection_variations = SQLite.DB(path_to_new_db)
        if DBInterface.execute(db_rulesets_collection_variations, "SELECT name FROM sqlite_master WHERE type='table' AND name='rulesets_variations';") |> DataFrame |> x -> (length(x.name)==1)
            DBInterface.execute(db_rulesets_collection_variations, "ALTER TABLE rulesets_variations RENAME TO rulesets_collection_variations;")
        end
        if !(DBInterface.execute(db_rulesets_collection_variations, "SELECT 1 FROM pragma_table_info('rulesets_collection_variations') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty)
            DBInterface.execute(db_rulesets_collection_variations, "ALTER TABLE rulesets_collection_variations RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
        end
    end
end

function upgradeToV0_0_15(auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version 0.0.15...
    \nWARNING: Upgrading to version 0.0.15 will change the database schema.
    See info at https://drbergman.github.io/pcvct/stable/misc/database_upgrades/

    ------IF ANOTHER INSTANCE OF PCVCT IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version 0.0.15? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version 0.0.15 aborted.")
        return false
    end
    println("\t- Upgrading to version 0.0.15...")

    #! first include ic_ecm_variation_id in simulations and monads tables
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='ic_ecm_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations ADD COLUMN ic_ecm_variation_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE simulations SET ic_ecm_variation_id=CASE WHEN ic_ecm_id=-1 THEN -1 ELSE 0 END;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='ic_ecm_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads ADD COLUMN ic_ecm_variation_id INTEGER;")
        DBInterface.execute(centralDB(), "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(centralDB(), "UPDATE monads_temp SET ic_ecm_variation_id=CASE WHEN ic_ecm_id=-1 THEN -1 ELSE 0 END;")
        DBInterface.execute(centralDB(), "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end

    #! now add ic_dc_id to simulations and monads tables
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='ic_dc_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations ADD COLUMN ic_dc_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE simulations SET ic_dc_id=-1;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='ic_dc_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads ADD COLUMN ic_dc_id INTEGER;")
        DBInterface.execute(centralDB(), "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(centralDB(), "UPDATE monads_temp SET ic_dc_id=-1;")
        DBInterface.execute(centralDB(), "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end
    return true
end

function upgradeToV0_0_16(auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version 0.0.16...
    \nWARNING: Upgrading to version 0.0.16 will change the database schema.
    See info at https://drbergman.github.io/pcvct/stable/misc/database_upgrades/

    ------IF ANOTHER INSTANCE OF PCVCT IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version 0.0.16? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version 0.0.16 aborted.")
        return false
    end
    println("\t- Upgrading to version 0.0.16...")

    #! add intracellular_id and intracellular_variation_id to simulations and monads tables
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('simulations') WHERE name='intracellular_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE simulations ADD COLUMN intracellular_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE simulations SET intracellular_id=-1;")
        DBInterface.execute(centralDB(), "ALTER TABLE simulations ADD COLUMN intracellular_variation_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE simulations SET intracellular_variation_id=-1;")
    end
    if DBInterface.execute(centralDB(), "SELECT 1 FROM pragma_table_info('monads') WHERE name='intracellular_id';") |> DataFrame |> isempty
        DBInterface.execute(centralDB(), "ALTER TABLE monads ADD COLUMN intracellular_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE monads SET intracellular_id=-1;")
        DBInterface.execute(centralDB(), "ALTER TABLE monads ADD COLUMN intracellular_variation_id INTEGER;")
        DBInterface.execute(centralDB(), "UPDATE monads SET intracellular_variation_id=-1;")
        DBInterface.execute(centralDB(), "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(centralDB(), "UPDATE monads_temp SET intracellular_id=-1;")
        DBInterface.execute(centralDB(), "UPDATE monads_temp SET intracellular_variation_id=-1;")
        DBInterface.execute(centralDB(), "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end
    return true
end

function upgradeToV0_0_24(::Bool)
    println("\t- Upgrading to version 0.0.24...")
    
    #! v0.0.23 accidentally used the capitalized version of these CSV file names
    monads_folder = joinpath(dataDir(), "outputs", "monads")
    folders = readdir(monads_folder; sort=false) |> filter(x -> isdir(joinpath(monads_folder, x)))
    for folder in folders
        if isfile(joinpath(monads_folder, folder, "Simulations.csv"))
            dst = joinpath(monads_folder, folder, "simulations.csv")
            @assert !isfile(dst) "$(dst) exists alongside Simulations.csv. Please manually select which one to keep.\nUpgrade to version 0.0.24 aborted."
            mv(joinpath(monads_folder, folder, "Simulations.csv"), dst)
        end
    end

    samplings_folder = joinpath(dataDir(), "outputs", "samplings")
    folders = readdir(samplings_folder; sort=false) |> filter(x -> isdir(joinpath(samplings_folder, x)))
    for folder in folders
        if isfile(joinpath(samplings_folder, folder, "Monads.csv"))
            dst = joinpath(samplings_folder, folder, "monads.csv")
            @assert !isfile(dst) "$(dst) exists alongside Monads.csv. Please manually select which one to keep.\nUpgrade to version 0.0.24 aborted."
            mv(joinpath(samplings_folder, folder, "Monads.csv"), dst)
        end
    end

    trials_folder = joinpath(dataDir(), "outputs", "trials")
    folders = readdir(trials_folder; sort=false) |> filter(x -> isdir(joinpath(trials_folder, x)))
    for folder in folders
        if isfile(joinpath(trials_folder, folder, "Samplings.csv"))
            dst = joinpath(trials_folder, folder, "samplings.csv")
            @assert !isfile(dst) "$(dst) exists alongside Samplings.csv. Please manually select which one to keep.\nUpgrade to version 0.0.24 aborted."
            mv(joinpath(trials_folder, folder, "Samplings.csv"), dst)
        end
    end
end