#! PhysiCell-specific database logic.

#! All generic database infrastructure (initializeDatabase,
#! tableIDName, insertFolder, queryToDataFrame,
#! stmtToDataFrame, inputFolderName, inputFolderID, tableExists, columnsExist,
#! tableColumns, buildWhereClause, databaseDiagnostics, etc.) is now defined in
#! ModelManager/src/database.jl.  This file provides only what is PhysiCell-specific.

import ModelManager: getParameterValue

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

################## PhysiCell-specific: getParameterValue ##################

"""
    getParameterValue(M::AbstractMonad, xp::XMLPath)
    getParameterValue(M::AbstractMonad, xml_path::AbstractVector{<:AbstractString})
    getParameterValue(simulation_id::Int, xp)

Get the parameter value for the given XML path from the monad's variations database if
the column exists, otherwise fall back to the base XML file.

The location is inferred from the XMLPath via [`inferVariationLocation`](@ref).
For the generic 3-argument form (explicit location), see `ModelManager.getParameterValue`.

- Boolean strings (`"true"` / `"false"`) are returned as `Bool`.
- Numeric strings are returned as `Float64`.
- Everything else is returned as-is.
"""
function getParameterValue(M::AbstractMonad, xp::XMLPath)
    location = inferVariationLocation(xp)
    return getParameterValue(M, location, xp)
end

function getParameterValue(M::AbstractMonad, xml_path::AbstractVector{<:AbstractString})
    return getParameterValue(M, XMLPath(xml_path))
end

function getParameterValue(simulation_id::Int, xp)
    return getParameterValue(Simulation(simulation_id), xp)
end
