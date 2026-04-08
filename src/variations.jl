#! PhysiCell-specific variation infrastructure.

# Extend the addVariationRows stub from ModelManager.
import ModelManager: addVariationRows, variationLocation, DiscreteVariation, DistributedVariation,
                     UniformDistributedVariation, NormalDistributedVariation,
                     ElementaryVariation, LatentVariation

#!
#! Generic types (XMLPath, DiscreteVariation, DistributedVariation, CoVariation,
#! LatentVariation, ParsedVariations, AddVariationMethod subtypes, addVariations, etc.)
#! are now defined in ModelManager.  This file provides:
#!   • variationLocation(xp::XMLPath) — PhysiCell-specific location inference
#!   • Backward-compat constructors (no location arg) for all variation types
#!   • addVariationRows(::PhysiCellSimulator, ...) + its helpers
#!   • Deprecated PhysiCell-specific dimension helpers

export addDomainVariationDimension!, addCustomDataVariationDimension!, addAttackRateVariationDimension!

################## PhysiCell-specific: variationLocation(::XMLPath) ##################

"""
    variationLocation(xp::XMLPath)

Infer the PhysiCell input-folder location symbol for `xp` based on the first path element.

Returns one of `:rulesets_collection`, `:intracellular`, `:ic_cell`, `:ic_ecm`, or `:config`.

This is a PhysiCell-specific function.  The generic ModelManager infrastructure does NOT
call `variationLocation`; callers are responsible for supplying the location explicitly.
"""
function variationLocation(xp::XMLPath)
    if startswith(xp.xml_path[1], "behavior_ruleset:name:")
        return :rulesets_collection
    elseif xp.xml_path[1] == "intracellulars"
        return :intracellular
    elseif startswith(xp.xml_path[1], "cell_patches:name:")
        return :ic_cell
    elseif startswith(xp.xml_path[1], "layer:ID:")
        return :ic_ecm
    else
        return :config
    end
end

################## Backward-compat convenience constructors ##################
#
# These let PCMM callers omit the `location` argument — location is inferred
# from the XMLPath.  The explicit-location constructors are defined in ModelManager.

function DiscreteVariation(target::XMLPath, values::Vector{T}) where T
    return DiscreteVariation(variationLocation(target), target, values)
end
DiscreteVariation(target::XMLPath, value::T) where T = DiscreteVariation(target, Vector{T}([value]))
DiscreteVariation(target::Vector{<:AbstractString}, values) = DiscreteVariation(XMLPath(target), values)

function DistributedVariation(target::XMLPath, distribution::Distribution; flip::Bool=false)
    return DistributedVariation(variationLocation(target), target, distribution; flip=flip)
end
DistributedVariation(target::Vector{<:AbstractString}, dist::Distribution; flip::Bool=false) =
    DistributedVariation(XMLPath(target), dist; flip=flip)

function ElementaryVariation(target::Vector{<:AbstractString}, v; kwargs...)
    if v isa Distribution{Univariate}
        return DistributedVariation(target, v; kwargs...)
    else
        return DiscreteVariation(target, v; kwargs...)
    end
end

function UniformDistributedVariation(xml_path::Vector{<:AbstractString}, lb::T, ub::T; flip::Bool=false) where {T<:Real}
    return DistributedVariation(xml_path, Uniform(lb, ub); flip=flip)
end

function NormalDistributedVariation(xml_path::Vector{<:AbstractString}, mu::T, sigma::T; lb::Real=-Inf, ub::Real=Inf, flip::Bool=false) where {T<:Real}
    return DistributedVariation(xml_path, truncated(Normal(mu, sigma), lb, ub); flip=flip)
end

function LatentVariation(latent_parameters::Vector{T}, targets::AbstractVector{XMLPath}, maps::Vector{<:Function}, lp_names::AbstractVector{<:AbstractString}=ModelManager.defaultLatentParameterNames(latent_parameters, targets)) where T<:Union{Vector{<:Real},<:Distribution}
    locations = variationLocation.(targets)
    return LatentVariation(latent_parameters, targets, maps, lp_names, locations)
end
function LatentVariation(latent_parameters::Vector{T}, targets::AbstractVector{<:AbstractVector{<:AbstractString}}, maps::Vector{<:Function}, lp_names::AbstractVector{<:AbstractString}=String[]) where T<:Union{Vector{<:Real},<:Distribution}
    targets_xp = XMLPath.(targets)
    lp_names = isempty(lp_names) ? ModelManager.defaultLatentParameterNames(latent_parameters, targets_xp) : lp_names
    return LatentVariation(latent_parameters, targets_xp, maps, lp_names)
end

################## Variation Dimension Functions (deprecated) ##################

"""
    addDomainVariationDimension!(evs::Vector{<:ElementaryVariation}, domain::NamedTuple)

Deprecated function that pushes variations onto `evs` for each domain boundary named in `domain`.

The names in `domain` can be flexibly named as long as they contain either `min` or `max` and one of `x`, `y`, or `z` (other than the the `x` in `max`).
It is not required to include all three dimensions and their boundaries.
The values for each boundary can be a single value or a vector of values.

Instead of using this function, use `configPath("x_min")`, `configPath("x_max")`, etc. to create the XML paths and then use `DiscreteVariation` to create the variations.
Use a [`CoVariation`](@ref) if you want to vary any of these together.

# Examples:
```
evs = ElementaryVariation[]
addDomainVariationDimension!(evs, (x_min=-78, xmax=78, min_y=-30, maxy=[30, 60], z_max=10))
```
"""
function addDomainVariationDimension!(evs::Vector{<:ElementaryVariation}, domain::NamedTuple)
    Base.depwarn("`addDomainVariationDimension!` is deprecated. Use `configPath(\"x_min\")` etc. to create the XML paths and then use `DiscreteVariation` to create the variations.", :addDomainVariationDimension!, force=true)
    dim_chars = ["z", "y", "x"] #! put x at the end to avoid prematurely matching with "max"
    for (tag, value) in pairs(domain)
        tag = String(tag)
        if contains(tag, "min")
            remaining_characters = replace(tag, "min" => "")
            dim_side = "min"
        elseif contains(tag, "max")
            remaining_characters = replace(tag, "max" => "")
            dim_side = "max"
        else
            msg = """
            Invalid tag for a domain dimension: $(tag)
            It must contain either 'min' or 'max'
            """
            throw(ArgumentError(msg))
        end
        ind = findfirst(contains.(remaining_characters, dim_chars))
        @assert !isnothing(ind) "Invalid domain dimension: $(tag)"
        dim_char = dim_chars[ind]
        tag = "$(dim_char)_$(dim_side)"
        xml_path = ["domain", tag]
        push!(evs, DiscreteVariation(xml_path, value)) #! do this to make sure that singletons and vectors are converted to vectors
    end
end

"""
    addAttackRateVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, target_name::String, values::Vector{T} where T)

Deprecated function that pushes a variation onto `evs` for the attack rate of a cell type against a target cell type.

Instead of using this function, use `configPath(<attacker_cell_type>, "attack", <target_cell_type>)` to create the XML path and then use `DiscreteVariation` to create the variation.

# Examples:
```
addAttackRateVariationDimension!(evs, "immune", "cancer", [0.1, 0.2, 0.3])
```
"""
function addAttackRateVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, target_name::String, values::Vector{T} where T)
    Base.depwarn("`addAttackRateVariationDimension!` is deprecated. Use `configPath(<attacker_cell_type>, \"attack\", <target_cell_type>)` to create the XML path and then use `DiscreteVariation` to create the variation.", :addAttackRateVariationDimension!, force=true)
    xml_path = attackRatePath(cell_definition, target_name)
    push!(evs, DiscreteVariation(xml_path, values))
end

"""
    addCustomDataVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, field_name::String, values::Vector{T} where T)

Deprecated function that pushes a variation onto `evs` for a custom data field of a cell type.

Instead of using this function, use `configPath(<cell_definition>, "custom", <tag>)` to create the XML path and then use `DiscreteVariation` to create the variation.

# Examples:
```
addCustomDataVariationDimension!(evs, "immune", "perforin", [0.1, 0.2, 0.3])
```
"""
function addCustomDataVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, field_name::String, values::Vector{T} where T)
    Base.depwarn("`addCustomDataVariationDimension!` is deprecated. Use `configPath(<cell_definition>, \"custom\", <tag>)` to create the XML path and then use `DiscreteVariation` to create the variation.", :addCustomDataVariationDimension!, force=true)
    xml_path = customDataPath(cell_definition, field_name)
    push!(evs, DiscreteVariation(xml_path, values))
end

################## Simulator dispatch: addVariationRows ##################

"""
    addVariationRows(::PhysiCellSimulator, inputs::InputFolders, reference_variation_id::VariationID, loc_dicts::Dict)

Add new rows to the per-location variation databases and return the resulting variation IDs.

`loc_dicts` maps each varied location symbol to a 3-tuple
`(values_matrix, types, targets)` where `values_matrix` is a `#targets × #samples`
numeric matrix.
"""
function addVariationRows(::PhysiCellSimulator, inputs::InputFolders, reference_variation_id::VariationID, loc_dicts::Dict)
    location_variation_ids = Dict{Symbol, Vector{Int}}()
    for (loc, (loc_vals, loc_types, loc_targets)) in pairs(loc_dicts)
        column_setup = setUpColumns(loc, inputs[loc].id, loc_types, loc_targets, reference_variation_id[loc])
        location_variation_ids[loc] = [addVariationRow(column_setup, c) for c in eachcol(loc_vals)]
    end
    n_par_vecs = length(first(values(location_variation_ids)))
    for loc in projectLocations().varied
        get!(location_variation_ids, loc, fill(reference_variation_id[loc], n_par_vecs))
    end
    return [([loc => location_variation_ids[loc][i] for loc in projectLocations().varied] |> VariationID) for i in 1:n_par_vecs]
end

################## Database Helper Functions ##################

"""
    addColumns(location::Symbol, folder_id::Int, loc_types::Vector{DataType}, loc_targets::Vector{XMLPath})

Add columns to the variations database for the given location and folder_id.
"""
function addColumns(location::Symbol, folder_id::Int, loc_types::Vector{DataType}, loc_targets::Vector{XMLPath})
    folder = inputFolderName(location, folder_id)
    db_columns = locationVariationsDatabase(location, folder)
    basenames = inputsDict()[location]["basename"]
    basenames = basenames isa Vector ? basenames : [basenames] #! force basenames to be a vector to handle all the same way
    basename_is_varied = inputsDict()[location]["varied"] .&& ([splitext(bn)[2] .== ".xml" for bn in basenames]) #! the varied entry is either a singleton Boolean or a vector of the same length as basenames
    basename_ind = findall(basename_is_varied .&& isfile.([joinpath(locationPath(location, folder), bn) for bn in basenames]))
    @assert !isnothing(basename_ind) "Folder $(folder) does not contain a valid $(location) file to support variations. The options are $(basenames[basename_is_varied])."
    @assert length(basename_ind) == 1 "Folder $(folder) contains multiple valid $(location) files to support variations. The options are $(basenames[basename_is_varied])."

    path_to_xml = joinpath(locationPath(location, folder), basenames[basename_ind[1]])

    table_name = locationVariationsTableName(location)

    @debug validateParsBytes(db_columns, table_name)

    id_column_name = locationVariationIDName(location)
    prev_par_column_names = tableColumns(table_name; db=db_columns)
    filter!(x -> !(x in (id_column_name, "par_key")), prev_par_column_names)
    varied_par_column_names = [columnName(xp.xml_path) for xp in loc_targets]

    is_new_column = [!(varied_column_name in prev_par_column_names) for varied_column_name in varied_par_column_names]
    if any(is_new_column)
        new_column_names = varied_par_column_names[is_new_column]
        new_column_data_types = loc_types[is_new_column] .|> sqliteDataType
        xml_doc = parse_file(path_to_xml)
        default_values_for_new = [getSimpleContent(xml_doc, xp.xml_path) for xp in loc_targets[is_new_column]]
        free(xml_doc)
        for (new_column_name, data_type) in zip(new_column_names, new_column_data_types)
            DBInterface.execute(db_columns, "ALTER TABLE $(table_name) ADD COLUMN '$(new_column_name)' $(data_type);")
        end

        columns = join("\"" .* new_column_names .* "\"", ",")
        placeholders = join(["?" for _ in new_column_names], ",")
        query = "UPDATE $table_name SET ($columns) = ($placeholders);"
        stmt = SQLite.Stmt(db_columns, query)
        DBInterface.execute(stmt, Tuple(default_values_for_new))

        select_query = constructSelectQuery(table_name; selection="$(tableIDName(table_name)), par_key")
        par_key_df = queryToDataFrame(select_query; db=db_columns)

        default_values_for_new[default_values_for_new.=="true"] .= "1"
        default_values_for_new[default_values_for_new.=="false"] .= "0"

        new_bytes = reinterpret(UInt8, parse.(Float64, default_values_for_new))
        for row in eachrow(par_key_df)
            id = row[1]
            par_key = row[2]
            append!(par_key, new_bytes)
            DBInterface.execute(db_columns, "UPDATE $table_name SET par_key = ? WHERE $(tableIDName(table_name)) = ?;", (par_key, id))
        end
    end

    @debug validateParsBytes(db_columns, table_name)

    static_par_column_names = deepcopy(prev_par_column_names)
    previously_varied_names = varied_par_column_names[.!is_new_column]
    filter!(x -> !(x in previously_varied_names), static_par_column_names)

    return static_par_column_names, varied_par_column_names
end

"""
    ColumnSetup

A struct to hold the setup for the columns in a variations database.

# Fields
- `db::SQLite.DB`: The database connection to the variations database.
- `table::String`: The name of the table in the database.
- `variation_id_name::String`: The name of the variation ID column in the table.
- `ordered_inds::Vector{Int}`: Indexes into the concatenated static and varied values to get the parameters in the order of the table columns (excluding the variation ID and par_key columns).
- `static_values_db::Vector{String}`: The static values as strings for DB insertion.
- `static_values_key::Vector{Float64}`: The static values as floats for the par_key hash.
- `feature_str::String`: The string representation of the features (columns) in the table.
- `types::Vector{DataType}`: The data types of the columns in the table.
- `placeholders::String`: The string representation of the placeholders for the values in the table.
- `stmt_insert::SQLite.Stmt`: The prepared statement for inserting new rows into the table.
- `stmt_select::SQLite.Stmt`: The prepared statement for selecting existing rows from the table.
"""
struct ColumnSetup
    db::SQLite.DB
    table::String
    variation_id_name::String
    ordered_inds::Vector{Int}
    static_values_db::Vector{String}
    static_values_key::Vector{Float64}
    feature_str::String
    types::Vector{DataType}
    placeholders::String
    stmt_insert::SQLite.Stmt
    stmt_select::SQLite.Stmt
end

"""
    addVariationRow(column_setup::ColumnSetup, varied_values::Vector{<:Real})

Add a new row to the location variations database using the prepared statement.
If the row already exists, it returns the existing variation ID.
"""
function addVariationRow(column_setup::ColumnSetup, varied_values::AbstractVector{<:Real})
    db_varied_values = [t == Bool ? v == 1.0 : v for (t, v) in zip(column_setup.types, varied_values)] .|> string
    db_pars = [column_setup.static_values_db; db_varied_values] #! combine static and varied values into a single vector of strings
    pars_for_key = [column_setup.static_values_key; varied_values] |> Vector{Float64}

    par_key = reinterpret(UInt8, pars_for_key[column_setup.ordered_inds])
    params = Tuple([db_pars; [par_key]]) #! Combine static and varied values into a single tuple for database insertion
    new_id = stmtToDataFrame(column_setup.stmt_insert, params) |> x -> x[!, 1]

    new_added = length(new_id) == 1
    if !new_added
        df = stmtToDataFrame(column_setup.stmt_select, params; is_row=true)
        new_id = df[!, 1]
    end
    @debug validateParsBytes(column_setup.db, column_setup.table)
    return new_id[1]
end

"""
    setUpColumns(location::Symbol, folder_id::Int, loc_types::Vector{DataType}, loc_targets::Vector{XMLPath}, reference_variation_id::Int)

Set up the columns for the variations database for the given location and folder_id.
"""
function setUpColumns(location::Symbol, folder_id::Int, loc_types::Vector{DataType}, loc_targets::Vector{XMLPath}, reference_variation_id::Int)
    static_par_column_names, varied_par_column_names = addColumns(location, folder_id, loc_types, loc_targets)
    db_columns = locationVariationsDatabase(location, folder_id)
    table_name = locationVariationsTableName(location)
    variation_id_name = locationVariationIDName(location)

    if isempty(static_par_column_names)
        static_values_db = String[]
        static_values_key = Float64[]
        table_features = String[]
    else
        query = constructSelectQuery(table_name, "WHERE $(variation_id_name)=$(reference_variation_id);"; selection=join("\"" .* static_par_column_names .* "\"", ", "))
        static_values = queryToDataFrame(query; db=db_columns, is_row=true) |> x -> [c[1] for c in eachcol(x)]
        static_values_db = string.(static_values) |> Vector{String}
        static_values_key = copy(static_values)
        static_values_key[static_values_key.=="true"] .= 1.0
        static_values_key[static_values_key.=="false"] .= 0.0
        static_values_key = Vector{Float64}(static_values_key)
        table_features = copy(static_par_column_names)
    end
    append!(table_features, varied_par_column_names)

    feature_str = join("\"" .* table_features .* "\"", ",") * ",par_key"
    placeholders = join(["?" for _ in table_features], ",") * ",?"

    stmt_insert = SQLite.Stmt(db_columns, "INSERT OR IGNORE INTO $(table_name) ($(feature_str)) VALUES($placeholders) RETURNING $(variation_id_name);")
    where_str = "WHERE ($(feature_str))=($(placeholders))"
    stmt_str = constructSelectQuery(table_name, where_str; selection=variation_id_name)
    stmt_select = SQLite.Stmt(db_columns, stmt_str)

    column_to_full_index = Dict{String,Int}()
    for (ind, col_name) in enumerate(table_features)
        column_to_full_index[col_name] = ind
    end
    param_column_names = tableColumns(table_name; db=db_columns) #! ensure columns are up to date
    filter!(x -> !(x in (variation_id_name, "par_key")), param_column_names)
    ordered_inds = [column_to_full_index[col_name] for col_name in param_column_names]

    return ColumnSetup(db_columns, table_name, variation_id_name, ordered_inds, static_values_db, static_values_key, feature_str, loc_types, placeholders, stmt_insert, stmt_select)
end
