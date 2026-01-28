using Distributions
import Distributions: cdf

export ElementaryVariation, DiscreteVariation, DistributedVariation, CoVariation, LatentVariation
export UniformDistributedVariation, NormalDistributedVariation
export GridVariation, LHSVariation, SobolVariation, RBDVariation
export addDomainVariationDimension!, addCustomDataVariationDimension!, addAttackRateVariationDimension!

################## XMLPath ##################

"""
    XMLPath

Hold the XML path as a vector of strings.

PhysiCell uses a `:` in names for signals/behaviors from cell custom data.
For example, `custom:sample` is the default way to represent the `sample` custom data in a PhysiCell rule.
PhysiCellModelManager.jl uses `:` to indicate an attribute in an XML path and thus splits on `:` when looking for attribute values.
To avoid this conflict, PhysiCellModelManager.jl will internally replace `custom:<name>` and `custom: <name>` with `custom <name>`.
Users should never have to think about this.
Any PhysiCellModelManager.jl function that uses XML paths will automatically handle this replacement.
"""
struct XMLPath
    xml_path::Vector{String}

    function XMLPath(xml_path::AbstractVector{<:AbstractString})
        for path_element in xml_path
            tokens = split(path_element, ":")
            if length(tokens) < 4
                continue
            end
            msg = """
            Invalid XML path: $(path_element)
            It has $(length(tokens)) tokens (':' is the delimiter) but the only valid path element with >3 tokens if one of:
            - <tag>::<child_tag>:<child_tag_content>
            - <tag>:<attribute>:custom:<custom_data_name> (where the final ':' is part of how PhysiCell denotes custom data)
            - <tag>:<attribute>:custom: <custom_data_name> (where the final ':' is part of how PhysiCell denotes custom data)
            """
            @assert (isempty(tokens[2]) || tokens[3] == "custom") msg
        end
        return new(xml_path)
    end
end

columnName(xp::XMLPath) = columnName(xp.xml_path)

Base.show(io::IO, xp::XMLPath) = print(io, "XMLPath: $(columnName(xp))")

################## Abstract Variations ##################

"""
    AbstractVariation

Abstract type for variations.

# Subtypes
[`ElementaryVariation`](@ref), [`DiscreteVariation`](@ref), [`DistributedVariation`](@ref), [`CoVariation`](@ref)

# Methods
[`addVariations`](@ref), [`createTrial`](@ref), [`run`](@ref), 
[`_createTrial`](@ref)
"""
abstract type AbstractVariation end

"""
    ElementaryVariation <: AbstractVariation

The base type for variations of a single parameter.
"""
abstract type ElementaryVariation <: AbstractVariation end

"""
    DiscreteVariation

The location, target, and values of a discrete variation.

# Fields
- `location::Symbol`: The location of the variation. Can be `:config`, `:rulesets_collection`, `:intracellular`, `:ic_cell`, `:ic_ecm`. The location is inferred from the target.
- `target::XMLPath`: The target of the variation. The target is a vector of strings that represent the XML path to the element being varied. See [`XMLPath`](@ref) for more information.
- `values::Vector{T}`: The values of the variation. The values are the possible values that the target can take on.

A singleton value can be passed in place of `values` for convenience.

# Examples
```jldoctest
julia> dv = DiscreteVariation(["overall", "max_time"], [1440.0, 2880.0])
DiscreteVariation (Float64):
  location: config
  target: overall/max_time
  values: [1440.0, 2880.0]
```
```jldoctest
xml_path = rulePath("default", "cycle entry", "decreasing_signals", "max_response")
DiscreteVariation(xml_path, 0)
# output
DiscreteVariation (Int64):
  location: rulesets_collection
  target: behavior_ruleset:name:default/behavior:name:cycle entry/decreasing_signals/max_response
  values: [0]
```
```jldoctest
xml_path = icCellsPath("default", "disc", 1, "x0")
DiscreteVariation(xml_path, [0.0, 100.0])
# output
DiscreteVariation (Float64):
  location: ic_cell
  target: cell_patches:name:default/patch_collection:type:disc/patch:ID:1/x0
  values: [0.0, 100.0]
```
```jldoctest
xml_path = icECMPath(2, "ellipse", 1, "density")
DiscreteVariation(xml_path, [0.1, 0.2])
# output
DiscreteVariation (Float64):
  location: ic_ecm
  target: layer:ID:2/patch_collection:type:ellipse/patch:ID:1/density
  values: [0.1, 0.2]
```
"""
struct DiscreteVariation{T} <: ElementaryVariation
    location::Symbol
    target::XMLPath
    values::Vector{T}

    function DiscreteVariation(target::Vector{<:AbstractString}, values::Vector{T}) where T
        return DiscreteVariation(XMLPath(target), values)
    end

    function DiscreteVariation(target::XMLPath, values::Vector{T}) where T
        location = variationLocation(target)
        return new{T}(location, target, values)
    end
end

DiscreteVariation(xml_path::Vector{<:AbstractString}, value::T) where T = DiscreteVariation(xml_path, Vector{T}([value]))

Base.length(discrete_variation::DiscreteVariation) = length(discrete_variation.values)

function Base.show(io::IO, dv::DiscreteVariation)
    println(io, "DiscreteVariation ($(variationDataType(dv))):")
    println(io, "  location: $(dv.location)")
    println(io, "  target: $(columnName(dv))")
    println(io, "  values: $(dv.values)")
end

function ElementaryVariation(target::Vector{<:AbstractString}, v; kwargs...)
    if v isa Distribution{Univariate}
        return DistributedVariation(target, v; kwargs...)
    else
        return DiscreteVariation(target, v; kwargs...)
    end
end

"""
    DistributedVariation

The location, target, and distribution of a distributed variation.

Analagousy to [`DiscreteVariation`](@ref), instances of `DistributedVariation` can be initialized with a `target` (XML path) and a `distribution` (a distribution from the `Distributions` package).
Alternatively, users can use the [`UniformDistributedVariation`](@ref) and [`NormalDistributedVariation`](@ref) functions to create instances of `DistributedVariation`.

# Fields
- `location::Symbol`: The location of the variation. Can be `:config`, `:rulesets_collection`, `:intracellular`, `:ic_cell`, or `:ic_ecm`. The location is inferred from the target.
- `target::XMLPath`: The target of the variation. The target is a vector of strings that represent the XML path to the element being varied. See [`XMLPath`](@ref) for more information.
- `distribution::Distribution`: The distribution of the variation.
- `flip::Bool=false`: Whether to flip the distribution, i.e., when asked for the iCDF of `x`, return the iCDF of `1-x`. Useful for [`CoVariation`](@ref)'s.

# Examples
```jldoctest
using Distributions
d = Uniform(1, 2)
DistributedVariation(PhysiCellModelManager.apoptosisPath("default", "death_rate"), d)
# output
DistributedVariation:
  location: config
  target: cell_definitions/cell_definition:name:default/phenotype/death/model:code:100/death_rate
  distribution: Distributions.Uniform{Float64}(a=1.0, b=2.0)
```
```jldoctest
using Distributions
d = Uniform(1, 2)
flip = true # the cdf on this variation will decrease from 1 to 0 as the value increases from 1 to 2
DistributedVariation(PhysiCellModelManager.necrosisPath("default", "death_rate"), d; flip=flip)
# output
DistributedVariation (flipped):
  location: config
  target: cell_definitions/cell_definition:name:default/phenotype/death/model:code:101/death_rate
  distribution: Distributions.Uniform{Float64}(a=1.0, b=2.0)
```
"""
struct DistributedVariation <: ElementaryVariation
    location::Symbol
    target::XMLPath
    distribution::Distribution
    flip::Bool

    function DistributedVariation(target::Vector{<:AbstractString}, distribution::Distribution; flip::Bool=false)
        return DistributedVariation(XMLPath(target), distribution; flip=flip)
    end
    function DistributedVariation(target::XMLPath, distribution::Distribution; flip::Bool=false)
        location = variationLocation(target)
        return new(location, target, distribution, flip)
    end
end

"""
    variationTarget(av::AbstractVariation)

Get the type [`XMLPath`](@ref) target(s) of a variation
"""
variationTarget(ev::ElementaryVariation) = ev.target

"""
    variationLocation(av::AbstractVariation)

Get the location of a variation as a `Symbol`, e.g., `:config`, `:rulesets_collection`, etc.
Can also pass in an [`XMLPath`](@ref) object.
"""
variationLocation(ev::ElementaryVariation) = ev.location

columnName(ev::ElementaryVariation) = variationTarget(ev) |> columnName

Base.length(::DistributedVariation) = -1 #! set to -1 to be a convention

function Base.show(io::IO, dv::DistributedVariation)
    println(io, "DistributedVariation" * (dv.flip ? " (flipped)" : "") * ":")
    println(io, "  location: $(dv.location)")
    println(io, "  target: $(columnName(dv))")
    println(io, "  distribution: $(dv.distribution)")
end

"""
    UniformDistributedVariation(xml_path::Vector{<:AbstractString}, lb::T, ub::T; flip::Bool=false) where {T<:Real}

Create a distributed variation with a uniform distribution.
"""
function UniformDistributedVariation(xml_path::Vector{<:AbstractString}, lb::T, ub::T; flip::Bool=false) where {T<:Real}
    return DistributedVariation(xml_path, Uniform(lb, ub); flip=flip)
end

"""
    NormalDistributedVariation(xml_path::Vector{<:AbstractString}, mu::T, sigma::T; lb::Real=-Inf, ub::Real=Inf, flip::Bool=false) where {T<:Real}

Create a (possibly truncated) distributed variation with a normal distribution.
"""
function NormalDistributedVariation(xml_path::Vector{<:AbstractString}, mu::T, sigma::T; lb::Real=-Inf, ub::Real=Inf, flip::Bool=false) where {T<:Real}
    return DistributedVariation(xml_path, truncated(Normal(mu, sigma), lb, ub); flip=flip)
end

"""
    variationValues(ev::ElementaryVariation[, cdf])

Get the values of an [`ElementaryVariation`](@ref).

If `ev` is a [`DiscreteVariation`](@ref), all values are returned unless `cdf` is provided.
In that case, the CDF(s) is linearly converted into an index into the values vector and the corresponding value is returned.

If `ev` is a [`DistributedVariation`](@ref), the `cdf` is required and the iCDF is returned.
The `cdf` can be a single value or a vector of values.

# Arguments
- `ev::ElementaryVariation`: The variation to get the values of.
- `cdf`: The cumulative distribution function (CDF) values to use for the variation.
"""
variationValues(discrete_variation::DiscreteVariation) = discrete_variation.values

function variationValues(discrete_variation::DiscreteVariation, cdf::Vector{<:Real})
    index = floor.(Int, cdf * length(discrete_variation)) .+ 1
    index[index.==(length(discrete_variation)+1)] .= length(discrete_variation) #! if cdf = 1, index = length(discrete_variation)+1, so we set it to length(discrete_variation)
    return discrete_variation.values[index]
end

function variationValues(dv::DistributedVariation, cdf::Vector{<:Real})
    return map(Base.Fix1(quantile, dv.distribution), dv.flip ? 1 .- cdf : cdf)
end

variationValues(ev, cdf::Real) = variationValues(ev, [cdf])

variationValues(::DistributedVariation) = error("A cdf must be provided for a DistributedVariation.")

"""
    variationValues(f::Function, ev::ElementaryVariation[, cdf])

Apply a function `f` to each of the variation values of an [`ElementaryVariation`](@ref).
See [`variationValues`](@ref) for details on how the variation values are obtained.
"""
variationValues(f::Function, args...) = f.(variationValues(args...))

"""
    variationDataType(ev::ElementaryVariation)

Get the data type of the variation.
"""
variationDataType(::DiscreteVariation{T}) where T = T
variationDataType(dv::DistributedVariation) = eltype(dv.distribution)

"""
    sqliteDataType(ev::ElementaryVariation)
    sqliteDataType(data_type::DataType)

Get the SQLite data type to hold the Julia data type.

These are the mappings in the order of the if-else statements:
- `Bool` -> `TEXT`
- `Integer` -> `INT`
- `Real` -> `REAL`
- otherwise -> `TEXT`
"""
function sqliteDataType(ev::ElementaryVariation)
    return sqliteDataType(variationDataType(ev))
end

function sqliteDataType(data_type::DataType)
    if data_type == Bool
        return "TEXT"
    elseif data_type <: Integer
        return "INT"
    elseif data_type <: Real
        return "REAL"
    else
        return "TEXT"
    end
end

"""
    cdf(ev::ElementaryVariation, x::Real)

Get the cumulative distribution function (CDF) of the variation at `x`.

If `ev` is a [`DiscreteVariation`](@ref), `x` must be in the values of the variation.
The value returned is from `0:Δ:1` where `Δ=1/(n-1)` and `n` is the number of values in the variation.

If `ev` is a [`DistributedVariation`](@ref), the CDF is computed from the distribution of the variation.
"""
function cdf(discrete_variation::DiscreteVariation, x::Real)
    if !(x in discrete_variation.values)
        error("Value not in elementary variation values.")
    end
    return (findfirst(isequal(x), discrete_variation.values) - 1) / (length(discrete_variation) - 1)
end

function cdf(dv::DistributedVariation, x::Real)
    out = cdf(dv.distribution, x)
    if dv.flip
        return 1 - out
    end
    return out
end

cdf(ev::ElementaryVariation, ::Real) = error("cdf not defined for $(typeof(ev))")

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

################## Co-Variations ##################

"""
    CoVariation{T<:ElementaryVariation} <: AbstractVariation

A co-variation of one or more variations.
Each must be of the same type, either `DiscreteVariation` or `DistributedVariation`.

# Fields
- `variations::Vector{T}`: The variations that make up the co-variation.

# Constructors
- `CoVariation(inputs::Vararg{Tuple{Vector{<:AbstractString},Distribution},N}) where {N}`: Create a co-variation from a vector of XML paths and distributions.
```julia
CoVariation((xml_path_1, d_1), (xml_path_2, d_2), ...) # d_i are distributions, e.g. `d_1 = Uniform(1, 2)`
```
- `CoVariation(inputs::Vararg{Tuple{Vector{<:AbstractString},Vector},N}) where {N}`: Create a co-variation from a vector of XML paths and values.
```julia
CoVariation((xml_path_1, val_1), (xml_path_2, val_2), ...) # val_i are vectors of values, e.g. `val_1 = [0.1, 0.2]`, or singletons, e.g. `val_2 = 0.3`
```
- `CoVariation(evs::Vector{ElementaryVariation})`: Create a co-variation from a vector of variations all the same type.
```julia
CoVariation([discrete_1, discrete_2, ...]) # all discrete variations and with the same number of values
CoVariation([distributed_1, distributed_2, ...]) # all distributed variations
```
- `CoVariation(inputs::Vararg{T}) where {T<:ElementaryVariation}`: Create a co-variation from a variable number of variations all the same type.
```julia
CoVariation(discrete_1, discrete_2, ...) # all discrete variations and with the same number of values
CoVariation(distributed_1, distributed_2, ...) # all distributed variations
```
"""
struct CoVariation{T<:ElementaryVariation} <: AbstractVariation
    variations::Vector{T}

    function CoVariation(inputs::Vararg{Tuple{Vector{<:AbstractString},Distribution},N}) where {N}
        variations = DistributedVariation[]
        for (xml_path, distribution) in inputs
            @assert xml_path isa Vector{<:AbstractString} "xml_path must be a vector of strings"
            push!(variations, DistributedVariation(xml_path, distribution))
        end
        return new{DistributedVariation}(variations)
    end

    function CoVariation(inputs::Vararg{Tuple{Vector{<:AbstractString},Vector},N}) where {N}
        variations = DiscreteVariation[]
        n_discrete = -1
        for (xml_path, val) in inputs
            n_vals = length(val)
            if n_discrete == -1
                n_discrete = n_vals
            else
                @assert n_discrete == n_vals "All discrete vals must have the same length"
            end
            push!(variations, DiscreteVariation(xml_path, val))
        end
        return new{DiscreteVariation}(variations)
    end

    CoVariation(evs::Vector{DistributedVariation}) = return new{DistributedVariation}(evs)

    function CoVariation(evs::Vector{<:DiscreteVariation})
        @assert (length.(evs) |> unique |> length) == 1 "All DiscreteVariations in a CoVariation must have the same length."
        return new{DiscreteVariation}(evs)
    end

    function CoVariation(inputs::Vararg{T}) where {T<:ElementaryVariation}
        return CoVariation(Vector{T}([inputs...]))
    end
end

variationTarget(cv::CoVariation) = variationTarget.(cv.variations)
variationLocation(cv::CoVariation) = variationLocation.(cv.variations)
columnName(cv::CoVariation) = columnName.(cv.variations) |> x -> join(x, " AND ")

function Base.length(cv::CoVariation)
    return length(cv.variations[1])
end

function Base.show(io::IO, cv::CoVariation)
    data_type = typeof(cv).parameters[1]
    data_type_str = string(data_type)
    title_str = "CoVariation ($(data_type_str)):"
    println(io, title_str)
    println(io, "-"^length(title_str))
    locations = variationLocation(cv)
    unique_locations = unique(locations)
    for location in unique_locations
        println(io, "  Location: $location")
        location_inds = findall(isequal(location), locations)
        for ind in location_inds
            println(io, "  Variation $ind:")
            println(io, "    target: $(columnName(cv.variations[ind]))")
            if data_type == DiscreteVariation
                println(io, "    values: $(variationValues(cv.variations[ind]))")
            elseif data_type == DistributedVariation
                println(io, "    distribution: $(cv.variations[ind].distribution)")
                println(io, "    flip: $(cv.variations[ind].flip)")
            end
        end
    end
end

################## Variation Dimension Functions ##################

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

################## Database Interface Functions ##################

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
- `static_values::Vector{String}`: The static values for the columns that are not varied.
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
    addVariationRows(inputs::InputFolders, reference_variation_id::VariationID, loc_dicts::Dict)

Add new rows to the variations databases for the given inputs and return the new variation IDs.
"""
function addVariationRows(inputs::InputFolders, reference_variation_id::VariationID, loc_dicts::Dict)
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

################## Specialized Variations ##################

"""
    AddVariationMethod

Abstract type for variation methods.

# Subtypes
[`GridVariation`](@ref), [`LHSVariation`](@ref), [`SobolVariation`](@ref), [`RBDVariation`](@ref)

# Methods
[`addVariations`](@ref), [`createTrial`](@ref), [`run`](@ref), 
[`_createTrial`](@ref)
"""
abstract type AddVariationMethod end

"""
    GridVariation <: AddVariationMethod

A variation method that creates a grid of all possible combinations of the values of the variations.

# Examples
```jldoctest
julia> GridVariation() # the only method for GridVariation
GridVariation()
```
"""
struct GridVariation <: AddVariationMethod end

"""
    LHSVariation <: AddVariationMethod

A variation method that creates a Latin Hypercube Sample of the values of the variations.

# Fields
Default values from constructors are shown.
- `n::Int`: The number of samples to take.
- `add_noise::Bool=false`: Whether to add noise to the samples or have them be in the center of the bins.
- `rng::AbstractRNG=Random.GLOBAL_RNG`: The random number generator to use.
- `orthogonalize::Bool=true`: Whether to orthogonalize the samples. See https://en.wikipedia.org/wiki/Latin_hypercube_sampling#:~:text=In%20orthogonal%20sampling

# Examples
```jldoctest
julia> LHSVariation(4) # set `n` and use default values for the rest
LHSVariation(4, false, Random.TaskLocalRNG(), true)
```
```jldoctest
using Random
LHSVariation(; n=16, add_noise=true, rng=MersenneTwister(1234), orthogonalize=false)
# output
LHSVariation(16, true, MersenneTwister(1234), false)
```
"""
struct LHSVariation <: AddVariationMethod
    n::Int
    add_noise::Bool
    rng::AbstractRNG
    orthogonalize::Bool
end
LHSVariation(n; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true) = LHSVariation(n, add_noise, rng, orthogonalize)
LHSVariation(; n::Int=4, kwargs...) = LHSVariation(n; kwargs...)

"""
    SobolVariation <: AddVariationMethod

A variation method that creates a Sobol sequence of the values of the variations.

See [`generateSobolCDFs`](@ref) for more information on how the Sobol sequence is generated based on `n` and the other fields.

See the GlobalSensitivity.jl package for more information on `RandomizationMethod`'s to use.

# Fields
Default values from constructors are shown.
- `n::Int`: The number of samples to take.
- `n_matrices::Int=1`: The number of matrices to use in the Sobol sequence.
- `randomization::RandomizationMethod=NoRand()`: The randomization method to use on the deterministic Sobol sequence.
- `skip_start::Union{Missing, Bool, Int}=missing`: Whether to skip the start of the sequence. Missing means PhysiCellModelManager.jl will choose the best option.
- `include_one::Union{Missing, Bool}=missing`: Whether to include 1 in the sequence. Missing means PhysiCellModelManager.jl will choose the best option.

# Examples
```jldoctest
julia> SobolVariation(9) # set `n` and use default values for the rest; will use [0, 0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875, 1]
SobolVariation(9, 1, QuasiMonteCarlo.NoRand(), missing, missing)
```
```jldoctest
julia> SobolVariation(15; skip_start=true) # use [0.5, 0.25, 0.75, ..., 1/16, 3/16, ..., 15/16]
SobolVariation(15, 1, QuasiMonteCarlo.NoRand(), true, missing)
```
```jldoctest
julia> SobolVariation(4; include_one=true) # use [0, 0.5, 1] and one of [0.25, 0.75]
SobolVariation(4, 1, QuasiMonteCarlo.NoRand(), missing, true)
```
"""
struct SobolVariation <: AddVariationMethod
    n::Int
    n_matrices::Int
    randomization::RandomizationMethod
    skip_start::Union{Missing,Bool,Int}
    include_one::Union{Missing,Bool}
end
SobolVariation(n::Int; n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing,Bool,Int}=missing, include_one::Union{Missing,Bool}=missing) = SobolVariation(n, n_matrices, randomization, skip_start, include_one)
SobolVariation(; pow2::Int=1, n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing,Bool,Int}=missing, include_one::Union{Missing,Bool}=missing) = SobolVariation(2^pow2, n_matrices, randomization, skip_start, include_one)

"""
    RBDVariation <: AddVariationMethod

A variation method that creates a Random Balance Design of the values of the variations.

This creates `n` sample points where the values in each dimension are uniformly distributed.
By default, this will use Sobol sequences (see [`SobolVariation`](@ref)) to create the sample points.
If `use_sobol` is `false`, it will use random permutations of uniformly spaced points for each dimension.

# Fields
Default values from constructors are shown.
- `n::Int`: The number of samples to take.
- `rng::AbstractRNG=Random.GLOBAL_RNG`: The random number generator to use.
- `use_sobol::Bool=true`: Whether to use Sobol sequences to create the sample points.
Do not set these next two fields unless you know what you are doing. Let PhysiCellModelManager.jl compute them.
- `pow2_diff::Union{Missing, Int}=missing`: The difference between `n` and the nearest power of 2. Missing means PhysiCellModelManager.jl will compute it if using Sobol sequences.
- `num_cycles::Union{Missing, Int, Rational}=missing`: The number of cycles to use in the Sobol sequence. Missing means PhysiCellModelManager.jl will set it.

# Examples
```jldoctest
julia> PhysiCellModelManager.RBDVariation(4) # set `n` and use default values for the rest
RBDVariation(4, Random.TaskLocalRNG(), true, 0, 1//2)
```
```jldoctest
julia> PhysiCellModelManager.RBDVariation(4; use_sobol=false) # use random permutations of uniformly spaced points
RBDVariation(4, Random.TaskLocalRNG(), false, missing, 1//1)
```
"""
struct RBDVariation <: AddVariationMethod
    n::Int
    rng::AbstractRNG
    use_sobol::Bool
    pow2_diff::Union{Missing,Int}
    num_cycles::Rational

    function RBDVariation(n::Int, rng::AbstractRNG, use_sobol::Bool, pow2_diff::Union{Missing,Int}, num_cycles::Union{Missing,Int,Rational})
        if use_sobol
            k = log2(n) |> round |> Int #! nearest power of 2 to n
            if ismissing(pow2_diff)
                pow2_diff = n - 2^k
            else
                @assert pow2_diff == n - 2^k "pow2_diff must be n - 2^k for RBDVariation with Sobol sequence"
            end
            @assert abs(pow2_diff) <= 1 "n must be within 1 of a power of 2 for RBDVariation with Sobol sequence"
            if ismissing(num_cycles)
                num_cycles = 1 // 2
            else
                @assert num_cycles == 1 // 2 "num_cycles must be 1//2 for RBDVariation with Sobol sequence"
            end
        else
            pow2_diff = missing #! not used in this case
            if ismissing(num_cycles)
                num_cycles = 1
            else
                @assert num_cycles == 1 "num_cycles must be 1 for RBDVariation with random sequence"
            end
        end
        return new(n, rng, use_sobol, pow2_diff, num_cycles)
    end
end

RBDVariation(n::Int; rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true, pow2_diff=missing, num_cycles=missing) = RBDVariation(n, rng, use_sobol, pow2_diff, num_cycles)

"""
    AddVariationsResult

Abstract type for the result of adding variations to a set of inputs.

# Subtypes
[`AddGridVariationsResult`](@ref), [`AddLHSVariationsResult`](@ref), [`AddSobolVariationsResult`](@ref), [`AddRBDVariationsResult`](@ref)
"""
abstract type AddVariationsResult end

"""
    addVariations(method::AddVariationMethod, inputs::InputFolders, avs::Vector{<:AbstractVariation}, reference_variation_id::VariationID=VariationID(inputs))

Add variations to the inputs using the specified [`AddVariationMethod`](@ref) and the variations in `avs`.
"""
function addVariations(method::AddVariationMethod, inputs::InputFolders, avs::Vector{<:AbstractVariation}, reference_variation_id::VariationID=VariationID(inputs))
    pv = ParsedVariations(avs)
    return addVariations(method, inputs, pv, reference_variation_id)
end

##################  Latent Variations ##################

"""
    LatentVariation{T<:Union{Vector{<:Real},<:Distribution}} <: AbstractVariation

A variation that uses latent parameters to generate the variation values.

Whereas [`CoVariation`](@ref)s enforce a 1D relationship between parameters, [`LatentVariation`](@ref)s allow for multi-dimensional relationships between parameters via the mapping functions and latent parameters.
These latent parameters are not recorded in the database; only the values of the target parameters are recorded.

Internally, [`ParsedVariations`](@ref) converts all variations to `LatentVariation`s for processing.

# Sensitivity Analysis
When performing senstivity analysis with these, the latent parameter names are used to identify the parameters in the Monad DataFrames.
If the user does not provide names for the latent parameters, default names are generated based on the targets. See [`defaultLatentParameterNames`](@ref) for more information.

# Fields
- `latent_parameters::Vector{T}`: The latent parameters used to generate the variation values. Must be either all vectors of real values or all distributions.
- `latent_parameter_names::Vector{String}`: The names of the latent parameters (useful for interpretable names in sensitivity analysis). Default names are generated if not provided.
- `locations::Vector{Symbol}`: The locations where the variations are applied.
- `targets::Vector{XMLPath}`: The target parameters to vary.
- `maps::Vector{<:Function}`: The mapping functions that take in the latent parameters (as a vector) and output the target parameter value.
- `types::Vector{DataType}`: The data types of the target parameters.

Note:
- The length of `latent_parameters` and `latent_parameter_names` must be the same, one per latent parameter.
- The lengths of `locations`, `targets`, `maps`, and `types` must be the same, one per target parameter.

# Examples
```jldoctest
using Distributions
latent_parameters = [Uniform(0.0, 1.0), truncated(Normal(0.5, 0.1); lower=0)] # two latent parameters: one setting the bottom threshold and one setting the threshold gap
latent_parameter_names = ["bottom_threshold", "threshold_gap"] # optional, human-interpretable names for the latent parameters
targets = [rulePath("stem", "asymmetric division to type1", "increasing_signals", "signal:name:custom:alpha", "half_max"), # this will track the bottom threshold
           rulePath("stem", "asymmetric division to type1", "decreasing_signals", "signal:name:custom:alpha", "half_max"), # this will track the top threshold
           rulePath("stem", "asymmetric division to type2", "increasing_signals", "signal:name:custom:alpha", "half_max")] # this will also track the top threshold
maps = [lp -> lp[1], # map the first latent parameter to the bottom threshold
        lp -> lp[1] + lp[2], # map the sum of the two latent parameters to the top threshold
        lp -> lp[1] + lp[2]] # map the sum of the two latent parameters to the top threshold for the second rule as well
LatentVariation(latent_parameters, targets, maps, latent_parameter_names)
# output
LatentVariation (Distribution), 2 -> 3:
---------------------------------------
  Latent Parameters (n = 2):
    lp#1. bottom_threshold (Distributions.Uniform{Float64}(a=0.0, b=1.0))
    lp#2. threshold_gap (Truncated(Distributions.Normal{Float64}(μ=0.5, σ=0.1); lower=0.0))
  Target Parameters (n = 3):
    tp#1. stem: custom:alpha increases asymmetric division to type1 half max
            Location: rulesets_collection
            Target: XMLPath: behavior_ruleset:name:stem/behavior:name:asymmetric division to type1/increasing_signals/signal:name:custom:alpha/half_max
    tp#2. stem: custom:alpha decreases asymmetric division to type1 half max
            Location: rulesets_collection
            Target: XMLPath: behavior_ruleset:name:stem/behavior:name:asymmetric division to type1/decreasing_signals/signal:name:custom:alpha/half_max
    tp#3. stem: custom:alpha increases asymmetric division to type2 half max
            Location: rulesets_collection
            Target: XMLPath: behavior_ruleset:name:stem/behavior:name:asymmetric division to type2/increasing_signals/signal:name:custom:alpha/half_max
```
"""
struct LatentVariation{T<:Union{Vector{<:Real},<:Distribution}} <: AbstractVariation
    latent_parameters::Vector{T}
    latent_parameter_names::Vector{String}
    locations::Vector{Symbol}
    targets::Vector{XMLPath}
    maps::Vector{<:Function}
    types::Vector{DataType}

    function LatentVariation(latent_parameters::Vector{<:Vector{T}}, targets::AbstractVector{XMLPath}, maps::Vector{<:Function}, lp_names::AbstractVector{<:AbstractString}=defaultLatentParameterNames(latent_parameters, targets)) where T<:Real
        @assert length(targets) == length(maps) "LatentVariation requires the number of locations, targets, and maps to be the same. Found $(length(locations)), $(length(targets)), $(length(maps)), respectively."
        locations = variationLocation.(targets)
        types = map(maps) do fn
            sample_input = [lp[1] for lp in latent_parameters]
            sample_output = fn(sample_input)
            eltype(sample_output)
        end
        return new{Vector{T}}(latent_parameters, lp_names, locations, targets, maps, types)
    end
    
    function LatentVariation(latent_parameters::Vector{T}, targets::AbstractVector{XMLPath}, maps::Vector{<:Function}, lp_names::AbstractVector{<:AbstractString}=defaultLatentParameterNames(latent_parameters, targets)) where T<:Distribution
        @assert length(targets) == length(maps) "LatentVariation requires the number of locations, targets, and maps to be the same. Found $(length(locations)), $(length(targets)), $(length(maps)), respectively."
        locations = variationLocation.(targets)
        types = map(maps) do fn
            sample_input = [quantile(lp, 0.5) for lp in latent_parameters]
            sample_output = fn(sample_input)
            eltype(sample_output)
        end
        return new{T}(latent_parameters, lp_names, locations, targets, maps, types)
    end
end

function LatentVariation(latent_parameters::Vector{T}, targets::AbstractVector{<:AbstractVector{<:AbstractString}}, maps::Vector{<:Function}, lp_names::AbstractVector{<:AbstractString}=String[]) where T<:Union{Vector{<:Real},<:Distribution}
    targets = XMLPath.(targets)
    if isempty(lp_names)
        lp_names = defaultLatentParameterNames(latent_parameters, targets)
    end
    return LatentVariation(latent_parameters, targets, maps, lp_names)
end

"""
    defaultLatentParameterNames(latent_parameters::Vector, targets::Vector{XMLPath})

Generate default names for latent parameters based on the target parameters.
For each latent parameter, the name is constructed as:
`"<target_1> | <target_2> | ... | lp#<i>"` where `<target_n>` is the column name of the n-th target parameter and `<i>` is the index of the latent parameter.

# Returns
- `Vector{String}`: A vector of default names for the latent parameters.
"""
function defaultLatentParameterNames(latent_parameters::Vector, targets::Vector{XMLPath})
    par_names = join(columnName.(targets), " | ")
    return [par_names * " | lp#$(i)" for i in 1:length(latent_parameters)]
end

function LatentVariation(dv::T) where T<:DiscreteVariation
    latent_parameters = [dv.values]
    targets = [variationTarget(dv)]
    maps = [first]
    return LatentVariation(latent_parameters, targets, maps, [columnName(dv)])
end

function LatentVariation(dv::T) where T<:DistributedVariation
    latent_parameters = [Uniform(0,1)]
    targets = [variationTarget(dv)]
    maps = [dv.flip ? us -> quantile(dv.distribution, 1 - us[1]) : us -> quantile(dv.distribution, us[1])] #! us is the vector of uniform samples (one per latent parameter)
    return LatentVariation(latent_parameters, targets, maps, [columnName(dv)])
end

function LatentVariation(cv::CoVariation{T}) where T<:DiscreteVariation
    latent_parameters = [collect(1:length(cv))]
    targets = variationTarget(cv)
    maps = [I -> cv.variations[i].values[I[1]] for i in 1:length(cv.variations)]
    return LatentVariation(latent_parameters, targets, maps, [columnName(cv)])
end

function LatentVariation(cv::CoVariation{T}) where T<:DistributedVariation
    latent_parameters = [Uniform(0.0, 1.0)]
    targets = variationTarget(cv)
    maps = map(cv.variations) do dv
        dv.flip ? us -> quantile(dv.distribution, 1 - us[1]) : us -> quantile(dv.distribution, us[1]) #! us is the vector of uniform samples (one per latent parameter)
    end
    return LatentVariation(latent_parameters, targets, maps, [columnName(cv)])
end

LatentVariation(lv::LatentVariation) = lv

Base.size(lv::LatentVariation{<:Vector{<:Real}}) = length.(lv.latent_parameters)
Base.size(lv::LatentVariation{<:Distribution}) = -ones(Int, length(lv.latent_parameters)) #! set to -1 to follow the convention from Distributed Variation
nLatentDims(lv::LatentVariation) = length(lv.latent_parameters)

variationTarget(lv::LatentVariation) = lv.targets
nTargetDims(lv::LatentVariation) = length(variationTarget(lv))
columnName(lv::LatentVariation) = variationTarget(lv) .|> columnName

variationLocation(lv::LatentVariation) = lv.locations

function Base.show(io::IO, lv::LatentVariation)
    data_type = lv.latent_parameters[1] isa Distribution ? "Distribution" : "Discrete"
    n_latent = nLatentDims(lv)
    n_targets = nTargetDims(lv)
    title_str = "LatentVariation ($data_type), $(n_latent) -> $(n_targets):"
    println(io, title_str)
    println(io, "-"^length(title_str))
    indent = "  "

    println(io, indent, "Latent Parameters (n = $n_latent):")
    all_latent_nums = ["lp#$(i)." for i in 1:nLatentDims(lv)]
    biggest_width = maximum(length.(all_latent_nums))
    for (n, name, lp) in zip(all_latent_nums, lv.latent_parameter_names, lv.latent_parameters)
        print(io, indent, indent, lpad(n, biggest_width), " $(name)")
        if lp isa Distribution
            println(io, " ($(lp))")
        else
            println(io, " ([", join(lp, ", "), "])")
        end
    end

    println(io, indent, "Target Parameters (n = $n_targets):")
    all_target_nums = ["tp#$(i)." for i in 1:nTargetDims(lv)]
    biggest_width = maximum(length.(all_target_nums))
    indent2 = indent * indent * ' '^(biggest_width + 3)
    last_n = last(all_target_nums)
    for (n, loc, tar) in zip(all_target_nums, variationLocation(lv), variationTarget(lv))
        short_target = shortVariationName(loc, columnName(tar))
        println(io, indent, indent, lpad(n, biggest_width), " $(short_target)")
        println(io, indent2, "Location: $(loc)")
        print(io, indent2, "Target: $(tar)")
        if n != last_n
            println(io)
        end
    end
end

"""
    variationValues(lv::LatentVariation)

Compute the variation values for all combinations of latent parameters in the LatentVariation.
Only works for LatentVariations with discrete latent parameters.

# Returns
- `Array{Float64}`: A matrix where each row corresponds to a unique combination of latent parameters and each column corresponds to a target parameter.
"""
function variationValues(lv::LatentVariation{<:Vector{<:Real}})
    cart_inds = CartesianIndices(Dims(size(lv)))
    lin_inds = LinearIndices(Dims(size(lv)))
    ret_val = Array{Float64}(undef, length(lv.maps), prod(size(lv)))
    for (I, li) in zip(cart_inds, lin_inds)
        lp_vals = [lps[i] for (i, lps) in zip(I.I, lv.latent_parameters)]
        ret_val[:, li] .= [fn(lp_vals) for fn in lv.maps]
    end
    return ret_val
end

function variationValues(lv::LatentVariation{<:Vector{<:Real}}, cdfs::AbstractVector{<:Real})
    @assert length(cdfs) == nLatentDims(lv) "CDF vector length must match number of latent parameters."
    latent_pars = [floor(Int, cdf * length(lp)) + 1 for (cdf, lp) in zip(cdfs, lv.latent_parameters)]
    return [fn(latent_pars) for fn in lv.maps]
end

function variationValues(lv::LatentVariation{<:Distribution}, cdfs::AbstractVector{<:Real})
    @assert length(cdfs) == nLatentDims(lv) "CDF vector length must match number of latent parameters."
    lp_vals = [quantile(d, cdf_val) for (d, cdf_val) in zip(lv.latent_parameters, cdfs)]
    return [fn(lp_vals) for fn in lv.maps]
end

function variationValues(lv::LatentVariation{<:Distribution}, cdfs::AbstractVector{<:AbstractVector})
    return stack(sample_cdfs -> variationValues(lv, sample_cdfs), cdfs)
end

function variationValues(lv::LatentVariation{<:Distribution}, cdfs::AbstractMatrix{<:Real})
    @assert size(cdfs, 1) == nLatentDims(lv) "CDF matrix number of rows must match number of latent parameters."
    return stack(sample_cdfs -> variationValues(lv, sample_cdfs), eachcol(cdfs))
end

################### Parsed Variations ##################

"""
    ParsedVariations

A struct that holds the parsed variations and their sizes for all locations.

# Fields
- `latent_variations::Vector{T}`: The latent variations parsed from the input variations.
"""
struct ParsedVariations{T<:LatentVariation}
    latent_variations::Vector{T}

    function ParsedVariations(avs::Vector{<:AbstractVariation})
        location_variations_dict = Dict{Symbol,Any}()
        for location in projectLocations().varied
            location_variations_dict[location] = (XMLPath[], Int[], [], Function[])
        end
        s = Set{Tuple{Symbol,XMLPath}}()
        lvs = LatentVariation.(avs) |> Vector{LatentVariation}
        for lv in lvs
            for (loc, tar) in zip(variationLocation(lv), variationTarget(lv))
                @assert !in((loc, tar), s) """The following XMLPath for location $(loc) is repeated, meaning being set twice. Please correct

                    $tar
                """
                push!(s, (loc, tar))
            end
        end

        return new{eltype(lvs)}(lvs)
    end
end

function variationValues(pv::ParsedVariations, cdf_col::AbstractVector{<:Real})
    @assert length(cdf_col) == nLatentDims(pv) "CDF vector length must match number of latent parameters."
    next_ind = 1
    sample_par_vals = []
    for lv in pv.latent_variations
        n_latent_dims = nLatentDims(lv)
        cdf_subset = cdf_col[next_ind:(next_ind+n_latent_dims-1)]
        next_ind += n_latent_dims
        par_values = variationValues(lv, cdf_subset)
        push!(sample_par_vals, par_values)
    end
    vcat(sample_par_vals...)
end

nLatentDims(pv::ParsedVariations) = mapreduce(nLatentDims, +, pv.latent_variations)
nTargetDims(pv::ParsedVariations) = mapreduce(nTargetDims, +, pv.latent_variations)

################## Grid Variations ##################

"""
    AddGridVariationsResult <: AddVariationsResult

A struct that holds the result of adding grid variations to a set of inputs.

# Fields
- `variation_ids::AbstractArray{VariationID}`: The variation IDs for all the variations added.
"""
struct AddGridVariationsResult <: AddVariationsResult
    variation_ids::AbstractArray{VariationID}
end

function addVariations(::GridVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_id::VariationID)
    if isempty(pv.latent_variations)
        return AddGridVariationsResult([reference_variation_id])
    end
    @assert all(lv -> all(!=(-1), size(lv)), pv.latent_variations) "GridVariation do not work with distributions."
    lv_col_iters = [eachcol(variationValues(lv)) for lv in pv.latent_variations] #! each is an iterator over the columns of the #pars x #samples matrix (where #samples is looping over all combinations of latent parameters in the individual latent variation)
    locs = mapreduce(variationLocation, vcat, pv.latent_variations)
    unique_locs = unique(locs)
    targets = mapreduce(variationTarget, vcat, pv.latent_variations)
    types = mapreduce(lv -> lv.types, vcat, pv.latent_variations)
    loc_inds = [loc => findall(==(loc), locs) for loc in unique_locs] |> Dict
    dim_szs = [prod(size(lv)) for lv in pv.latent_variations]
    cart_inds = CartesianIndices(Dims(dim_szs))
    all_vals = stack(vec(cart_inds)) do I #! make this linear so that we get a #target x #samples matrix (rather than a higher dimensional array)
        mapreduce(vcat, zip(I.I, lv_col_iters)) do (i, lv_col_iter)
            lv_col_iter[i]
        end
    end
    loc_dicts = map(unique_locs) do loc
        loc => (all_vals[loc_inds[loc], :], types[loc_inds[loc]], targets[loc_inds[loc]])
    end |> Dict
    return addVariationRows(inputs, reference_variation_id, loc_dicts) |> AddGridVariationsResult
end

################## Latin Hypercube Sampling Functions ##################

"""
    orthogonalLHS(k::Int, d::Int)

Generate an orthogonal Latin Hypercube Sample in `d` dimensions with `k` subdivisions in each dimension, requiring `n=k^d` samples.
"""
function orthogonalLHS(k::Int, d::Int)
    n = k^d
    lhs_inds = zeros(Int, (n, d))
    for i in 1:d
        n_bins = k^(i - 1) #! number of bins from previous dims (a bin has sampled points that are in the same subelement up through i-1 dim and need to be separated in subsequent dims)
        bin_size = k^(d - i + 1) #! number of sampled points in each bin
        if i == 1
            lhs_inds[:, 1] = 1:n
        else
            bin_inds_gps = [(j - 1) * bin_size .+ (1:bin_size) |> collect for j in 1:n_bins] #! the indices belonging to each of the bins (this relies on the sorting step below to easily find which points are currently in the same box and need to be separated along the ith dimension)
            for pt_ind = 1:bin_size #! pick ith coordinate for each point in the bin; each iter here will work up the ith coordinates assigning one to each bin at each iter
                ind = zeros(Int, n_bins) #! indices where the next set of ith coordinates will go
                for (j, bin_inds) in enumerate(bin_inds_gps) #! pick a random, remaining element for each bin
                    rand_ind_of_ind = rand(1:length(bin_inds)) #! pick the index of a remaining index
                    ind[j] = popat!(bin_inds, rand_ind_of_ind) #! get the random index and remove it so we don't pick it again
                end
                lhs_inds[ind, i] = shuffle(1:n_bins) .+ (pt_ind - 1) * n_bins #! for the selected inds, shuffle the next set of ith coords into them
            end
        end
        lhs_inds[:, 1:i] = sortslices(lhs_inds[:, 1:i], dims=1, by=x -> (x ./ (n / k) .|> ceil .|> Int)) #! sort the found values so that sampled points in the same box upon projection into the 1:i dims are adjacent
    end
    return lhs_inds
end

"""
    generateLHSCDFs(n::Int, d::Int[; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true])

Generate a Latin Hypercube Sample of the Cumulative Distribution Functions (CDFs) for `n` samples in `d` dimensions.

# Arguments
- `n::Int`: The number of samples to take.
- `d::Int`: The number of dimensions to sample.
- `add_noise::Bool=false`: Whether to add noise to the samples or have them be in the center of the bins.
- `rng::AbstractRNG=Random.GLOBAL_RNG`: The random number generator to use.
- `orthogonalize::Bool=true`: Whether to orthogonalize the samples, if possible. See https://en.wikipedia.org/wiki/Latin_hypercube_sampling#:~:text=In%20orthogonal%20sampling

# Returns
- `cdfs::Matrix{Float64}`: The CDFs for the samples. Each row is a sample and each column is a dimension (corresponding to a feature).

# Examples
```jldoctest
cdfs = PhysiCellModelManager.generateLHSCDFs(4, 2)
size(cdfs)
# output
(4, 2)
```
"""
function generateLHSCDFs(n::Int, d::Int; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true)
    cdfs = (Float64.(1:n) .- (add_noise ? rand(rng, Float64, n) : 0.5)) / n #! permute below for each parameter separately
    k = n^(1 / d) |> round |> Int
    if orthogonalize && (n == k^d)
        #! then good to do the orthogonalization
        lhs_inds = orthogonalLHS(k, d)
    else
        lhs_inds = reduce(hcat, [shuffle(rng, 1:n) for _ in 1:d]) #! each shuffled index vector is added as a column
    end
    return cdfs[lhs_inds]
end

"""
    AddLHSVariationsResult <: AddVariationsResult

A struct that holds the result of adding LHS variations to a set of inputs.

# Fields
- `cdfs::Matrix{Float64}`: The CDFs for the samples. Each row is a sample and each column is a dimension (corresponding to a latent parameter).
- `variation_ids::Vector{VariationID}`: The variation IDs for all the variations added.
"""
struct AddLHSVariationsResult <: AddVariationsResult
    cdfs::Matrix{Float64}
    variation_ids::Vector{VariationID}
end

function addVariations(lhs_variation::LHSVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_id::VariationID)
    d = nLatentDims(pv)
    cdfs = generateLHSCDFs(lhs_variation.n, d; add_noise=lhs_variation.add_noise, rng=lhs_variation.rng, orthogonalize=lhs_variation.orthogonalize)
    cdfs_reshaped = permutedims(cdfs) #! transpose so that each column is a sample
    variation_ids = addCDFVariations(inputs, pv, reference_variation_id, cdfs_reshaped)
    return AddLHSVariationsResult(cdfs_reshaped, variation_ids)
end

################## Sobol Sequence Sampling Functions ##################

"""
    generateSobolCDFs(n::Int, d::Int[; n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing)

Generate `n_matrices` Sobol sequences of the Cumulative Distribution Functions (CDFs) for `n` samples in `d` dimensions.

The subsequence of the Sobol sequence is chosen based on the value of `n` and the value of `include_one`.
If it is one less than a power of 2, e.g. `n=7`, skip 0 and start from 0.5.
Otherwise, it will always start from 0.
If it is one more than a power of 2, e.g. `n=9`, include 1 (unless `include_one` is `false`).

The `skip_start` field can be used to control this by skipping the start of the sequence.
If `skip_start` is `true`, skip to the smallest consecutive subsequence with the same denominator that has at least `n` elements.
If `skip_start` is `false`, start from 0.
If `skip_start` is an integer, skip that many elements in the sequence, .e.g., `skip_start=1` skips 0 and starts at 0.5.

If you want to include 1 in the sequence, set `include_one` to `true`.
If you want to exlude 1 (in the case of `n=9`, e.g.), set `include_one` to `false`.

# Arguments
- `n::Int`: The number of samples to take.
- `d::Int`: The number of dimensions to sample.
- `n_matrices::Int=1`: The number of matrices to use in the Sobol sequence (effectively, the dimension of the sample is `d` x `n_matrices`).
- `randomization::RandomizationMethod=NoRand()`: The randomization method to use on the deterministic Sobol sequence. See GlobalSensitivity.jl.
- `skip_start::Union{Missing, Bool, Int}=missing`: Whether to skip the start of the sequence. Missing means PhysiCellModelManager.jl will choose the best option.
- `include_one::Union{Missing, Bool}=missing`: Whether to include 1 in the sequence. Missing means PhysiCellModelManager.jl will choose the best option.

# Returns
- `cdfs::Array{Float64, 3}`: The CDFs for the samples. The first dimension is the features, the second dimension is the matrix, and the third dimension is the sample points.

# Examples
```jldoctest
cdfs = PhysiCellModelManager.generateSobolCDFs(11, 3)
size(cdfs)
# output
(3, 1, 11)
```
```jldoctest
cdfs = PhysiCellModelManager.generateSobolCDFs(7, 5; n_matrices=2)
size(cdfs)
# output
(5, 2, 7)
```
"""
function generateSobolCDFs(n::Int, d::Int; n_matrices::Int=1, T::Type=Float64, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing,Bool,Int}=missing, include_one::Union{Missing,Bool}=missing)
    s = Sobol.SobolSeq(d * n_matrices)
    if ismissing(skip_start) #! default to this
        if ispow2(n + 1) #! then n = 2^k - 1
            skip_start = 1 #! skip the first point (0)
        else
            skip_start = false #! don't skip the first point (0)
            if ispow2(n - 1) #! then n = 2^k + 1
                include_one |= ismissing(include_one) #! unless otherwise specified, assume the +1 is to get the boundary 1 included as well
            elseif ispow2(n) #! then n = 2^k
                nothing #! including 0, grab the first 2^k points
            else #! not within 1 of a power of 2, just start at the beginning?
                nothing
            end
        end
    end
    n_draws = n - (include_one === true) #! if include_one is true, then we need to draw n-1 points and then append 1 to the end
    if skip_start == false #! false or 0
        cdfs = randomize(reduce(hcat, [zeros(T, n_matrices * d), [next!(s) for i in 1:n_draws-1]...]), randomization) #! n_draws-1 because the SobolSeq already skips 0
    else
        cdfs = Matrix{T}(undef, d * n_matrices, n_draws)
        num_to_skip = skip_start === true ? ((1 << (floor(Int, log2(n_draws - 1)) + 1))) : skip_start
        num_to_skip -= 1 #! the SobolSeq already skips 0
        for _ in 1:num_to_skip
            Sobol.next!(s)
        end
        for col in eachcol(cdfs)
            Sobol.next!(s, col)
        end
        cdfs = randomize(cdfs, randomization)
    end
    if include_one === true #! cannot compare missing==true, but can make this comparison
        cdfs = hcat(cdfs, ones(T, d * n_matrices))
    end
    return reshape(cdfs, (d, n_matrices, n))
end

generateSobolCDFs(sobol_variation::SobolVariation, d::Int) = generateSobolCDFs(sobol_variation.n, d; n_matrices=sobol_variation.n_matrices, randomization=sobol_variation.randomization, skip_start=sobol_variation.skip_start, include_one=sobol_variation.include_one)

"""
    AddSobolVariationsResult <: AddVariationsResult

A struct that holds the result of adding Sobol variations to a set of inputs.

# Fields
- `cdfs::Array{Float64, 3}`: The CDFs for the samples. The first dimension is the varied parameters, the second dimension is the design matrices, and the third dimension is the samples.
- `variation_ids::AbstractArray{VariationID}`: The variation IDs for all the variations added.
"""
struct AddSobolVariationsResult <: AddVariationsResult
    cdfs::Array{Float64,3}
    variation_ids::AbstractArray{VariationID}
end

function addVariations(sobol_variation::SobolVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_id::VariationID)
    d = nLatentDims(pv)
    cdfs = generateSobolCDFs(sobol_variation, d) #! cdfs is (d, sobol_variation.n_matrices, sobol_variation.n)
    cdfs_reshaped = reshape(cdfs, (d, sobol_variation.n_matrices * sobol_variation.n)) #! reshape to (d, sobol_variation.n_matrices * sobol_variation.n) so that each column is a sobol sample
    variation_ids = addCDFVariations(inputs, pv, reference_variation_id, cdfs_reshaped)
    variation_ids = reshape(variation_ids, (sobol_variation.n_matrices, sobol_variation.n)) |> permutedims
    return AddSobolVariationsResult(cdfs, variation_ids)
end

################## Random Balance Design Sampling Functions ##################

"""
    generateRBDCDFs(rbd_variation::RBDVariation, d::Int)

Generate CDFs for a Random Balance Design (RBD) in `d` dimensions.

# Arguments
- `rbd_variation::RBDVariation`: The RBD variation method to use.
- `d::Int`: The number of dimensions to sample.

# Returns
- `cdfs::Matrix{Float64}`: The CDFs for the samples. Each row is a sample and each column is a dimension (corresponding to a parameter / parameter group from a [`CoVariation`](@ref)).
- `rbd_sorting_inds::Matrix{Int}`: A `n_samples` x `d` matrix that gives the ordering of the dimensions to use for the RBD. The order along each column is necessary for computing the RBD, sorting the simulations along the periodic curve.
"""
function generateRBDCDFs(rbd_variation::RBDVariation, d::Int)
    if rbd_variation.use_sobol
        println("Using Sobol sequence for RBD.")
        if rbd_variation.n == 1
            rbd_sorting_inds = fill(1, (1, d))
            cdfs = 0.5 .+ zeros(Float64, (1, d))
        else
            @assert !ismissing(rbd_variation.pow2_diff) "pow2_diff must be calculated for RBDVariation constructor with Sobol sequence. How else could we get here?"
            @assert rbd_variation.num_cycles == 1 // 2 "num_cycles must be 1//2 for RBDVariation constructor with Sobol sequence. How else could we get here?"
            #! vary along a half period of the sine function since that will cover all CDF values (compare to the full period below). in computing the RBD, we will 
            #!   /    __\      /\  <- \ is the flipped version of the / in this line of commented code
            #!  /       /    \/    <- \ is the flipped version of the / in this line of commented code
            if rbd_variation.pow2_diff == -1
                skip_start = 1
            elseif rbd_variation.pow2_diff == 0
                skip_start = true
            else
                skip_start = false
            end
            cdfs = generateSobolCDFs(rbd_variation.n, d; n_matrices=1, randomization=NoRand(), skip_start=skip_start, include_one=rbd_variation.pow2_diff == 1) #! rbd_sorting_inds here is (d, n_matrices=1, rbd_variation.n)
            cdfs = reshape(cdfs, d, rbd_variation.n) |> permutedims #! cdfs is now (rbd_variation.n, d)
            rbd_sorting_inds = stack(sortperm, eachcol(cdfs))
        end
    else
        @assert rbd_variation.num_cycles == 1 "num_cycles must be 1 for RBDVariation constructor with random sequence. How else could we get here?"
        #! vary along the full period of the sine function and do fft as normal
        #!   /\
        #! \/  
        sorted_s_values = range(-π, stop=π, length=rbd_variation.n + 1) |> collect
        pop!(sorted_s_values)
        permuted_s_values = [sorted_s_values[randperm(rbd_variation.rng, rbd_variation.n)] for _ in 1:d] |> x -> reduce(hcat, x)
        cdfs = 0.5 .+ asin.(sin.(permuted_s_values)) ./ π
        rbd_sorting_inds = stack(sortperm, eachcol(permuted_s_values))
    end
    return cdfs, rbd_sorting_inds
end

function addVariations(rbd_variation::RBDVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_id::VariationID)
    d = nLatentDims(pv)
    cdfs, rbd_sorting_inds = generateRBDCDFs(rbd_variation, d)
    cdfs_reshaped = permutedims(cdfs) #! transpose so that each column is a sample
    variation_ids = addCDFVariations(inputs, pv, reference_variation_id, cdfs_reshaped)
    variation_matrix = createSortedRBDMatrix(variation_ids, rbd_sorting_inds)
    return AddRBDVariationsResult(variation_ids, variation_matrix)
end

"""
    createSortedRBDMatrix(variation_ids::Vector{Int}, rbd_sorting_inds::Matrix{Int})

Create a sorted matrix of variation IDs based on the RBD sorting indices.
This ensures that the orderings for each parameter stored for the RBD calculations.
"""
function createSortedRBDMatrix(variation_ids::Vector{VariationID}, rbd_sorting_inds::Matrix{Int})
    return stack(inds -> variation_ids[inds], eachcol(rbd_sorting_inds))
end

"""
    AddRBDVariationsResult <: AddVariationsResult

A struct that holds the result of adding Sobol variations to a set of inputs.

# Fields
- `variation_ids::AbstractArray{VariationID}`: The variation IDs for all the variations added.
- `variation_matrix::Matrix{VariationID}`: The matrix of variation IDs sorted for RBD calculations.
"""
struct AddRBDVariationsResult <: AddVariationsResult
    variation_ids::AbstractArray{VariationID}
    variation_matrix::Matrix{VariationID}
end

################## Sampling Helper Functions ##################

"""
    addCDFVariations(inputs::InputFolders, pv::ParsedVariations, reference_variation_id::VariationID, cdfs::AbstractMatrix{Float64})

Add variations to the inputs. Used in [`addVariations`](@ref) with the [`LHSVariation`](@ref), [`SobolVariation`](@ref), and [`RBDVariation`](@ref) methods.
"""
function addCDFVariations(inputs::InputFolders, pv::ParsedVariations, reference_variation_id::VariationID, cdfs::AbstractMatrix{Float64})
    #! CDFs come in as ndims x nsamples matrix. If any parameters are co-varying, they correspond to a single row in the CDFs matrix.
    #! This function goes parameter-by-parameter, identifying the column it is associated with and then computing the new values for that parameter.
    all_vals = stack(cdf_col -> variationValues(pv, cdf_col), eachcol(cdfs))

    locs = mapreduce(variationLocation, vcat, pv.latent_variations)
    unique_locs = unique(locs)
    targets = mapreduce(variationTarget, vcat, pv.latent_variations)
    types = mapreduce(lv -> lv.types, vcat, pv.latent_variations)
    loc_inds = [loc => findall(==(loc), locs) for loc in unique_locs] |> Dict

    loc_dicts = map(unique_locs) do loc
        loc => (all_vals[loc_inds[loc], :], types[loc_inds[loc]], targets[loc_inds[loc]])
    end |> Dict
    return addVariationRows(inputs, reference_variation_id, loc_dicts)
end