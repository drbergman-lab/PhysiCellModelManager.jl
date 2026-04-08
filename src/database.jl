#! PhysiCell-specific database logic.

# Import non-exported ModelManager stubs so these methods extend them.
import ModelManager: getInputFolderDescription, initializeInputFolder

#!
#! All generic database infrastructure (initializeDatabase, createSchema,
#! createMMTable / createPCMMTable, tableIDName, insertFolder, queryToDataFrame,
#! stmtToDataFrame, inputFolderName, inputFolderID, tableExists, columnsExist,
#! tableColumns, buildWhereClause, databaseDiagnostics, etc.) is now defined in
#! ModelManager/src/database.jl.  This file provides only what is PhysiCell-specific.

export getAllParameterValues, getParameterValue

################## PhysiCell version schema (dispatcher target) ##################

"""
    physicellVersionsSchema()

Return the SQL schema fragment for the `physicell_versions` table.
This is the value returned by `simulatorVersionSchema(::PhysiCellSimulator)`.
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

################## PhysiCell metadata helper ##################

"""
    metadataDescription(path_to_folder::AbstractString)

Get the description from `metadata.xml` inside `path_to_folder`, using the `description`
child of the root element.  Returns `""` if the file is absent or has no such element.
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

################## ModelManager interface hooks ##################

"""
    getInputFolderDescription(::PhysiCellSimulator, path::AbstractString)

Return the description from `metadata.xml` inside `path`.
Called by `insertFolder` in ModelManager when registering a new input folder.
"""
getInputFolderDescription(::PhysiCellSimulator, path::String) = metadataDescription(path)

"""
    initializeInputFolder(::PhysiCellSimulator, input_folder::InputFolder)

Call `prepareBaseFile` for `input_folder` when it is first registered in the database.
"""
function initializeInputFolder(::PhysiCellSimulator, input_folder::InputFolder)
    prepareBaseFile(input_folder)
end

################## PhysiCell-specific: getParameterValue ##################

"""
    getParameterValue(M::AbstractMonad, xp::XMLPath)
    getParameterValue(M::AbstractMonad, xml_path::AbstractVector{<:AbstractString})
    getParameterValue(simulation_id::Int, xp)

Get the parameter value for the given XML path from the monad's variations database if
the column exists, otherwise fall back to the base XML file.

- Boolean strings (`"true"` / `"false"`) are returned as `Bool`.
- Numeric strings are returned as `Float64`.
- Everything else is returned as-is.
"""
function getParameterValue(M::AbstractMonad, xp::XMLPath)
    location = variationLocation(xp)
    db = locationVariationsDatabase(location, M)
    @assert !isnothing(db) "XMLPath $(xp.xml_path) corresponds to location $(location), but that location is not being varied in this $(nameof(typeof(M)))."
    @assert !ismissing(db) "Variations database for location $(location) not found in folder $(M.inputs[location].folder)."
    if columnsExist([columnName(xp)], locationVariationsTableName(location); db=db)
        query = constructSelectQuery(locationVariationsTableName(location), "WHERE $(locationVariationIDName(location))=$(M.variation_id[location])"; selection="\"" * columnName(xp) * "\"")
        df = queryToDataFrame(query; db=db, is_row=true)
        v = df[1, columnName(xp)]
        if v ∈ ("true", "false")
            return v == "true"
        end
        return v
    else
        path_to_xml = prepareBaseFile(M.inputs[location])
        xml_doc = parse_file(path_to_xml)
        v = getSimpleContent(xml_doc, xp.xml_path)
        free(xml_doc)
        return parseValueFromString(v)
    end
end

function getParameterValue(M::AbstractMonad, xml_path::AbstractVector{<:AbstractString})
    xp = XMLPath(xml_path)
    return getParameterValue(M, xp)
end

function getParameterValue(simulation_id::Int, xp)
    simulation = Simulation(simulation_id)
    return getParameterValue(simulation, xp)
end

################## PhysiCell-specific: getAllParameterValues ##################

"""
    getAllParameterValues(simulation_id::Int)
    getAllParameterValues(S::AbstractSampling)

Get all parameter values for the given simulation, monad, or sampling as a DataFrame.
Simulation ID can also be passed directly as an integer.

# Identifying attributes
If sibling elements have identical tags, attributes are programmatically searched to find one that can be used to identify them.
Priority is given to "name", "ID", and "id" attributes.
If sibling elements cannot be uniquely identified by an attribute, artificial IDs will be added to the XML paths to ensure uniqueness for the column names.
These will show up as `<tag>:temp_id:<index>` in the column names.
Search for them with `contains(col_name, ":temp_id:")`.
Note: these are not added to the XML files themselves.
Users must manually insert such artificial IDs into their XML files to use PCMM to vary those parameters.

# Converting column names into XML paths
To convert the column names in the returned DataFrame back into XML paths, split the column names by '/':

```julia
df = getAllParameterValues(simulation_id)
col1 = names(df)[1]
xml_path = split(col1, '/')
```

Alternatively, the internal [`columnNameToXMLPath`](@ref) function can be used.

```julia
xml_path = PhysiCellModelManager.columnNameToXMLPath(col1)
```

Conversion back can be done either with `join` or the `columnName` function:

```julia
xml_path = ["overall", "max_time"]
col_name = join(xml_path, '/')
# or
col_name = PhysiCellModelManager.columnName(xml_path)
```
"""
function getAllParameterValues(S::Sampling)
    monad_ids = monadIDs(S)
    dfs = [getAllParameterValues(Monad(monad_id)) for monad_id in monad_ids]
    df = vcat(dfs...)
    df.monad_id = monad_ids
    return df
end

function getAllParameterValues(M::AbstractMonad)
    D = Dict{String,Any}()
    for (loc, input_folder) in pairs(M.inputs.input_folders)
        if !input_folder.varied
            continue # only get values for varied inputs
        end

        if isempty(input_folder.folder)
            continue # skip missing inputs
        end

        path_to_xml = createXMLFile(loc, M)
        xml_doc = parse_file(path_to_xml)
        xml_root = root(xml_doc)
        current_path = String[]

        recurseToGetParameterValues!(D, current_path, xml_root)
        free(xml_doc)
    end
    return DataFrame(D)
end

function getAllParameterValues(simulation_id::Int)
    simulation = Simulation(simulation_id)
    return getAllParameterValues(simulation)
end

"""
    recurseToGetParameterValues!(D::Dict{String,Any}, current_path::Vector{String}, element::XMLElement)

Recursively traverse the XML element tree to extract parameter values into `D`.
Used by [`getAllParameterValues`](@ref).
"""
function recurseToGetParameterValues!(D::Dict{String,Any}, current_path::Vector{String}, element::XMLElement)
    if elementIsTerminal(element)
        v = content(element)
        key = columnName(XMLPath(current_path))
        D[key] = parseValueFromString(v)
        return
    end
    child_tags = [name(c) for c in child_elements(element)]
    priority_attributes = ("name", "ID", "id")
    for tag in unique(child_tags)
        these_children = [c for c in child_elements(element) if name(c) == tag]
        common_attributes = intersect([collect(attributes_dict(c) |> keys) for c in these_children]...)
        if length(these_children) == 1
            priority_attribute_found = false
            for attr in priority_attributes
                if attr in common_attributes
                    priority_attribute_found = true
                    recurseToGetParameterValues!(D, [current_path; "$tag:$attr:$(attribute(these_children[1], attr))"], these_children[1])
                    break
                end
            end
            if !priority_attribute_found
                recurseToGetParameterValues!(D, [current_path; tag], these_children[1])
            end
            continue
        end
        unique_attribute = nothing
        for attr in priority_attributes
            if !(attr in common_attributes)
                continue
            end
            attr_values = [attribute(c, attr) for c in these_children]
            if length(unique(attr_values)) == length(these_children)
                unique_attribute = attr
                break
            end
        end
        if isnothing(unique_attribute)
            for attr in common_attributes
                attr_values = [attribute(c, attr) for c in these_children]
                if length(unique(attr_values)) == length(these_children)
                    unique_attribute = attr
                    break
                end
            end
        end
        if isnothing(unique_attribute)
            @warn "Could not find unique attribute to distinguish between multiple children with tag $(tag) under path $(columnName(current_path)). Adding artificial IDs to make unique keys."
            for (i, c) in enumerate(these_children)
                recurseToGetParameterValues!(D, [current_path; "$tag:temp_id:$i"], c)
            end
        else
            for c in these_children
                recurseToGetParameterValues!(D, [current_path; "$tag:$unique_attribute:$(attribute(c, unique_attribute))"], c)
            end
        end
    end
end

"""
    parseValueFromString(v::String)

Parse a string value: return `Bool` for `"true"`/`"false"`, `Float64` if numeric, or the
original string otherwise.
"""
function parseValueFromString(v::String)
    if v ∈ ("true", "false")
        return v == "true"
    elseif tryparse(Float64, v) |> !isnothing
        return parse(Float64, v)
    end
    return v
end

########### Database Validation Functions ###########

"""
    validateParsBytes(db::SQLite.DB, table_name::String)

Assert that the `par_key` blob in every row of `table_name` matches the float64
reinterpretation of the other columns.
"""
function validateParsBytes(db::SQLite.DB, table_name::String)
    df = queryToDataFrame("SELECT * FROM $table_name;", db=db)
    @assert names(df)[1] == tableIDName(table_name) "$(table_name) does not have the primary key as the first column."
    @assert names(df)[2] == "par_key" "$(table_name) does not have par_key as the second column."
    for row in eachrow(df)
        par_key = row[:par_key]
        vals = [row[3:end]...]
        vals[vals .== "true"] .= 1.0
        vals[vals .== "false"] .= 0.0
        expected_par_key = reinterpret(UInt8, Vector{Float64}(vals))
        @assert par_key == expected_par_key """
        par_key does not match the expected values for $(table_name) ID $(row[1]).
        Expected: $(expected_par_key)
        Found: $(par_key)
        """
    end
end
