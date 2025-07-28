using PhysiCellXMLRules, PhysiCellCellCreator, PhysiCellECMCreator, LightXML

export configPath, rulePath, icCellsPath, icECMPath

@compat public domainPath, timePath, fullSavePath, svgSavePath, substratePath,
               cellDefinitionPath, phenotypePath, cyclePath,
               apoptosisPath, necrosisPath, volumePath, mechanicsPath,
               motilityPath, secretionPath, cellInteractionsPath,
               phagocytosisPath, attackRatePath, fusionPath,
               transformationPath, integrityPath, customDataPath,
               initialParameterDistributionPath, userParameterPath

################## XML Functions ##################

"""
    getChildByAttribute(parent_element::XMLElement, path_element_split::Vector{<:AbstractString})

Get the child element of `parent_element` that matches the given tag and attribute.
"""
function getChildByAttribute(parent_element::XMLElement, path_element_split::Vector{<:AbstractString})
    path_element_name, attribute_name, attribute_value = path_element_split
    candidate_elements = get_elements_by_tagname(parent_element, path_element_name)
    for ce in candidate_elements
        if attribute(ce, attribute_name) == attribute_value
            return ce
        end
    end
    return nothing
end

"""
    getChildByChildContent(current_element::XMLElement, path_element::AbstractString)

Get the child element of `current_element` that matches the given tag and child content.
"""
function getChildByChildContent(current_element::XMLElement, path_element::AbstractString)
    tag, child_scheme = split(path_element, "::")
    tokens = split(child_scheme, ":")
    @assert length(tokens) == 2 "Invalid child scheme for $(path_element). Expected format: <tag>::<child_tag>:<child_content>"
    child_tag, child_content = tokens
    candidate_elements = get_elements_by_tagname(current_element, tag)
    for ce in candidate_elements
        child_element = find_element(ce, child_tag)
        if !isnothing(child_element) && content(child_element) == child_content
            return ce, true
        end
    end
    return current_element, false
end

"""
    retrieveElement(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)

Retrieve the element in the XML document that matches the given path.

If `required` is `true`, an error is thrown if the element is not found.
Otherwise, `nothing` is returned if the element is not found.
"""
function retrieveElement(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)
    current_element = root(xml_doc)
    for path_element in xml_path
        if contains(path_element, "::")
            current_element, success = getChildByChildContent(current_element, path_element)
            if !success
                current_element = nothing
            end
        else
            current_element = contains(path_element, ":") ?
                getChildByAttribute(current_element, split(path_element, ":"; limit=3)) :
                find_element(current_element, path_element)
        end

        if isnothing(current_element)
            required ? retrieveElementError(xml_path, path_element) : return nothing
        end
    end
    return current_element
end

"""
    retrieveElementError(xml_path::Vector{<:AbstractString}, path_element::String)

Throw an error if the element defined by `xml_path` is not found in the XML document, including the path element that caused the error.
"""
function retrieveElementError(xml_path::Vector{<:AbstractString}, path_element::String)
    error_msg = "Element not found: $(join(xml_path, " -> "))"
    error_msg *= "\n\tFailed at: $(path_element)"
    throw(ArgumentError(error_msg))
end

"""
    getContent(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)

Get the content of the element in the XML document that matches the given path. See [`retrieveElement`](@ref).
"""
function getContent(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)
    return retrieveElement(xml_doc, xml_path; required=required) |> content
end

"""
    updateField(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}, new_value::Union{Int,Real,String})

Update the content of the element in the XML document that matches the given path with the new value. See [`retrieveElement`](@ref).
"""
function updateField(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}, new_value::Union{Int,Real,String})
    current_element = retrieveElement(xml_doc, xml_path; required=true)
    set_content(current_element, string(new_value))
    return nothing
end

"""
    columnName(xml_path)

Return the column name corresponding to the given XML path.

Works on a vector of strings, an [`XMLPath`](@ref) object, or a [`ElementaryVariation`](@ref) object.
Inverse of [`columnNameToXMLPath`](@ref).
"""
columnName(xml_path::Vector{<:AbstractString}) = join(xml_path, "/")

"""
    columnNameToXMLPath(column_name::String)

Return the XML path corresponding to the given column name.

Inverse of [`columnName`](@ref).
"""
columnNameToXMLPath(column_name::String) = split(column_name, "/")

"""
    makeXMLPath(current_element::XMLElement, xml_path::AbstractVector{<:AbstractString})

Create (if it does not exist) and return the XML element relative to the given XML element.

Similar functionality to the shell command `mkdir -p`, but for XML elements.

# Arguments
- `current_element::XMLElement`: The current XML element to start from.
- `xml_path::AbstractVector{<:AbstractString}`: The path to the XML element to create or retrieve. Can be a string representing a child of the current element.
"""
function makeXMLPath(current_element::XMLElement, xml_path::AbstractVector{<:AbstractString})
    for path_element in xml_path
        if contains(path_element, "::")
            current_element, success = getChildByChildContent(current_element, path_element)
            if !success
                current_element = new_child(current_element, tag)
                child_element = new_child(current_element, child_tag)
                set_content(child_element, child_content)
            end
        elseif !contains(path_element, ":")
            child_element = find_element(current_element, path_element)
            if isnothing(child_element)
                current_element = new_child(current_element, path_element)
            else
                current_element = child_element
            end
        else
            #! Deal with checking attributes
            path_element_split = split(path_element, ":"; limit=3)
            child_element = getChildByAttribute(current_element, path_element_split)
            if isnothing(child_element)
                path_element_name, attribute_name, attribute_value = path_element_split
                child_element = new_child(current_element, path_element_name)
                set_attribute(child_element, attribute_name, attribute_value)
            end
            current_element = child_element
        end
    end
    return current_element
end

"""
    makeXMLPath(xml_doc::XMLDocument, xml_path::AbstractVector{<:AbstractString})

Create (if it does not exist) and return the XML element relative to the root of the given XML document.

# Arguments
- `xml_doc::XMLDocument`: The XML document to start from.
- `xml_path::AbstractVector{<:AbstractString}`: The path to the XML element to create or retrieve. Can be a string representing a child of the root element.
"""
function makeXMLPath(xml_doc::XMLDocument, xml_path::AbstractVector{<:AbstractString})
    current_element = root(xml_doc)
    return makeXMLPath(current_element, xml_path)
end

makeXMLPath(x, xml_path::AbstractString) = makeXMLPath(x, [xml_path])

################## Configuration Functions ##################

"""
    createXMLFile(location::Symbol, M::AbstractMonad)

Create XML file for the given location and variation_id in the given monad.

The file is placed in `\$(location)_variations` and can be accessed from there to run the simulation(s).
"""
function createXMLFile(location::Symbol, M::AbstractMonad)
    path_to_folder = locationPath(location, M)
    path_to_xml = joinpath(path_to_folder, variationsTableName(location), "$(location)_variation_$(M.variation_id[location]).xml")
    if isfile(path_to_xml)
        return path_to_xml
    end
    mkpath(dirname(path_to_xml))

    path_to_base_xml = prepareBaseFile(M.inputs[location])
    @assert endswith(path_to_base_xml, ".xml") "Base XML file for $(location) must end with .xml. Got $(path_to_base_xml)"
    @assert isfile(path_to_base_xml) "Base XML file not found: $(path_to_base_xml)"

    xml_doc = parse_file(path_to_base_xml)
    if M.variation_id[location] != 0 #! only update if not using the base variation for the location
        query = constructSelectQuery(variationsTableName(location), "WHERE $(locationVariationIDName(location))=$(M.variation_id[location])")
        variation_row = queryToDataFrame(query; db=variationsDatabase(location, M), is_row=true)
        for column_name in names(variation_row)
            if column_name == locationVariationIDName(location)
                continue
            end
            xml_path = columnNameToXMLPath(column_name)
            updateField(xml_doc, xml_path, variation_row[1, column_name])
        end
    end
    save_file(xml_doc, path_to_xml)
    free(xml_doc)
    return
end

"""
    prepareBaseFile(input_folder::InputFolder)

Return the path to the base XML file for the given input folder.
"""
function prepareBaseFile(input_folder::InputFolder)
    if input_folder.location == :rulesets_collection
        return prepareBaseRulesetsCollectionFile(input_folder)
    end
    return joinpath(locationPath(input_folder), input_folder.basename)
end

"""
    prepareBaseRulesetsCollectionFile(input_folder::InputFolder)

Return the path to the base XML file for the given input folder.
"""
function prepareBaseRulesetsCollectionFile(input_folder::InputFolder)
    path_to_rulesets_collection_folder = locationPath(:rulesets_collection, input_folder.folder)
    path_to_base_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
    if !isfile(path_to_base_xml)
        #! this could happen if the rules are not being varied (so no call to addRulesetsVariationsColumns) and then a sim runs without the base_rulesets.xml being created yet
        writeXMLRules(path_to_base_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
    end
    return path_to_base_xml
end

"""
    prepareVariedInputFolder(location::Symbol, M::AbstractMonad)

Create the XML file for the location in the monad.
"""
function prepareVariedInputFolder(location::Symbol, M::AbstractMonad)
    if !M.inputs[location].varied #! this input is not being varied (either unused or static)
        return
    end
    createXMLFile(location, M)
end

"""
    prepareVariedInputFolder(location::Symbol, sampling::Sampling)

Create the XML file for each monad in the sampling for the given location.
"""
function prepareVariedInputFolder(location::Symbol, sampling::Sampling)
    if !sampling.inputs[location].varied #! this input is not being varied (either unused or static)
        return
    end
    for monad in Monad.(readConstituentIDs(sampling))
        prepareVariedInputFolder(location, monad)
    end
end

"""
    pathToICCell(simulation::Simulation)

Return the path to the IC cell file for the given simulation, creating it if it needs to be generated from an XML file.
"""
function pathToICCell(simulation::Simulation)
    @assert simulation.inputs[:ic_cell].id != -1 "No IC cell variation being used" #! we should have already checked this before calling this function
    path_to_ic_cell_folder = locationPath(:ic_cell, simulation)
    if isfile(joinpath(path_to_ic_cell_folder, "cells.csv")) #! ic already given by cells.csv
        return joinpath(path_to_ic_cell_folder, "cells.csv")
    end
    path_to_config_xml = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(simulation.variation_id[:config]).xml")
    xml_doc = parse_file(path_to_config_xml)
    domain_dict = Dict{String,Float64}()
    for d in ["x", "y", "z"]
        for side in ["min", "max"]
            key = "$(d)_$(side)"
            xml_path = ["domain"; key]
            domain_dict[key] = getContent(xml_doc, xml_path) |> x -> parse(Float64, x)
        end
    end
    free(xml_doc)
    path_to_ic_cell_variations = joinpath(path_to_ic_cell_folder, "ic_cell_variations")
    path_to_ic_cell_xml = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_id[:ic_cell]).xml")
    path_to_ic_cell_file = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_id[:ic_cell])_s$(simulation.id).csv")
    generateICCell(path_to_ic_cell_xml, path_to_ic_cell_file, domain_dict)
    return path_to_ic_cell_file
end

"""
    pathToICECM(simulation::Simulation)

Return the path to the IC ECM file for the given simulation, creating it if it needs to be generated from an XML file.
"""
function pathToICECM(simulation::Simulation)
    @assert simulation.inputs[:ic_ecm].id != -1 "No IC ecm variation being used" #! we should have already checked this before calling this function
    path_to_ic_ecm_folder = locationPath(:ic_ecm, simulation)
    if isfile(joinpath(path_to_ic_ecm_folder, "ecm.csv")) #! ic already given by ecm.csv
        return joinpath(path_to_ic_ecm_folder, "ecm.csv")
    end
    path_to_config_xml = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(simulation.variation_id[:config]).xml")
    xml_doc = parse_file(path_to_config_xml)
    config_dict = Dict{String,Float64}()
    for d in ["x", "y"] #! does not (yet?) support 3D
        for side in ["min", "max"]
            key = "$(d)_$(side)"
            xml_path = ["domain"; key]
            config_dict[key] = getContent(xml_doc, xml_path) |> x -> parse(Float64, x)
        end
        key = "d$(d)" #! d$(d) looks funny but it's just dx and dy
        xml_path = ["domain"; key]
        config_dict[key] = getContent(xml_doc, xml_path) |> x -> parse(Float64, x)
    end
    free(xml_doc)
    path_to_ic_ecm_variations = joinpath(path_to_ic_ecm_folder, "ic_ecm_variations")
    path_to_ic_ecm_xml = joinpath(path_to_ic_ecm_variations, "ic_ecm_variation_$(simulation.variation_id[:ic_ecm]).xml")
    path_to_ic_ecm_file = joinpath(path_to_ic_ecm_variations, "ic_ecm_variation_$(simulation.variation_id[:ic_ecm])_s$(simulation.id).csv")
    generateICECM(path_to_ic_ecm_xml, path_to_ic_ecm_file, config_dict)
    return path_to_ic_ecm_file
end

################## XML Path Helper Functions ##################

"""
    configPath(tokens::Vararg{Union{AbstractString,Integer}})

Return the XML path to the configuration for the given tokens, inferring the path based on the tokens.

This function works by calling the explicit path functions for the given tokens:
[`domainPath`](@ref), [`timePath`](@ref), [`fullSavePath`](@ref), [`svgSavePath`](@ref), [`substratePath`](@ref), [`cyclePath`](@ref), [`apoptosisPath`](@ref), [`necrosisPath`](@ref), [`volumePath`](@ref), [`mechanicsPath`](@ref), [`motilityPath`](@ref), [`secretionPath`](@ref), [`cellInteractionsPath`](@ref), [`phagocytosisPath`](@ref), [`attackRatePath`](@ref), [`fusionPath`](@ref), [`transformationPath`](@ref), [`integrityPath`](@ref), [`customDataPath`](@ref), [`initialParameterDistributionPath`](@ref), and [`userParameterPath`](@ref).

This is an experimental feature that can perhaps standardize ways to access the configuration XML path with (hopefully) minimal referencing of the XML file.
Take a guess at what you think the inputs should be.
Depending on the number of tokens passed in, the function will try to infer the path or throw an error if it cannot.
The error message will include the possible tokens that can be used for the given number of tokens as well as the more explicit function that has specific documentation.
"""
function configPath(tokens::Vararg{Union{AbstractString,Integer}})
    @assert length(tokens) > 0 "At least one token is required"
    if length(tokens) == 1
        token = tokens[1]
        if token ∈ ["x_min", "x_max", "y_min", "y_max", "z_min", "z_max", "dx", "dy", "dz", "use_2D"]
            return domainPath(token)
        elseif token ∈ ["max_time", "dt_intracellular", "dt_diffusion", "dt_mechanics", "dt_phenotype"]
            return timePath(token)
        elseif contains(token, "full") && contains(token, "data")
            return fullSavePath()
        elseif contains(lowercase(token), "svg") && contains(token, "save")
            return svgSavePath()
        else
            msg = """
            Unrecognized singular token for configPath: $(token)
            Possible singular tokens include:
            - "x_min", "x_max", "y_min", "y_max", "z_min", "z_max", "dx", "dy", "dz", "use_2D" (see `domainPath`)
            - "max_time", "dt_intracellular", "dt_diffusion", "dt_mechanics", "dt_phenotype" (see `timePath`)
            - "full_data_interval" (see `fullSavePath`)
            - "SVG_save_interval" (see `svgSavePath`)

            If this is a user parameter, use two tokens instead:
              configPath("user_parameter", $(token)) # see `userParameterPath`
            """
            throw(ArgumentError(msg))
        end
    elseif length(tokens) == 2
        token1, token2 = tokens
        if token2 ∈ ["diffusion_coefficient", "decay_rate"]
            return substratePath(token1, "physical_parameter_set", token2)
        elseif token2 ∈ ["initial_condition", "Dirichlet_boundary_condition"]
            return substratePath(token1, token2)
        elseif token2 ∈ ["xmin", "xmax", "ymin", "ymax", "zmin", "zmax"]
            return substratePath(token1, "Dirichlet_options", "boundary_value:ID:$(token2)")
        elseif token2 ∈ ["total", "fluid_fraction", "nuclear", "fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcified_fraction", "calcification_rate", "relative_rupture_volume"]
            return volumePath(token1, token2)
        elseif token2 ∈ ["cell_cell_adhesion_strength", "cell_cell_repulsion_strength", "relative_maximum_adhesion_distance", "attachment_elastic_constant", "attachment_rate", "detachment_rate", "maximum_number_of_attachments"]
            return mechanicsPath(token1, token2)
        elseif token2 ∈ ["set_relative_equilibrium_distance", "set_absolute_equilibrium_distance"]
            return mechanicsPath(token1, "options", token2)
        elseif token2 ∈ ["speed", "persistence_time", "migration_bias"]
            return motilityPath(token1, token2)
        elseif token2 ∈ ["apoptotic_phagocytosis_rate", "necrotic_phagocytosis_rate", "other_dead_phagocytosis_rate", "attack_damage_rate", "attack_duration"]
            return cellInteractionsPath(token1, token2)
        elseif token2 ∈ ["damage_rate", "damage_repair_rate"]
            return integrityPath(token1, token2)
        elseif startswith(token2, "custom")
            new_token2 = token2[8:end] |> lstrip #! remove "custom:", "custom ", or "custom: " from the token
            return customDataPath(token1, new_token2)
        elseif token1 ∈ ["user_parameter", "user_parameters"]
            return userParameterPath(token2)
        else
            msg = """
            Unrecognized tokens for configPath: $(tokens)
            Possible second tokens include:
            - "diffusion_coefficient", "decay_rate" (see `substratePath`)
            - "initial_condition", "Dirichlet_boundary_condition" (see `substratePath`)
            - "xmin", "xmax", "ymin", "ymax", "zmin", "zmax" (see `substratePath`)
            - "total", "fluid_fraction", "nuclear", "fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcified_fraction", "calcification_rate", "relative_rupture_volume" (see `volumePath`)
            - "cell_cell_adhesion_strength", "cell_cell_repulsion_strength", "relative_maximum_adhesion_distance", "attachment_elastic_constant", "attachment_rate", "detachment_rate", "maximum_number_of_attachments" (see `mechanicsPath`)
            - "set_relative_equilibrium_distance", "set_absolute_equilibrium_distance" (see `mechanicsPath`)
            - "speed", "persistence_time", "migration_bias" (see `motilityPath`)
            - "apoptotic_phagocytosis_rate", "necrotic_phagocytosis_rate", "other_dead_phagocytosis_rate", "attack_damage_rate", "attack_duration" (see `cellInteractionsPath`)
            - "damage_rate", "damage_repair_rate" (see `integrityPath`)
            - "custom:<tag>" (see `customDataPath`)

            Alternatively, if this is a user parameter, make sure it is of the form:
              configPath("user_parameter", <parameter>)
            """
            throw(ArgumentError(msg))
        end
    elseif length(tokens) == 3
        token1, token2, token3 = tokens
        if token2 == "Dirichlet_options"
            return substratePath(token1, token2, "boundary_value:ID:$(token3)")
        elseif contains(token2, "cycle") && contains(token2, "rate") && (token3 isa Integer || all(c -> isdigit(c), token3))
            return cyclePath(token1, "phase_transition_rates", "rate:start_index:$(token3)")
        elseif contains(token2, "cycle") && contains(token2, "duration") && (token3 isa Integer || all(c -> isdigit(c), token3))
            return cyclePath(token1, "phase_durations", "duration:index:$(token3)")
        elseif token2 == "apoptosis"
            return inferDeathModelPath(:apoptosis, token1, token3)
        elseif token2 == "necrosis"
            return inferDeathModelPath(:necrosis, token1, token3)
        elseif token2 ∈ ["adhesion", "adhesion_affinity", "adhesion_affinities", "cell_adhesion", "cell_adhesion_affinity", "cell_adhesion_affinities"]
            return mechanicsPath(token1, "cell_adhesion_affinities", "cell_adhesion_affinity:name:$(token3)")
        elseif token2 == "motility"
            return motilityPath(token1, "options", token3)
        elseif token2 == "chemotaxis"
            return motilityPath(token1, "options", "chemotaxis", token3)
        elseif contains(token2, "chemotaxis") && contains(token2, "advanced")
            if token3 ∈ ["enabled", "normalize_each_gradient"]
                return motilityPath(token1, "options", "advanced_chemotaxis", token3)
            else
                return motilityPath(token1, "options", "advanced_chemotaxis", "chemotactic_sensitivities", "chemotactic_sensitivity:substrate:$(token3)")
            end
        elseif token3 ∈ ["secretion_rate", "secretion_target", "uptake_rate", "net_export_rate"]
            return secretionPath(token1, token2, token3)
        elseif token2 ∈ ["phagocytosis", "phagocytose"]
            if token3 ∈ ["apoptotic", "necrotic", "other_dead"]
                return phagocytosisPath(token1, Symbol(token3))
            else
                return phagocytosisPath(token1, token3)
            end
        elseif token2 ∈ ["fusion", "fuse to"]
            return fusionPath(token1, token3)
        elseif token2 ∈ ["transformation", "transform to"]
            return transformationPath(token1, token3)
        elseif token2 ∈ ["attack", "attack_rate"]
            return attackRatePath(token1, token3)
        elseif token2 == "custom"
            return customDataPath(token1, token3)
        else
            msg = """
            Unrecognized triple of tokens for configPath: $(tokens)
            Possible triple tokens include:
            - `configPath(<substrate_name>, "Dirichlet_options", <boundary_id>)` (see `substratePath`)
            - `configPath(<cell_type>, "cycle_rate", <start_index>)` (see `cyclePath`)
            - `configPath(<cell_type>, "cycle_duration", <index>)` (see `cyclePath`)
            - `configPath(<cell_type>, "apoptosis", <parameter>)` (see `apoptosisPath`)
            - `configPath(<cell_type>, "necrosis", <parameter>)` (see `necrosisPath`)
            - `configPath(<cell_type>, "adhesion", <cell_type>)` (see `mechanicsPath`)
            - `configPath(<cell_type>, "motility", <parameter>)` (see `motilityPath`)
            - `configPath(<cell_type>, "chemotaxis", <parameter>)` (see `motilityPath`)
            - `configPath(<cell_type>, "advanced_chemotaxis", <parameter>)` (see `motilityPath`)
            - `configPath(<cell_type>, "advanced_chemotaxis", <substrate_name>)` (see `motilityPath`)
            - `configPath(<cell_type>, <substrate_name>, <parameter>)` (see `secretionPath`)
            - `configPath(<cell_type>, <interaction>, <cell_type>)` (`<interaction>` is one of "phagocytosis", "fusion", "transformation", "attack_rate") (see `cellInteractionsPath`)
            - `configPath(<cell_type>, "custom", <tag>)` (see `customDataPath`)
            """
            throw(ArgumentError(msg))
        end
    elseif length(tokens) == 4
        token1, token2, token3, token4 = tokens
        recognized_duration_tokens = ["duration"]
        recognized_rate_tokens = ["rate", "transition_rate", "phase_transition_rate"]
        if token2 == "cycle" && (token3 ∈ recognized_duration_tokens || token3 ∈ recognized_rate_tokens)
            if token3 ∈ recognized_duration_tokens
                return cyclePath(token1, "phase_durations", "duration:index:$(token4)")
            else
                return cyclePath(token1, "phase_transition_rates", "rate:start_index:$(token4)")
            end
        elseif token2 == "necrosis"
            @assert token3 ∈ ["duration", "transition_rate"] "Unrecognized third token for necrosis with four tokens passed in to configPath: $(token3). Needs to be either \"duration\" or \"transition_rate\""
            return inferDeathModelPath(:necrosis, token1, "$(token3)_$(token4)")
        elseif contains(token2, "initial") && contains(token2, "parameter") && contains(token2, "distribution")
            return initialParameterDistributionPath(token1, token3, token4)
        else
            msg = """
            Unrecognized four tokens for configPath: $(tokens)
            Possible four tokens include:
            - `configPath(<cell_type>, "cycle", "duration", <index>)` (see `cyclePath`)
            - `configPath(<cell_type>, "cycle", "rate", <start_index>)` (see `cyclePath`)
            - `configPath(<cell_type>, "necrosis", "duration", <index>)` (see `necrosisPath`)
            - `configPath(<cell_type>, "necrosis", "transition_rate", <start_index>)` (see `necrosisPath`)
            - `configPath(<cell_type>, "initial_parameter_distribution", <behavior>, <parameter>)` (see `initialParameterDistributionPath`)
            """
            throw(ArgumentError(msg))
        end
    else
        throw(ArgumentError("configPath only supports 1, 2, 3, or 4 tokens. Got $(length(tokens)) tokens."))
    end
end

"""
    inferDeathModelPath(death_model::Symbol, token1::AbstractString, token3::AbstractString)

Helper function to infer the death model path based on the death model and the third token passed in to [`configPath`](@ref).
"""
function inferDeathModelPath(death_model::Symbol, token1::AbstractString, token3::AbstractString)
    path_fn = death_model == :apoptosis ? apoptosisPath : necrosisPath
    if token3 ∈ ["unlysed_fluid_change_rate", "lysed_fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcification_rate", "relative_rupture_volume"]
        return path_fn(token1, "parameters", token3)
    elseif token3 == "rate" || (contains(token3, "death") && contains(token3, "rate"))
        return path_fn(token1, "death_rate")
    elseif token3 ∈ ["duration", "duration_0"]
        return path_fn(token1, "phase_durations", "duration:index:0")
    elseif token3 == "duration_1"
        return path_fn(token1, "phase_durations", "duration:index:1")
    elseif token3 ∈ ["transition_rate", "transition_rate_0"]
        return path_fn(token1, "phase_transition_rates", "rate:start_index:0")
    elseif token3 == "transition_rate_1"
        return path_fn(token1, "phase_transition_rates", "rate:start_index:1")
    else
        msg = """
        Unrecognized third token for configPath when second token is "$(death_model)": $(token3)
        Possible third tokens include:
        - "unlysed_fluid_change_rate", "lysed_fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcification_rate", "relative_rupture_volume"
        - "death_rate"
        """
        if death_model == :apoptosis
            msg *= """
            - "duration", "transition_rate"
            """
        else
            msg *= """
            - "duration_0", "transition_rate_0", "duration_1", "transition_rate_1"
            """
        end
        throw(ArgumentError(msg))
    end
end

"""
    domainPath(tag::AbstractString)

Return the XML path to the domain for the given tag.

Possible `tag`s include:
- `"x_min"`
- `"x_max"`
- `"y_min"`
- `"y_max"`
- `"z_min"`
- `"z_max"`
- `"dx"`
- `"dy"`
- `"dz"`
- `"use_2D"` (value is `"true"`or `"false"`)
"""
domainPath(tag::AbstractString) = ["domain"; tag]

"""
    timePath(tag::AbstractString)

Return the XML path to the time for the given tag.

Possible `tag`s include:
- `"max_time"`
- `"dt_intracellular"`
- `"dt_diffusion"`
- `"dt_mechanics"`
- `"dt_phenotype"`
"""
timePath(tag::AbstractString) = ["overall"; tag]

"""
    fullSavePath()

Return the XML path to the interval for full data saves.
"""
fullSavePath() = ["save"; "full_data"; "interval"]

"""
    svgSavePath()

Return the XML path to the interval for SVG data saves.
"""
svgSavePath() = ["save"; "SVG"; "interval"]

"""
    substratePath(substrate_name::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the substrate for the given name (or deeper if more path elements are given).

Possible `path_elements` include:
- `substratePath(<substrate_name>, "physical_parameter_set", <tag>)` with `<tag>` one of
  - `"diffusion_coefficient"`
  - `"decay_rate"`
- `substratePath(<substrate_name>, <tag>)` with `<tag>` one of
  - `"initial_condition"`
  - `"Dirichlet_boundary_condition"`
- `substratePath(<substrate_name>, "Dirichlet_options", "boundary_value:ID:<boundary_id>")` where `<boundary_id>` is one of
  - `"xmin"`
  - `"xmax"`
  - `"ymin"`
  - `"ymax"`
  - `"zmin"`
  - `"zmax"`
"""
substratePath(substrate_name::AbstractString, path_elements::Vararg{AbstractString}) = ["microenvironment_setup"; "variable:name:$(substrate_name)"; path_elements...]

"""
    cellDefinitionPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the cell definition or deeper if more path elements are given.
"""
function cellDefinitionPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})
    return ["cell_definitions"; "cell_definition:name:$(cell_definition)"; path_elements...]
end

"""
    phenotypePath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the phenotype for the given cell type (or deeper if more path elements are given).
"""
function phenotypePath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})
    return cellDefinitionPath(cell_definition, "phenotype", path_elements...)
end

"""
    cyclePath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the cycle for the given cell type (or deeper if more path elements are given).

Possible `path_elements` include:
- `cyclePath(<cell_type>, "phase_durations", "duration:index:0")` # replace 0 with the index of the phase
- `cyclePath(<cell_type>, "phase_transition_rates", "rate:start_index:0")` # replace 0 with the start index of the phase
"""
cyclePath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = phenotypePath(cell_definition, "cycle", path_elements...)

"""
    deathPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the death for the given cell type (or deeper if more path elements are given).
Users are encouraged to use the [`apoptosisPath`](@ref) or [`necrosisPath`](@ref) functions.
"""
deathPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = phenotypePath(cell_definition, "death", path_elements...)

"""
    apoptosisPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the apoptosis for the given cell type (or deeper if more path elements are given).

Possible `path_elements` include:
- `apoptosisPath(<cell_type>, "death_rate")`
- `apoptosisPath(<cell_type>, "phase_durations", "duration:index:0")` # apoptosis only has one phase, so index is always 0
- `apoptosisPath(<cell_type>, "phase_transition_rates", "rate:start_index:0")` # apoptosis only has one phase, so start index is always 0
- `apoptosisPath(<cell_type>, "parameters", <tag>)` with `<tag>` one of
  - `unlysed_fluid_change_rate`
  - `lysed_fluid_change_rate`
  - `cytoplasmic_biomass_change_rate`
  - `nuclear_biomass_change_rate`
  - `calcification_rate`
  - `relative_rupture_volume`
"""
apoptosisPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = deathPath(cell_definition, "model:code:100", path_elements...)

"""
    necrosisPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the necrosis for the given cell type (or deeper if more path elements are given).

Possible `path_elements` are identical to those for [`apoptosisPath`](@ref) with one exception: Necrosis has two phases so the phase index can be either 0 or 1.
They include:
- `necrosisPath(<cell_type>, "death_rate")`
- `necrosisPath(<cell_type>, "phase_durations", "duration:index:0")` # necrosis has two phases, so index is either 0 or 1
- `necrosisPath(<cell_type>, "phase_transition_rates", "rate:start_index:0")` # necrosis has two phases, so start index is either 0 or 1
- `necrosisPath(<cell_type>, "parameters", <tag>)` with `<tag>` one of
  - `unlysed_fluid_change_rate`
  - `lysed_fluid_change_rate`
  - `cytoplasmic_biomass_change_rate`
  - `nuclear_biomass_change_rate`
  - `calcification_rate`
  - `relative_rupture_volume`
"""
necrosisPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = deathPath(cell_definition, "model:code:101", path_elements...)

"""
    volumePath(cell_definition::AbstractString, tag::AbstractString)

Return the XML path to the volume for the given cell type (or deeper if more path elements are given).

Possible `tag`s include:
- `"total"`
- `"fluid_fraction"`
- `"nuclear"`
- `"fluid_change_rate"`
- `"cytoplasmic_biomass_change_rate"`
- `"nuclear_biomass_change_rate"`
- `"calcified_fraction"`
- `"calcification_rate"`
- `"relative_rupture_volume"`
"""
volumePath(cell_definition::AbstractString, tag::AbstractString) = phenotypePath(cell_definition, "volume", tag)

"""
    mechanicsPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the mechanics for the given cell type (or deeper if more path elements are given).

Possible `path_elements` include:
- `mechanicsPath(<cell_type>, <tag>)` with `<tag>` one of
  - `"cell_cell_adhesion_strength"`
  - `"cell_cell_repulsion_strength"`
  - `"relative_maximum_adhesion_distance"`
  - `"attachment_elastic_constant"`
  - `"attachment_rate"`
  - `"detachment_rate"`
  - `"maximum_number_of_attachments"`
- `mechanicsPath(<cell_type>, "cell_adhesion_affinities", "cell_adhesion_affinity:name:<cell_type>")`
  - `<cell_type>` is a string of the model cell type
- `mechanicsPath(<cell_type>, "options", <tag>)` with `<tag>` one of
  - `"set_relative_equilibrium_distance"`
  - `"set_absolute_equilibrium_distance"`
"""
mechanicsPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = phenotypePath(cell_definition, "mechanics", path_elements...)

"""
    motilityPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the motility for the given cell type (or deeper if more path elements are given).

Possible `path_elements` include:
- `motilityPath(<cell_type>, <tag>)` with `<tag>` one of
  - `"speed"`
  - `"persistence_time"`
  - `"migration_bias"`
- `motilityPath(<cell_type>, "options", <tag>)` with `<tag>` one of
  - `"enabled"` (value is `"true"`or `"false"`)
  - `"use_2D"` (value is `"true"`or `"false"`)
- `motilityPath(<cell_type>, "options", "chemotaxis", <tag>)` with `<tag>` one of
  - `"enabled"` (value is `"true"`or `"false"`)
  - `"substrate"` (value is string of the model substrate)
  - `"direction"` (value is -1 or 1)
- `motilityPath(<cell_type>, "options", "advanced_chemotaxis", <tag>)`
  - `"enabled"` (value is `"true"`or `"false"`)
  - `"normalize_each_gradient"` (value is `"true"`or `"false"`)
- `motilityPath(<cell_type>, "options", "advanced_chemotaxis", "chemotactic_sensitivities", "chemotactic_sensitivity:substrate:<substrate_name>")`
  - `<substrate_name>` is a string of the model substrate
"""
motilityPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = phenotypePath(cell_definition, "motility", path_elements...)

"""
    secretionPath(cell_definition::AbstractString, substrate_name::AbstractString, tag::AbstractString)

Return the XML path to the secretion tag of the given substrate for the given cell type.

Possible `tag`s include:
- `"secretion_rate"`
- `"secretion_target"`
- `"uptake_rate"`
- `"net_export_rate"`
"""
secretionPath(cell_definition::AbstractString, substrate_name::AbstractString, tag::AbstractString) = phenotypePath(cell_definition, "secretion", "substrate:name:$(substrate_name)", tag)

"""
    cellInteractionsPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the cell interactions for the given cell type (or deeper if more path elements are given).

Possible `path_elements` include:
- `cellInteractionsPath(<cell_type>, <tag>)` with `<tag>` one of
  - `"apoptotic_phagocytosis_rate"`
  - `"necrotic_phagocytosis_rate"`
  - `"other_dead_phagocytosis_rate"`
  - `"attack_damage_rate"`
  - `"attack_duration"`
For other elements in `<cell_interactions>`, use [`phagocytosisPath`](@ref), [`attackRatePath`](@ref), or [`fusionPath`](@ref) as needed.
"""
cellInteractionsPath(cell_definition::AbstractString, path_elements::Vararg{AbstractString}) = phenotypePath(cell_definition, "cell_interactions", path_elements...)

"""
    phagocytosisPath(cell_definition::AbstractString, target_cell_definition::AbstractString)
    phagocytosisPath(cell_definition::AbstractString, death_process::Symbol)

Return the XML path to the phagocytosis element for the given cell type.
If a string is supplied, it is treated as a cell type.
If a symbol is supplied, it specifies a death model and must be one of `:apoptosis`, `:necrosis`, or `:other_dead`.

# Examples
```jldoctest
julia> PhysiCellModelManager.phagocytosisPath("M1", "cancer")
6-element Vector{String}:
 "cell_definitions"
 "cell_definition:name:M1"
 "phenotype"
 "cell_interactions"
 "live_phagocytosis_rates"
 "phagocytosis_rate:name:cancer"
```
```jldoctest
julia> PhysiCellModelManager.phagocytosisPath("M1", :apoptotic)
5-element Vector{String}:
 "cell_definitions"
 "cell_definition:name:M1"
 "phenotype"
 "cell_interactions"
 "apoptotic_phagocytosis_rate"
```
"""
phagocytosisPath(cell_definition::AbstractString, target_cell_definition::AbstractString) = cellInteractionsPath(cell_definition, "live_phagocytosis_rates", "phagocytosis_rate:name:$(target_cell_definition)")

function phagocytosisPath(cell_definition::AbstractString, death_process::Symbol)
    tag = begin
        if death_process in [:apoptosis, :apoptotic]
            "apoptotic_phagocytosis_rate"
        elseif death_process in [:necrosis, :necrotic]
            "necrotic_phagocytosis_rate"
        elseif death_process == :other_dead
            "other_dead_phagocytosis_rate"
        else
            msg = """
            The `death_process` symbol passed in to `phagocytosisPath` must be one of...
              :apoptosis, :necrosis, or :other_dead.
              
              Got: $(death_process)
            """
            throw(ArgumentError(msg))
        end
    end
    return cellInteractionsPath(cell_definition, tag)
end

"""
    attackRatePath(cell_definition::AbstractString, target_cell_definition::AbstractString)

Return the XML path to the attack rate of the first cell type attacking the second cell type.
[`attackPath`](@ref) and [`attackRatesPath`](@ref) are synonyms for this function.

# Examples
```jldoctest
julia> PhysiCellModelManager.attackRatePath("cd8", "cancer")
6-element Vector{String}:
 "cell_definitions"
 "cell_definition:name:cd8"
 "phenotype"
 "cell_interactions"
 "attack_rates"
 "attack_rate:name:cancer"
```
"""
attackRatePath(cell_definition::AbstractString, target_cell_definition::AbstractString) = cellInteractionsPath(cell_definition, "attack_rates", "attack_rate:name:$(target_cell_definition)")

"""
    attackPath(cell_definition::AbstractString, target_cell_definition::AbstractString)

Alias for [`attackRatePath`](@ref).
"""
attackPath = attackRatePath

"""
    attackRatesPath(cell_definition::AbstractString, target_cell_definition::AbstractString)

Alias for [`attackRatePath`](@ref).
"""
attackRatesPath = attackRatePath

"""
    fusionPath(cell_definition::AbstractString, target_cell_definition::AbstractString)

Return the XML path to the fusion rate of the first cell type fusing to the second cell type.

# Examples
```jldoctest
julia> PhysiCellModelManager.fusionPath("epi", "epi")
6-element Vector{String}:
 "cell_definitions"
 "cell_definition:name:epi"
 "phenotype"
 "cell_interactions"
 "fusion_rates"
 "fusion_rate:name:epi"
```
"""
fusionPath(cell_definition::AbstractString, target_cell_definition::AbstractString) = cellInteractionsPath(cell_definition, "fusion_rates", "fusion_rate:name:$(target_cell_definition)")

"""
    transformationPath(from_cell_definition::AbstractString, to_cell_definition::AbstractString)

Return the XML path to the transformation rates for the first cell definition to the second cell definition.

# Examples
```jldoctest
julia> PhysiCellModelManager.transformationPath("M1", "M2")
6-element Vector{String}:
 "cell_definitions"
 "cell_definition:name:M1"
 "phenotype"
 "cell_transformations"
 "transformation_rates"
 "transformation_rate:name:M2"
```
"""
function transformationPath(from_cell_definition::AbstractString, to_cell_definition::AbstractString)
    return phenotypePath(from_cell_definition, "cell_transformations", "transformation_rates", "transformation_rate:name:$(to_cell_definition)")
end

"""
    integrityPath(cell_definition::AbstractString, tag::AbstractString)

Return the XML path to the cell integrity tag for the given cell type.

Possible `tag`s include:
- `"damage_rate"`
- `"damage_repair_rate"`
"""
integrityPath(cell_definition::AbstractString, tag::AbstractString) = phenotypePath(cell_definition, "cell_integrity", tag)

"""
    customDataPath(cell_definition::AbstractString, tag::AbstractString)

Return the XML path to the custom data tag for the given cell type.
"""
customDataPath(cell_definition::AbstractString, tag::AbstractString) = cellDefinitionPath(cell_definition, "custom_data", tag)

"""
    initialParameterDistributionPath(cell_definition::AbstractString, behavior::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the initial parameter distribution of the behavior for the given cell type.

Possible `path_elements` depend on the `type` of the distribution:
- `type="Uniform"`    : `min`, `max`
- `type="LogUniform"` : `min`, `max`
- `type="Normal"`     : `mu`, `sigma`, `lower_bound`, `upper_bound`
- `type="LogNormal"`  : `mu`, `sigma`, `lower_bound`, `upper_bound`
- `type="Log10Normal"`: `mu`, `sigma`, `lower_bound`, `upper_bound`
"""
function initialParameterDistributionPath(cell_definition::AbstractString, behavior::AbstractString, path_elements::Vararg{AbstractString})
    return cellDefinitionPath(cell_definition, "initial_parameter_distributions", "distribution::behavior:$(behavior)", path_elements...)
end

"""
    userParameterPath(tag::AbstractString)

Return the XML path to the user parameter for the given field name. [`userParametersPath`](@ref) is a synonym for this function.
"""
userParameterPath(tag::AbstractString) = ["user_parameters"; tag]

"""
    userParametersPath(tag::AbstractString)

Alias for [`userParameterPath`](@ref).
"""
userParametersPath = userParameterPath

############# XML Path Helper Functions (non-config) #############

"""
    rulePath(cell_definition::AbstractString, behavior::AbstractString, path_elements::Vararg{AbstractString})

Return the XML path to the rule for the given cell type and behavior.

Optionally, add more path_elements to the path as extra arguments.

# Example
```jldoctest
julia> rulePath("T cell", "attack rate")
2-element Vector{String}:
 "behavior_ruleset:name:T cell"
 "behavior:name:attack rate"
```
```jldoctest
julia> rulePath("cancer", "cycle entry", "increasing_signals", "signal:name:oxygen", "half_max")
5-element Vector{String}:
 "behavior_ruleset:name:cancer"
 "behavior:name:cycle entry"
 "increasing_signals"
 "signal:name:oxygen"
 "half_max"
```
"""
function rulePath(cell_definition::AbstractString, behavior::AbstractString, path_elements::Vararg{AbstractString})
    return ["behavior_ruleset:name:$(cell_definition)"; "behavior:name:$(behavior)"; path_elements...]
end

"""
    icCellsPath(cell_definition::AbstractString, patch_type::AbstractString, patch_id, path_elements::Vararg{Union{Integer,AbstractString}})

Return the XML path to the IC cell patch for the given cell type, patch type, and patch ID.
The remaining arguments are either just the tag for the patch parameter or the carveout patch type, ID, and tag.

# Examples
```jldoctest
julia> icCellsPath("default", "disc", 1, "x0")
4-element Vector{String}:
 "cell_patches:name:default"
 "patch_collection:type:disc"
 "patch:ID:1"
 "x0"
```
```jldoctest
julia> icCellsPath("default", "annulus", 1, "rectangle", 1, "width")
7-element Vector{String}:
 "cell_patches:name:default"
 "patch_collection:type:annulus"
 "patch:ID:1"
 "carveout_patches"
 "patch_collection:type:rectangle"
 "patch:ID:1"
 "width"
```
"""
function icCellsPath(cell_definition::AbstractString, patch_type::AbstractString, patch_id, path_elements::Vararg{Union{Integer,AbstractString}})
    supported_patch_types = PhysiCellCellCreator.supportedPatchTypes()
    @assert patch_type in supported_patch_types "IC Cell patch_type must be one of the available patch types, i.e., in $(supported_patch_types). Got $(patch_type)"
    xml_path = ["cell_patches:name:$(cell_definition)"; "patch_collection:type:$(patch_type)"; "patch:ID:$(patch_id)"]
    if length(path_elements) == 1
        #! then this is a tag of the patch
        @assert path_elements[1] in PhysiCellCellCreator.supportedPatchTextElements(patch_type) "IC Cell patch_type $(patch_type) does not support the tag $(path_elements[1]). Supported tags are: $(PhysiCellCellCreator.supportedPatchTextElements(patch_type))"
        return [xml_path; path_elements[1]]
    end
    @assert length(path_elements) == 3 "After the patch ID, either one (for a patch parameter) or three (for a carveout parameter) additional path elements must be provided. Got $(length(path_elements)) elements."
    carveout_patch_type, carveout_patch_id, carveout_patch_tag = path_elements
    @assert carveout_patch_type in PhysiCellCellCreator.supportedCarveoutTypes() "IC Cell carveout type must be one of the available carveout patch types, i.e., in $(PhysiCellCellCreator.supportedCarveoutTypes()). Got $(carveout_patch_type)"
    return [xml_path; "carveout_patches"; "patch_collection:type:$(carveout_patch_type)"; "patch:ID:$(carveout_patch_id)"; carveout_patch_tag]
end

"""
    icECMPath(layer_id::Int, patch_type::AbstractString, patch_id, path_elements::Vararg{AbstractString})

Return the XML path to the IC ECM patch for the given layer_id, patch_type, and patch_id.
Optionally, add more path_elements to the path as extra arguments.

# Examples
```jldoctest
julia> icECMPath(2, "ellipse", 1, "a")
4-element Vector{String}:
 "layer:ID:2"
 "patch_collection:type:ellipse"
 "patch:ID:1"
 "a"
```
```jldoctest
julia> icECMPath(2, "elliptical_disc", 1, "density")
4-element Vector{String}:
 "layer:ID:2"
 "patch_collection:type:elliptical_disc"
 "patch:ID:1"
 "density"
```
```jldoctest
julia> icECMPath(2, "ellipse_with_shell", 1, "interior", "density")
5-element Vector{String}:
 "layer:ID:2"
 "patch_collection:type:ellipse_with_shell"
 "patch:ID:1"
 "interior"
 "density"
```
"""
function icECMPath(layer_id, patch_type::AbstractString, patch_id, path_elements::Vararg{AbstractString})
    supported_patch_types = PhysiCellECMCreator.supportedPatchTypes()
    @assert patch_type in supported_patch_types "IC ECM patch_type must be one of the available patch types, i.e., in $(supported_patch_types). Got $(patch_type)"
    xml_path = ["layer:ID:$(layer_id)"; "patch_collection:type:$(patch_type)"; "patch:ID:$(patch_id)"]
    if length(path_elements) == 1
        #! then this is a tag of the patch
        @assert path_elements[1] in PhysiCellECMCreator.supportedPatchTextElements(patch_type) "IC ECM patch_type $(patch_type) does not support the tag $(path_elements[1]). Supported tags are: $(PhysiCellECMCreator.supportedPatchTextElements(patch_type))"
        return [xml_path; path_elements[1]]
    end
    @assert patch_type == "ellipse_with_shell" && length(path_elements) == 2 "After the patch ID, either one (for a patch parameter) or two (for an ellipse_with_shell parameter) additional path elements must be provided. Got $(length(path_elements)) elements."
    subpatch, tag = path_elements
    @assert subpatch ∈ ["interior", "shell", "exterior"] "For the ellipse_with_shell patch type, the first argument after the patch ID must be either 'interior', 'shell', or 'exterior'. Got $(subpatch)"
    @assert tag ∈ ["density", "anisotropy", "orientation"] "For the ellipse_with_shell patch type, the second argument after the patch ID must be either 'density', 'anisotropy', or 'orientation'. Got $(tag)"
    return ["layer:ID:$(layer_id)"; "patch_collection:type:$(patch_type)"; "patch:ID:$(patch_id)"; subpatch; tag]
end

################## Simplify Name Functions ##################

"""
    shortLocationVariationID(fieldname)

Return the short location variation ID name used in creating a DataFrame summary table.

# Arguments
- `fieldname`: The field name to get the short location variation ID for. This can be a symbol or a string.
"""
function shortLocationVariationID(fieldname::Symbol)
    if fieldname == :config
        return :ConfigVarID
    elseif fieldname == :rulesets_collection
        return :RulesVarID
    elseif fieldname == :intracellular
        return :IntraVarID
    elseif fieldname == :ic_cell
        return :ICCellVarID
    elseif fieldname == :ic_ecm
        return :ICECMVarID
    else
        throw(ArgumentError("Got fieldname $(fieldname). However, it must be 'config', 'rulesets_collection', 'intracellular', 'ic_cell', or 'ic_ecm'."))
    end
end

shortLocationVariationID(fieldname::String) = shortLocationVariationID(Symbol(fieldname))

"""
    shortLocationVariationID(type::Type, fieldname::Union{String, Symbol})

Return (as a `type`) the short location variation ID name used in creating a DataFrame summary table.
"""
function shortLocationVariationID(type::Type, fieldname::Union{String, Symbol})
    return type(shortLocationVariationID(fieldname))
end

"""
    shortVariationName(location::Symbol, name::String)

Return the short name of the varied parameter for the given location and name used in creating a DataFrame summary table.
"""
function shortVariationName(location::Symbol, name::String)
    if location == :config
        return shortConfigVariationName(name)
    elseif location == :rulesets_collection
        return shortRulesetsVariationName(name)
    elseif location == :intracellular
        return shortIntracellularVariationName(name)
    elseif location == :ic_cell
        return shortICCellVariationName(name)
    elseif location == :ic_ecm
        return shortICECMVariationName(name)
    else
        throw(ArgumentError("location must be 'config', 'rulesets_collection', 'intracellular', 'ic_cell', or 'ic_ecm'."))
    end
end

"""
    shortConfigVariationName(name::String)

Return the short name of the varied parameter in the configuration file for the given name used in creating a DataFrame summary table.
"""
function shortConfigVariationName(name::String)
    if name == "config_variation_id"
        return shortLocationVariationID(String, "config")
    elseif name == "overall/max_time"
        return "Max Time"
    elseif name == "save/full_data/interval"
        return "Full Save Interval"
    elseif name == "save/SVG/interval"
        return "SVG Save Interval"
    elseif startswith(name, "cell_definitions")
        return cellParameterName(name)
    else
        return name
    end
end

"""
    shortRulesetsVariationName(name::String)

Return the short name of the varied parameter in the rulesets collection file for the given name used in creating a DataFrame summary table.
"""
function shortRulesetsVariationName(name::String)
    if name == "rulesets_collection_variation_id"
        return shortLocationVariationID(String, "rulesets_collection")
    else
        return ruleParameterName(name)
    end
end

"""
    shortIntracellularVariationName(name::String)

Return the short name of the varied parameter in the intracellular file for the given name used in creating a DataFrame summary table.
"""
function shortIntracellularVariationName(name::String)
    if name == "intracellular_variation_id"
        return shortLocationVariationID(String, "intracellular")
    else
        return name
    end
end

"""
    shortICCellVariationName(name::String)

Return the short name of the varied parameter in the IC cell file for the given name used in creating a DataFrame summary table.
"""
function shortICCellVariationName(name::String)
    if name == "ic_cell_variation_id"
        return shortLocationVariationID(String, "ic_cell")
    else
        return icCellParameterName(name)
    end
end

"""
    shortICECMVariationName(name::String)

Return the short name of the varied parameter in the ECM file for the given name used in creating a DataFrame summary table.
"""
function shortICECMVariationName(name::String)
    if name == "ic_ecm_variation_id"
        return shortLocationVariationID(String, "ic_ecm")
    else
        return icECMParameterName(name)
    end
end

"""
    cellParameterName(column_name::String)

Return the short name of the varied parameter associated with a cell definition for the given column name used in creating a DataFrame summary table.
"""
function cellParameterName(column_name::String)
    xml_path = columnNameToXMLPath(column_name)
    cell_type = split(xml_path[2], ":"; limit=3) |> last
    target_name = ""
    for component in xml_path[3:end]
        if contains(component, "::")
            #! something like "distribution::behavior:oxygen uptake" for initial parameter distributions
            target_name = split(component, "::"; limit=2) |> last
            target_name = split(target_name, ":"; limit=2) |> last
        elseif contains(component, ":name:")
            target_name = split(component, ":"; limit=3) |> last
            break
        elseif contains(component, ":code:")
            target_code = split(component, ":"; limit=3) |> last
            @assert target_code in ["100", "101"] "Unknown code in xml path: $(target_code)"
            if target_code == "100"
                target_name = "apop"
            else
                target_name = "necr"
            end
            break
        end
    end
    suffix = xml_path[end]
    if target_name != ""
        suffix = "$(target_name) $(suffix)"
    end
    return replace("$(cell_type): $(suffix)", '_' => ' ')
end

"""
    ruleParameterName(name::String)

Return the short name of the varied parameter associated with a ruleset for the given name used in creating a DataFrame summary table.
"""
function ruleParameterName(name::String)
    @assert startswith(name, "behavior_ruleset") "'name' for a rulesets variation name must start with 'behavior_ruleset'. Got $(name)"
    xml_path = columnNameToXMLPath(name)
    cell_type = split(xml_path[1], ":"; limit=3) |> last
    behavior = split(xml_path[2], ":"; limit=3) |> last
    is_decreasing = xml_path[3] == "decreasing_signals"
    if xml_path[4] == "max_response"
        ret_val = "$(cell_type): $(behavior) $(is_decreasing ? "min" : "max")"
    else
        response = is_decreasing ? "decreases" : "increases"
        signal = split(xml_path[4], ":"; limit=3) |> last
        ret_val = "$(cell_type): $(signal) $(response) $(behavior) $(xml_path[5])"
    end
    return ret_val |> x->replace(x, '_' => ' ')
end

"""
    icCellParameterName(name::String)

Return the short name of the varied parameter associated with a cell patch for the given name used in creating a DataFrame summary table.
"""
function icCellParameterName(name::String)
    @assert startswith(name, "cell_patches") "'name' for a cell variation name must start with 'cell_patches'. Got $(name)"
    xml_path = columnNameToXMLPath(name)
    cell_type = split(xml_path[1], ":"; limit=3) |> last
    patch_type = split(xml_path[2], ":"; limit=3) |> last
    id = split(xml_path[3], ":"; limit=3) |> last
    parameter = xml_path[4]
    return "$(cell_type) IC: $(patch_type)[$(id)] $(parameter)" |> x->replace(x, '_' => ' ')
end

"""
    icECMParameterName(name::String)

Return the short name of the varied parameter associated with a ECM patch for the given name used in creating a DataFrame summary table.
"""
function icECMParameterName(name::String)
    @assert startswith(name, "layer") "'name' for a ecm variation name must start with 'layer'. Got $(name)"
    xml_path = columnNameToXMLPath(name)
    layer_id = split(xml_path[1], ":"; limit=3) |> last
    patch_type = split(xml_path[2], ":"; limit=3) |> last
    patch_id = split(xml_path[3], ":"; limit=3) |> last
    parameter = join(xml_path[4:end], "-")
    return "L$(layer_id)-$(patch_type)-P$(patch_id): $(parameter)" |> x->replace(x, '_' => ' ')
end