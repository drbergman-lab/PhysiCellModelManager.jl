#! PhysiCell-specific variation infrastructure.

import ModelManager: DiscreteVariation, DistributedVariation,
                     UniformDistributedVariation, NormalDistributedVariation,
                     ElementaryVariation, LatentVariation

#!
#! Generic types (XMLPath, DiscreteVariation, DistributedVariation, CoVariation,
#! LatentVariation, ParsedVariations, AddVariationMethod subtypes, addVariations, etc.)
#! are now defined in ModelManager.  This file provides:
#!   • inferVariationLocation(xp::XMLPath) — PhysiCell-specific location inference
#!   • Backward-compat constructors (no location arg) for all variation types
#!   • addVariationRows(::PhysiCellSimulator, ...) + its helpers
#!   • Deprecated PhysiCell-specific dimension helpers

export domainVariations

################## inferVariationLocation(::XMLPath) ##################

"""
    inferVariationLocation(xp::XMLPath)

Infer the PhysiCell input-folder location symbol for `xp` based on the first path element.

Returns one of `:rulesets_collection`, `:intracellular`, `:ic_cell`, `:ic_ecm`, or `:config`.

This is a PhysiCell-specific function.  The generic ModelManager infrastructure does NOT
call `inferVariationLocation`; callers are responsible for supplying the location explicitly.
"""
function inferVariationLocation(xp::XMLPath)
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
    return DiscreteVariation(inferVariationLocation(target), target, values)
end
DiscreteVariation(target::XMLPath, value::T) where T = DiscreteVariation(target, Vector{T}([value]))
DiscreteVariation(target::Vector{<:AbstractString}, values) = DiscreteVariation(XMLPath(target), values)

function DistributedVariation(target::XMLPath, distribution::Distribution; flip::Bool=false)
    return DistributedVariation(inferVariationLocation(target), target, distribution; flip=flip)
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
    locations = inferVariationLocation.(targets)
    return LatentVariation(latent_parameters, targets, maps, lp_names, locations)
end
function LatentVariation(latent_parameters::Vector{T}, targets::AbstractVector{<:AbstractVector{<:AbstractString}}, maps::Vector{<:Function}, lp_names::AbstractVector{<:AbstractString}=String[]) where T<:Union{Vector{<:Real},<:Distribution}
    targets_xp = XMLPath.(targets)
    lp_names = isempty(lp_names) ? ModelManager.defaultLatentParameterNames(latent_parameters, targets_xp) : lp_names
    return LatentVariation(latent_parameters, targets_xp, maps, lp_names)
end

################## Variation Dimension Functions ##################

"""
    domainVariations(domain::NamedTuple; covary::Bool=false)::Vector{<:AbstractVariation}
    domainVariations(; covary::Bool=false, kwargs...)::Vector{<:AbstractVariation}

Create a set of `DiscreteVariation`s for the domain boundaries based on the provided named tuple.

The names in `domain` can be flexibly named as long as they contain either `min` or `max` and one of `x`, `y`, or `z` (other than the the `x` in `max`).
It is not required to include all three dimensions and their boundaries.

The values for each boundary can be a single value or a vector of values.
If any boundary has a vector of values, then the `covary` flag determines how the variations are created:
- If `covary=false` (the default), then the variations will be created as a full factorial combination of all the provided values for each boundary.
- If `covary=true`, then the variations will be created by covarying the values for each boundary together (i.e. the first value for each boundary will be combined together, the second value for each boundary will be combined together, etc.). In this case, all boundaries with more than one value must have the same number of values.

# Examples:
```julia
domainVariations((x_min=-78, xmax=78, min_y=-30, maxy=[30, 60], z_max=10))
```
Equivalently:
```julia
domainVariations(x_min=-78, xmax=78, min_y=-30, maxy=[30, 60], z_max=10)
```

The following produces four different domain sizes:
```julia
domainVariations((x_min=[-78, -70], xmax=[78, 70], min_y=-30, maxy=30, z_max=10))
```
while this produces two domain sizes by covarying the x boundaries together and keeping the y and z boundaries fixed:
```julia
domainVariations((x_min=[-78, -70], xmax=[78, 70], min_y=-30, maxy=30, z_max=10); covary=true)
```
"""
function domainVariations(domain::NamedTuple; covary::Bool=false)::Vector{<:AbstractVariation}
    dim_chars = ["z", "y", "x"] #! put x at the end to avoid prematurely matching with "max"
    evs = DiscreteVariation[]
    cv_length = 0 #! store the length of the vectors if covary=true
    if covary
        all_variable_value_lengths = [length(value) for value in values(domain) if length(value) > 1]
        cv_length = first(all_variable_value_lengths)
        @assert all(==(cv_length), all_variable_value_lengths) "All boundaries with multiple values must have the same number of values when covary=true"
    end

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
        push!(evs, DiscreteVariation(xml_path, covary && length(value) == 1 ? fill(value, cv_length) : value))
    end

    if covary
        return [CoVariation(evs)]
    else
        return evs
    end
end

function domainVariations(; covary::Bool=false, kwargs...)
    return domainVariations(NamedTuple{keys(kwargs)}(values(kwargs)); covary=covary)
end

