export printSimulationsTable, simulationsTable

################## Database Initialization Functions ##################

"""
    initializeDatabase()

Initialize the central database. If the database does not exist, it will be created.
"""
function initializeDatabase()
    close(centralDB()) #! close the old database connection if it exists
    pcmm_globals.db = SQLite.DB(centralDB().file)
    SQLite.transaction(centralDB(), "EXCLUSIVE")
    try
        createSchema()
    catch e
        SQLite.rollback(centralDB())
        println("Error initializing database: $e")
        return false
    else
        SQLite.commit(centralDB())
        pcmm_globals.initialized = true
        return true
    end
end

"""
    reinitializeDatabase()

Reinitialize the database by searching through the `data/inputs` directory to make sure all are present in the database.
"""
function reinitializeDatabase()
    if !isInitialized()
        println("Database not initialized. Initialize the database first before re-initializing. `initializeModelManager()` will do this.")
        return
    end
    pcmm_globals.initialized = false
    return initializeDatabase()
end

"""
    createSchema()

Create the schema for the database. This includes creating the tables and populating them with data.
"""
function createSchema()
    if !parseProjectInputsConfigurationFile()
        println("Project configuration file parsing failed.")
        return false
    end
    
    #! make sure necessary directories are present
    if !necessaryInputsPresent()
        return false
    end

    #! initialize and populate physicell_versions table
    createPCMMTable("physicell_versions", physicellVersionsSchema())
    pcmm_globals.current_physicell_version_id = resolvePhysiCellVersionID()

    #! initialize tables for all inputs
    for (location, location_dict) in pairs(inputsDict())
        table_name = tableName(location)
        table_schema = """
            $(locationIDName(location)) INTEGER PRIMARY KEY,
            folder_name UNIQUE,
            description TEXT
        """
        createPCMMTable(table_name, table_schema)

        folders = readdir(locationPath(location); sort=false) |> filter(x -> isdir(joinpath(locationPath(location), x)))
        if location_dict["required"] && isempty(folders)
            println("No folders in $(locationPath(location)) found. This is where to put the folders for $(tableName(location)).")
            return false
        end
        for folder in folders
            insertFolder(location, folder)
        end
    end

    simulations_schema = """
        simulation_id INTEGER PRIMARY KEY,
        physicell_version_id INTEGER,
        $(inputIDsSubSchema()),
        $(inputVariationIDsSubSchema()),
        status_code_id INTEGER,
        $(abstractSamplingForeignReferenceSubSchema()),
        FOREIGN KEY (status_code_id)
            REFERENCES status_codes (status_code_id)
    """
    createPCMMTable("simulations", simulations_schema)

    #! initialize monads table
    createPCMMTable("monads", monadsSchema())

    #! initialize samplings table
    createPCMMTable("samplings", samplingsSchema())

    #! initialize trials table
    trials_schema = """
        trial_id INTEGER PRIMARY KEY,
        datetime TEXT,
        description TEXT
    """
    createPCMMTable("trials", trials_schema)

    createDefaultStatusCodesTable()

    return true
end

"""
    necessaryInputsPresent()

Check if all necessary input folders are present in the database.
"""
function necessaryInputsPresent()
    success = true
    for (location, location_dict) in pairs(inputsDict())
        if !location_dict["required"]
            continue
        end

        if !(locationPath(location) |> isdir)
            println("No $(locationPath(location)) found. This is where to put the folders for $(tableName(location)).")
            success = false
        end
    end
    return success
end

"""
    physicellVersionsSchema()

Create the schema for the physicell_versions table. This includes the columns and their types.
"""
function physicellVersionsSchema()
    return """
    physicell_version_id INTEGER PRIMARY KEY,
    repo_owner TEXT,
    tag TEXT,
    commit_hash TEXT UNIQUE,
    date TEXT
    """
end

"""
    monadsSchema()

Create the schema for the monads table. This includes the columns and their types.
"""
function monadsSchema()
    return """
    monad_id INTEGER PRIMARY KEY,
    physicell_version_id INTEGER,
    $(inputIDsSubSchema()),
    $(inputVariationIDsSubSchema()),
    $(abstractSamplingForeignReferenceSubSchema()),
    UNIQUE (physicell_version_id,
            $(join([locationIDName(k) for k in keys(inputsDict())], ",\n")),
            $(join([locationVariationIDName(k) for (k, d) in pairs(inputsDict()) if any(d["varied"])], ",\n"))
            )
   """
end

"""
    inputIDsSubSchema()

Create the part of the schema corresponding to the input IDs.
"""
function inputIDsSubSchema()
    return join(["$(locationIDName(k)) INTEGER" for k in keys(inputsDict())], ",\n")
end

"""
    inputVariationIDsSubSchema()

Create the part of the schema corresponding to the varied inputs and their IDs.
"""
function inputVariationIDsSubSchema()
    return join(["$(locationVariationIDName(k)) INTEGER" for (k, d) in pairs(inputsDict()) if any(d["varied"])], ",\n")
end

"""
    abstractSamplingForeignReferenceSubSchema()

Create the part of the schema containing foreign key references for the simulations, monads, and samplings tables.
"""
function abstractSamplingForeignReferenceSubSchema()
    return """
    FOREIGN KEY (physicell_version_id)
        REFERENCES physicell_versions (physicell_version_id),
    $(join(["""
    FOREIGN KEY ($(locationIDName(k)))
        REFERENCES $(tableName(k)) ($(locationIDName(k)))\
    """ for k in keys(inputsDict())], ",\n"))
    """
end

"""
    samplingsSchema()

Create the schema for the samplings table. This includes the columns and their types.
"""
function samplingsSchema()
    return """
    sampling_id INTEGER PRIMARY KEY,
    physicell_version_id INTEGER,
    $(inputIDsSubSchema()),
    $(abstractSamplingForeignReferenceSubSchema())
    """
end

"""
    metadataDescription(path_to_folder::AbstractString)

Get the description from the metadata.xml file in the given folder using the `description` element as a child element of the root element.
"""
function metadataDescription(path_to_folder::AbstractString)
    path_to_metadata = joinpath(path_to_folder, "metadata.xml")
    description = ""
    if isfile(path_to_metadata)
        xml_doc = parse_file(path_to_metadata)
        metadata = root(xml_doc)
        description_element = find_element(metadata, "description")
        if !isnothing(description_element)
            description = content(find_element(metadata, "description"))
        end
        free(xml_doc)
    end
    return description
end

"""
    createPCMMTable(table_name::String, schema::String; db::SQLite.DB=centralDB())

Create a table in the database with the given name and schema. The table will be created if it does not already exist.

The table name must end in "s" to help normalize the ID names for these entries.
The schema must have a PRIMARY KEY named as the table name without the "s" followed by "_id."
"""
function createPCMMTable(table_name::String, schema::String; db::SQLite.DB=centralDB())
    #! check that table_name ends in "s"
    if last(table_name) != 's'
        s = "Table name must end in 's'."
        s *= "\n\tThis helps to normalize what the id names are for these entries."
        s *= "\n\tYour table $(table_name) does not end in 's'."
        throw(ErrorException(s))
    end
    #! check that schema has PRIMARY KEY named as table_name without the s followed by _id
    id_name = locationIDName(Symbol(table_name[1:end-1]))
    if !occursin("$(id_name) INTEGER PRIMARY KEY", schema)
        s = "Schema must have PRIMARY KEY named as $(id_name)."
        s *= "\n\tThis helps to normalize what the id names are for these entries."
        s *= "\n\tYour schema $(schema) does not have \"$(id_name) INTEGER PRIMARY KEY\"."
        throw(ErrorException(s))
    end
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS $(table_name) (
        $(schema)
        )
    ")
    return
end

"""
    insertFolder(location::Symbol, folder::String, description::String="")

Insert a folder into the database. If the folder already exists, it will be ignored.

If the folder already has a description from the metadata.xml file, that description will be used instead of the one provided.
"""
function insertFolder(location::Symbol, folder::String, description::String="")
    path_to_folder = locationPath(location, folder)
    old_description = metadataDescription(path_to_folder)
    description = isempty(old_description) ? description : old_description
    query = "INSERT OR IGNORE INTO $(tableName(location)) (folder_name, description) VALUES ('$folder', '$description') RETURNING $(locationIDName(location));"
    df = queryToDataFrame(query)
    if !folderIsVaried(location, folder)
        return
    end
    db_variations = joinpath(locationPath(location, folder), "$(location)_variations.db") |> SQLite.DB
    createPCMMTable(variationsTableName(location), "$(locationVariationIDName(location)) INTEGER PRIMARY KEY"; db=db_variations)
    DBInterface.execute(db_variations, "INSERT OR IGNORE INTO $(location)_variations ($(locationVariationIDName(location))) VALUES(0);")
    input_folder = InputFolder(location, folder)
    prepareBaseFile(input_folder)
end

"""
    recognizedStatusCodes()

Return the recognized status codes for simulations.
"""
recognizedStatusCodes() = ["Not Started", "Queued", "Running", "Completed", "Failed"]

"""
    createDefaultStatusCodesTable()

Create the default status codes table in the database.
"""
function createDefaultStatusCodesTable()
    status_codes_schema = """
        status_code_id INTEGER PRIMARY KEY,
        status_code TEXT UNIQUE
    """
    createPCMMTable("status_codes", status_codes_schema)
    status_codes = recognizedStatusCodes()
    for status_code in status_codes
        DBInterface.execute(centralDB(), "INSERT OR IGNORE INTO status_codes (status_code) VALUES ('$status_code');")
    end
end

"""
    statusCodeID(status_code::String)

Get the ID of a status code from the database.
"""
function statusCodeID(status_code::String)
    @assert status_code in recognizedStatusCodes() "Status code $(status_code) is not recognized. Must be one of $(recognizedStatusCodes())."
    query = constructSelectQuery("status_codes", "WHERE status_code='$status_code';"; selection="status_code_id")
    return queryToDataFrame(query; is_row=true) |> x -> x[1,:status_code_id]
end

"""
    isStarted(simulation_id::Int[; new_status_code::Union{Missing,String}=missing])

Check if a simulation has been started. Can also pass in a `Simulation` object in place of the simulation ID.

If `new_status_code` is provided, update the status of the simulation to this value.
The check and status update are done in a transaction to ensure that the status is not changed by another process.
"""
function isStarted(simulation_id::Int; new_status_code::Union{Missing,String}=missing)
    query = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id)"; selection="status_code_id")
    mode = ismissing(new_status_code) ? "DEFERRED" : "EXCLUSIVE" #! if we are possibly going to update, then set to exclusive mode
    SQLite.transaction(centralDB(), mode)
    status_code = queryToDataFrame(query; is_row=true) |> x -> x[1,:status_code_id]
    is_started = status_code != statusCodeID("Not Started")
    if !ismissing(new_status_code) && !is_started
        query = "UPDATE simulations SET status_code_id=$(statusCodeID(new_status_code)) WHERE simulation_id=$(simulation_id);"
        DBInterface.execute(centralDB(), query)
    end
    SQLite.commit(centralDB())

    return is_started
end

isStarted(simulation::Simulation; new_status_code::Union{Missing,String}=missing) = isStarted(simulation.id; new_status_code=new_status_code)

################## DB Interface Functions ##################

"""
    variationsDatabase(location::Symbol, folder::String)

Return the database for the location and folder.

The second argument can alternatively be the ID of the folder or an AbstractSampling object (simulation, monad, or sampling) using that folder.
"""
function variationsDatabase(location::Symbol, folder::String)
    if folder == ""
        return nothing
    end
    path_to_db = joinpath(locationPath(location, folder), "$(location)_variations.db")
    if !isfile(path_to_db)
        return missing
    end
    return path_to_db |> SQLite.DB
end

function variationsDatabase(location::Symbol, id::Int)
    folder = inputFolderName(location, id)
    return variationsDatabase(location, folder)
end

function variationsDatabase(location::Symbol, S::AbstractSampling)
    folder = S.inputs[location].folder
    return variationsDatabase(location, folder)
end

########### Retrieving Database Information Functions ###########

"""
    vctDBQuery(query::String; db::SQLite.DB=centralDB())
    
Execute a query against the database and return the result.
"""
vctDBQuery(query::String; db::SQLite.DB=centralDB()) = DBInterface.execute(db, query)

"""
    queryToDataFrame(query::String; db::SQLite.DB=centralDB(), is_row::Bool=false)

Execute a query against the database and return the result as a DataFrame.

If `is_row` is true, the function will assert that the result has exactly one row, i.e., a unique result.
"""
function queryToDataFrame(query::String; db::SQLite.DB=centralDB(), is_row::Bool=false)
    df = vctDBQuery(query; db=db) |> DataFrame
    if is_row
        @assert size(df,1)==1 "Did not find exactly one row matching the query:\n\tDatabase file: $(db)\n\tQuery: $(query)\nResult: $(df)"
    end
    return df
end

"""
    constructSelectQuery(table_name::String, condition_stmt::String=""; selection::String="*")

Construct a SELECT query for the given table name, condition statement, and selection.
"""
constructSelectQuery(table_name::String, condition_stmt::String=""; selection::String="*") = "SELECT $(selection) FROM $(table_name) $(condition_stmt);"

"""
    inputFolderName(location::Symbol, id::Int)
    
Retrieve the folder name associated with the given location and ID.
"""
function inputFolderName(location::Symbol, id::Int)
    if id == -1
        return ""
    end

    query = constructSelectQuery(tableName(location), "WHERE $(locationIDName(location))=$(id)"; selection="folder_name")
    return queryToDataFrame(query; is_row=true) |> x -> x.folder_name[1]
end

"""
    inputFolderID(location::Symbol, folder_name::String; db::SQLite.DB=centralDB())

Retrieve the ID of the folder associated with the given location and folder name.
"""
function inputFolderID(location::Symbol, folder_name::String; db::SQLite.DB=centralDB())
    if folder_name == ""
        return -1
    end
    primary_key_string = locationIDName(location)
    query = constructSelectQuery(tableName(location), "WHERE folder_name='$(folder_name)'"; selection=primary_key_string)
    df = queryToDataFrame(query; is_row=true)
    return df[1, primary_key_string]
end

########### Summarizing Database Functions ###########

"""
    variationIDs(location::Symbol, S::AbstractSampling)

Return a vector of the variation IDs for the given location associated with `S`.
"""
variationIDs(location::Symbol, M::AbstractMonad) = [M.variation_id[location]]
variationIDs(location::Symbol, sampling::Sampling) = [monad.variation_id[location] for monad in sampling.monads]

"""
    variationsTable(query::String, db::SQLite.DB; remove_constants::Bool=false)

Return a DataFrame containing the variations table for the given query and database.

Remove constant columns if `remove_constants` is true and the DataFrame has more than one row.
"""
function variationsTable(query::String, db::SQLite.DB; remove_constants::Bool=false)
    df = queryToDataFrame(query, db=db)
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!,n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

"""
    variationsTableName(location::Symbol, variations_database::SQLite.DB, variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)

Return a DataFrame containing the variations table for the given location, variations database, and variation IDs.
"""
function variationsTable(location::Symbol, variations_database::SQLite.DB, variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    used_variation_ids = filter(x -> x != -1, variation_ids) #! variation_id = -1 means this input is not even being used
    query = constructSelectQuery(variationsTableName(location), "WHERE $(locationVariationIDName(location)) IN ($(join(used_variation_ids,",")))")
    df = variationsTable(query, variations_database; remove_constants=remove_constants)
    rename!(name -> shortVariationName(location, name), df)
    return df
end

"""
    variationsTable(location::Symbol, S::AbstractSampling; remove_constants::Bool=false)

Return a DataFrame containing the variations table for the given location and sampling.
"""
function variationsTable(location::Symbol, S::AbstractSampling; remove_constants::Bool=false)
    return variationsTable(location, variationsDatabase(location, S), variationIDs(location, S); remove_constants=remove_constants)
end

"""
    variationsTable(location::Symbol, ::Nothing, variation_ids::AbstractVector{<:Integer}; kwargs...)

If the location is not being used, return a DataFrame with all variation IDs set to -1.
"""
function variationsTable(location::Symbol, ::Nothing, variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == -1, variation_ids) "If the $(location) is not being used, then all $(locationVariationIDName(location))s must be -1."
    return DataFrame(shortLocationVariationID(location)=>variation_ids)
end

"""
    variationsTable(location::Symbol, ::Missing, variation_ids::AbstractVector{<:Integer}; kwargs...)

If the location folder does not contain a variations database, return a DataFrame with all variation IDs set to 0.
"""
function variationsTable(location::Symbol, ::Missing, variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == 0, variation_ids) "If the $(location)_folder does not contain a $(location)_variations.db, then all $(locationVariationIDName(location))s must be 0."
    return DataFrame(shortLocationVariationID(location)=>variation_ids)
end

"""
    addFolderNameColumns!(df::DataFrame)

Add the folder names to the DataFrame for each location in the DataFrame.
"""
function addFolderNameColumns!(df::DataFrame)
    for (location, location_dict) in pairs(inputsDict())
        if !(locationIDName(location) in names(df))
            continue
        end
        unique_ids = unique(df[!, locationIDName(location)])
        folder_names_dict = [id => inputFolderName(location, id) for id in unique_ids] |> Dict{Int,String}
        if location_dict["required"]
            @assert !any(folder_names_dict |> values .|> isempty) "Some $(location) folders are empty/missing, but they are required."
        end
        df[!, "$(location)_folder"] .= [folder_names_dict[id] for id in df[!, locationIDName(location)]]
    end
    return df
end

"""
    simulationsTableFromQuery(query::String; remove_constants::Bool=true, sort_by=String[], sort_ignore=[:SimID; shortLocationVariationID.(projectLocations().varied)])

Return a DataFrame containing the simulations table for the given query.

By default, will ignore the simulation ID and the variation IDs for the varied locations when sorting.
The sort order can be controlled by the `sort_by` and `sort_ignore` keyword arguments.

By default, constant columns (columns with the same value for all simulations) will be removed (unless there is only one simulation).
Set `remove_constants` to false to keep these columns.

# Arguments
- `query::String`: The SQL query to execute.

# Keyword Arguments
- `remove_constants::Bool`: If true, removes columns that have the same value for all simulations. Defaults to true.
- `sort_by::Vector{String}`: A vector of column names to sort the table by. Defaults to all columns. To populate this argument, it is recommended to first print the table to see the column names.
- `sort_ignore::Vector{String}`: A vector of column names to ignore when sorting. Defaults to the simulation ID and the variation IDs associated with the simulations.
"""
function simulationsTableFromQuery(query::String;
                                   remove_constants::Bool=true,
                                   sort_by=String[],
                                   sort_ignore=[:SimID; shortLocationVariationID.(projectLocations().varied)])
    #! preprocess sort kwargs
    sort_by = (sort_by isa Vector ? sort_by : [sort_by]) .|> Symbol
    sort_ignore = (sort_ignore isa Vector ? sort_ignore : [sort_ignore]) .|> Symbol

    df = queryToDataFrame(query)
    id_col_names_to_remove = names(df) #! a bunch of ids that we don't want to show

    filter!(n -> n != "simulation_id", id_col_names_to_remove) #! we will remove all the IDs other than the simulation ID
    addFolderNameColumns!(df) #! add the folder columns

    #! handle each of the varying inputs
    for loc in projectLocations().varied
        df = appendVariations(loc, df)
    end

    select!(df, Not(id_col_names_to_remove)) #! now remove the variation ID columns
    rename!(df, :simulation_id => :SimID)
    col_names = names(df)
    if remove_constants && size(df, 1) > 1
        filter!(n -> length(unique(df[!, n])) > 1, col_names)
        select!(df, col_names)
    end
    if isempty(sort_by)
        sort_by = deepcopy(col_names)
    end
    setdiff!(sort_by, sort_ignore) #! remove the columns we don't want to sort by
    filter!(n -> n in col_names, sort_by) #! remove any columns that are not in the DataFrame
    sort!(df, sort_by)
    return df
end

"""
    appendVariations(location::Symbol, df::DataFrame)

Add the varied parameters associated with the `location` to  `df`.
"""
function appendVariations(location::Symbol, df::DataFrame)
    short_var_name = shortLocationVariationID(location)
    var_df = DataFrame(short_var_name => Int[], :folder_name => String[])
    unique_tuples = [(row["$(location)_folder"], row[locationVariationIDName(location)]) for row in eachrow(df)] |> unique
    for unique_tuple in unique_tuples
        temp_df = variationsTable(location, variationsDatabase(location, unique_tuple[1]), [unique_tuple[2]]; remove_constants=false)
        temp_df[!,:folder_name] .= unique_tuple[1]
        append!(var_df, temp_df, cols=:union)
    end
    folder_pair = ("$(location)_folder" |> Symbol) => :folder_name
    id_pair = (locationVariationIDName(location) |> Symbol) => short_var_name
    return outerjoin(df, var_df, on = [folder_pair, id_pair])
end

"""
    simulationsTable(T; kwargs...)

Return a DataFrame with the simulation data calling [`simulationsTableFromQuery`](@ref) with those keyword arguments.

There are three options for `T`:
- `T` can be any `Simulation`, `Monad`, `Sampling`, `Trial`, or any array (or vector) of such.
- `T` can also be a vector of simulation IDs.
- If omitted, creates a DataFrame for all the simulations.
"""
function simulationsTable(T::Union{AbstractTrial,AbstractArray{<:AbstractTrial}}; kwargs...)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulationIDs(T),",")));")
    return simulationsTableFromQuery(query; kwargs...)
end

function simulationsTable(simulation_ids::AbstractVector{<:Integer}; kwargs...)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));")
    return simulationsTableFromQuery(query; kwargs...)
end

function simulationsTable(; kwargs...)
    query = constructSelectQuery("simulations")
    return simulationsTableFromQuery(query; kwargs...)
end

########### Printing Database Functions ###########

"""
    printSimulationsTable()

Print a table of simulations and their varied values. See keyword arguments below for more control of the output.

There are many methods for this function. The simplest is `printSimulationsTable()`, which prints all simulations in the database.
You can also pass in any number of simulations, monads, samplings, and trials to print a table of those simulations:
```
printSimulationsTable([simulation_1, monad_3, sampling_2, trial_1])
```
Finally, a vector of simulation IDs can be passed in:
```
printSimulationsTable([1, 2, 3])
```
Keyword arguments can be used with any of these methods to control the output:
# Keyword Arguments
- `sink`: A function to print the table. Defaults to `println`. Note, the table is a DataFrame, so you can also use `CSV.write` to write the table to a CSV file.
- `remove_constants::Bool`: If true, removes columns that have the same value for all simulations. Defaults to true.
- `sort_by::Vector{String}`: A vector of column names to sort the table by. Defaults to all columns. To populate this argument, first print the table to see the column names.
- `sort_ignore::Vector{String}`: A vector of column names to ignore when sorting. Defaults to the database IDs associated with the simulations.
"""
printSimulationsTable(args...; sink=println, kwargs...) = simulationsTable(args...; kwargs...) |> sink
