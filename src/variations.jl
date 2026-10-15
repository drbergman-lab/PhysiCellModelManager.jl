#! PhysiCell-specific variation infrastructure.

#!
#! Generic types (XMLPath, DiscreteVariation, DistributedVariation, CoVariation,
#! LatentVariation, ParsedVariations, AddVariationMethod subtypes, addVariations, etc.)
#! and every constructor form -- explicit location, location-free, simulator-first --
#! are defined in ModelManager.  This file provides:
#!   • inferVariationLocation(::PhysiCellSimulator, ::XMLPath) — the backend hook the
#!     location-free constructors resolve through
#!   • addVariationRows(::PhysiCellSimulator, ...) + its helpers
#!   • Deprecated PhysiCell-specific dimension helpers

export domainVariations

################## inferVariationLocation ##################

#! Map an XMLPath to the input-folder location that owns it, by its first path element.
#! ModelManager's location-free constructors (`DiscreteVariation(target, values)`, the tuple forms
#! of `CoVariation`, `LatentVariation` without `locations`, ...) call this through the registered
#! simulator; `getParameterValue(M, xp)` calls it directly.
function ModelManager.inferVariationLocation(::PhysiCellSimulator, xp::XMLPath)
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

