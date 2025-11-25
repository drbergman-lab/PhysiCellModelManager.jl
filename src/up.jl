using PhysiCellXMLRules

const pcmm_milestones = [v"0.0.1", v"0.0.3", v"0.0.10", v"0.0.11", v"0.0.13", v"0.0.15", v"0.0.16", v"0.0.25", v"0.0.29", v"0.0.30", v"0.1.3", v"0.2.0"]
const upgrade_fns = Dict{VersionNumber, Function}()

macro up_fns()
    pairs_exprs = Expr[]
    for version in pcmm_milestones
        fn_name = Symbol("upgradeToV$(replace(string(version), "." => "_"))")
        push!(pairs_exprs, :( upgrade_fns[$(version)] = $(fn_name) ))
    end
    quote
        $(pairs_exprs...)
    end
end

"""
    upgradePCMM(from_version::VersionNumber, to_version::VersionNumber, auto_upgrade::Bool)

Upgrade the PhysiCellModelManager.jl database from one version to another.

The upgrade process is done in steps, where each step corresponds to a milestone version.
The function will apply all necessary upgrades until the target version is reached.
If `auto_upgrade` is true, the function will automatically apply all upgrades without prompting.
Otherwise, it will prompt the user for confirmation before large upgrades.
"""
function upgradePCMM(from_version::VersionNumber, to_version::VersionNumber, auto_upgrade::Bool)
    println("Upgrading PhysiCellModelManager.jl from version $(from_version) to $(to_version)...")
    @assert issorted(pcmm_milestones) "Milestone versions must be sorted in ascending order. Got $(pcmm_milestones)."
    next_milestone_inds = findall(x -> from_version < x, pcmm_milestones) #! this could be simplified to take advantage of this list being sorted, but who cares? It's already so fast
    next_milestones = pcmm_milestones[next_milestone_inds]
    success = true
    for next_milestone in next_milestones
        up_fn = get(upgrade_fns, next_milestone, nothing)
        @assert !isnothing(up_fn) "No upgrade function found for version $(next_milestone)."
        success = up_fn(auto_upgrade)
        if !success
            break
        else
            DBInterface.execute(centralDB(), "UPDATE $(pcmmVersionTableName(next_milestone)) SET version='$(next_milestone)';")
        end
    end
    if success && to_version > pcmm_milestones[end]
        println("\t- Upgrading to version $(to_version)...")
        DBInterface.execute(centralDB(), "UPDATE $(pcmmVersionTableName(to_version)) SET version='$(to_version)';")
    end
    return success
end

"""
    populateTableOnFeatureSubset(db::SQLite.DB, source_table::String, target_table::String; column_mapping::Dict{String, String}=Dict{String,String}())

Populate a target table with data from a source table, using a column mapping if provided.
"""
function populateTableOnFeatureSubset(db::SQLite.DB, source_table::String, target_table::String; column_mapping::Dict{String,String}=Dict{String,String}())
    @assert tableExists(source_table; db=db) "Source table $(source_table) does not exist in the database."
    @assert tableExists(target_table; db=db) "Target table $(target_table) does not exist in the database."
    source_columns = tableColumns(source_table; db=db)
    target_columns = [haskey(column_mapping, c) ? column_mapping[c] : c for c in source_columns]
    @assert columnsExist(target_columns, target_table; db=db) "One or more target columns do not exist in the target table."
    insert_into_cols = "(" * join(target_columns, ",") * ")"
    select_cols = join(source_columns, ",")
    query = "INSERT INTO $(target_table) $(insert_into_cols) SELECT $(select_cols) FROM $(source_table);"
    DBInterface.execute(db, query)
end

"""
    pcmmVersionTableName(version::VersionNumber)

Returns the name of the version table based on the given version number.
Before version 0.0.30, the table name is "pcvct_version". Version 0.0.30 and later use "pcmm_version".
"""
pcmmVersionTableName(version::VersionNumber) = version < v"0.0.30" ? "pcvct_version" : "pcmm_version"

"""
    upgradeToX_Y_Z(auto_upgrade::Bool)

Upgrade the database to PhysiCellModelManager.jl version X.Y.Z. Each milestone version has its own upgrade function.
"""
function upgradeToVX_Y_Z end

function continueMilestoneUpgrade(version::VersionNumber, auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version $(version)...

    WARNING: Upgrading to version $(version) will change the database schema.
    See info at https://drbergman-lab.github.io/PhysiCellModelManager.jl/stable/misc/database_upgrades/

    ------IF ANOTHER INSTANCE OF PhysiCellModelManager.jl IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version $(version)? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version $(version) aborted.")
        return false
    end
    println("\t- Upgrading to version $(version)...")
    return true
end

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
            column_names = tableColumns("rulesets_variations"; db=db_rulesets_variations)
            filter!(x -> x != "rulesets_collection_variation_id", column_names)
            path_to_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
            if !isfile(path_to_xml)
                writeXMLRules(path_to_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
            end
            xml_doc = parse_file(path_to_xml)
            for column_name in column_names
                xml_path = columnNameToXMLPath(column_name)
                base_value = getSimpleContent(xml_doc, xml_path)
                stmt = SQLite.Stmt(db_rulesets_variations, "UPDATE rulesets_variations SET '$(column_name)'=(:base_value) WHERE rulesets_collection_variation_id=0;")
                DBInterface.execute(stmt, (base_value,))
            end
            free(xml_doc)
        end
    end
    return true
end

function upgradeToV0_0_3(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.0.3", auto_upgrade)
        return false
    end
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
        createPCMMTable("monads", monadsSchema())
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
        if tableExists("variations"; db=db_config_variations)
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
    if !continueMilestoneUpgrade(v"0.0.10", auto_upgrade)
        return false
    end

    createPCMMTable("physicell_versions", physicellVersionsSchema())
    pcmm_globals.current_physicell_version_id = resolvePhysiCellVersionID()

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
        createPCMMTable("monads", monadsSchema())
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
        if tableExists("rulesets_variations"; db=db_rulesets_collection_variations)
            DBInterface.execute(db_rulesets_collection_variations, "ALTER TABLE rulesets_variations RENAME TO rulesets_collection_variations;")
        end
        if !(DBInterface.execute(db_rulesets_collection_variations, "SELECT 1 FROM pragma_table_info('rulesets_collection_variations') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty)
            DBInterface.execute(db_rulesets_collection_variations, "ALTER TABLE rulesets_collection_variations RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
        end
    end
end

function upgradeToV0_0_15(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.0.15", auto_upgrade)
        return false
    end

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
        createPCMMTable("monads", monadsSchema())
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
        createPCMMTable("monads", monadsSchema())
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end
    return true
end

function upgradeToV0_0_16(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.0.16", auto_upgrade)
        return false
    end

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
        createPCMMTable("monads", monadsSchema())
        populateTableOnFeatureSubset(centralDB(), "monads_temp", "monads")
        DBInterface.execute(centralDB(), "DROP TABLE monads_temp;")
    end
    return true
end

function upgradeToV0_0_25(::Bool)
    println("\t- Upgrading to version 0.0.25...")

    #! v0.0.23 accidentally used the capitalized version of these CSV file names
    monads_folder = joinpath(dataDir(), "outputs", "monads")
    if isdir(monads_folder)
        folders = readdir(monads_folder; sort=false) |> filter(x -> isdir(joinpath(monads_folder, x)))
        for folder in folders
            if isfile(joinpath(monads_folder, folder, "Simulations.csv"))
                temp_dst = joinpath(monads_folder, folder, "__temp_simulations__.csv")
                mv(joinpath(monads_folder, folder, "Simulations.csv"), temp_dst)
                dst = joinpath(monads_folder, folder, "simulations.csv")
                mv(temp_dst, dst)
            end
        end
    end

    samplings_folder = joinpath(dataDir(), "outputs", "samplings")
    if isdir(samplings_folder)
        folders = readdir(samplings_folder; sort=false) |> filter(x -> isdir(joinpath(samplings_folder, x)))
        for folder in folders
            if isfile(joinpath(samplings_folder, folder, "Monads.csv"))
                temp_dst = joinpath(samplings_folder, folder, "__temp_monads__.csv")
                mv(joinpath(samplings_folder, folder, "Monads.csv"), temp_dst)
                dst = joinpath(samplings_folder, folder, "monads.csv")
                mv(temp_dst, dst)
            end
        end
    end

    trials_folder = joinpath(dataDir(), "outputs", "trials")
    if isdir(trials_folder)
        folders = readdir(trials_folder; sort=false) |> filter(x -> isdir(joinpath(trials_folder, x)))
        for folder in folders
            if isfile(joinpath(trials_folder, folder, "Samplings.csv"))
                temp_dst = joinpath(trials_folder, folder, "__temp_samplings__.csv")
                mv(joinpath(trials_folder, folder, "Samplings.csv"), temp_dst)
                dst = joinpath(trials_folder, folder, "samplings.csv")
                mv(temp_dst, dst)
            end
        end
    end
    return true
end

function upgradeToV0_0_29(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.0.29", auto_upgrade)
        return false
    end

    old_file_path = joinpath(dataDir(), "inputs.toml")
    new_file_path = pathToInputsConfig()
    @assert isfile(old_file_path) "The inputs.toml file is missing. Please create it before upgrading to version 0.0.29."
    @assert isdir(joinpath(dataDir(), "inputs")) "The inputs directory is missing. Please create it before upgrading to version 0.0.29."
    if isfile(new_file_path)
        println("The inputs.toml file is already in the inputs directory. No need to move it.")
    else
        mv(old_file_path, new_file_path)
    end
    return true
end

function upgradeToV0_0_30(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.0.30", auto_upgrade)
        return false
    end

    if tableExists("pcvct_version")
        DBInterface.execute(centralDB(), "ALTER TABLE pcvct_version RENAME TO pcmm_version;")
    else
        println("While upgrading to version 0.0.30, the pcvct_version table was not found. This is unexpected.")
        return false
    end
    return true
end

function upgradeToV0_1_3(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.1.3", auto_upgrade)
        return false
    end

    old_path = joinpath(dataDir(), "vct.db")
    new_path = joinpath(dataDir(), "pcmm.db")
    if isfile(old_path)
        close(centralDB())
        mv(old_path, new_path)
        pcmm_globals.db = SQLite.DB(new_path)
    else
        println("While upgrading to version 0.1.3, the vct.db file was not found. This is unexpected.")
        return false
    end
    return true
end

function upgradeToV0_2_0(auto_upgrade::Bool)
    if !continueMilestoneUpgrade(v"0.2.0", auto_upgrade)
        return false
    end

    parseProjectInputsConfigurationFile()
    varied_locations = projectLocations().varied
    for location in projectLocations().varied
        location_folders = queryToDataFrame(constructSelectQuery(locationTableName(location); selection="folder_name")) |> x -> x.folder_name
        location_variation_id_name = locationVariationIDName(location)
        for location_folder in location_folders
            path_to_db = joinpath(locationPath(location, location_folder), locationVariationsDBName(location))
            if !isfile(path_to_db)
                continue
            end
            db = SQLite.DB(path_to_db)
            table_name = locationVariationsTableName(location)
            df = queryToDataFrame(constructSelectQuery(table_name); db=db)
            if "par_key" in names(df)
                continue
            end
            ids = df[!, location_variation_id_name]
            select!(df, Not(location_variation_id_name))
            @assert !(:par_key in names(df)) "Column par_key already found in table $(table_name) in database at $(path_to_db). It seems the upgrade has already been applied."
            par_names = "'" .* names(df) .* "'"
            sqlite_types = sqliteDataType.(eltype.(eachcol(df)))
            col_inserts = par_names .* " " .* sqlite_types

            SQLite.transaction(db)
            try
                DBInterface.execute(db, "ALTER TABLE $(table_name) RENAME TO $(table_name)_old;")
                schema = "$location_variation_id_name INTEGER PRIMARY KEY, par_key BLOB UNIQUE"
                if !isempty(col_inserts)
                    schema *= "," * join(col_inserts, ',')
                end
                createPCMMTable(table_name, schema; db=db)

                stmt_str = "INSERT INTO $(table_name) ($(location_variation_id_name), par_key"
                if !isempty(par_names)
                    stmt_str *= ", $(join(par_names, ','))"
                end
                stmt_str *= ") VALUES ($(join(["?" for _ in 1:(length(par_names)+2)], ",")));"
                stmt = SQLite.Stmt(db, stmt_str)

                for (row_id, row) in zip(ids, eachrow(df))
                    original_vals = [row...]
                    vals = copy(original_vals)
                    vals[vals.=="true"] .= 1.0
                    vals[vals.=="false"] .= 0.0
                    is_string = [v isa String for v in vals]
                    vals[is_string] .= tryparse.(Float64, vals[is_string])
                    @assert all(!isnothing, vals[is_string]) "All parameter values must be parseable as Float64 to create the binary representation. Found non-parseable values: $(original_vals[is_string .& isnothing.(vals)])."
                    @assert all(v -> v ∈ (0.0, 1.0) , vals[is_string]) "All parameter values that were strings must be 'true' or 'false' to create the binary representation. Found: $(original_vals[is_string .& .!([v ∈ (0.0, 1.0) for v in vals])])."
                    original_vals[is_string] .= [v == 0.0 ? "false" : "true" for v in vals[is_string]] #! fix original vals to be the correct strings
                    @assert all(x -> x isa Real, vals) "All parameter values must be Real to create the binary representation. Found: $(typeof.(vals))."
                    par_key = reinterpret(UInt8, Vector{Float64}(vals))
                    params = [row_id, par_key, original_vals...]
                    DBInterface.execute(stmt, params)
                end
                DBInterface.execute(db, "DROP TABLE $(table_name)_old;")
                validateParsBytes(db, table_name)
            catch e
                SQLite.rollback(db)
                @info """
                Error during upgrade of database at $(path_to_db): $(e). Not committing changes to any databases.
                Please report this issue at https://github.com/drbergman-lab/PhysiCellModelManager.jl/issues
                For now, revert back to the previous PCMM version v0.1.7:

                    pkg> rm PhysiCellModelManager
                    pkg> add PhysiCellModelManager@v0.1.7
                """
                return false
            else
                SQLite.commit(db)
                index_name = "$(table_name)_index"
                SQLite.dropindex!(db, index_name; ifexists=true) #! remove previous index
            end
        end
    end
    return true
end

@up_fns