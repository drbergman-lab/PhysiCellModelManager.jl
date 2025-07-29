using LightXML, TOML, AutoHashEquals

export assembleIntracellular!, PhysiCellComponent

"""
    PhysiCellComponent

A struct to hold the information about a component that is used to assemble an input of PhysiCell.

The `type` and `name` are the only fields that are compared for equality.
The `type` represents the type of component that it is.
Currently, only "roadrunner" is supported.
The `name` is the name of the file inside the `components/type/` directory.
The `id` is the id of the component, which will be -1 to indicate it is not yet set.
The `id` is used to link which cell definition(s) use which component(s).

# Fields
- `type::String`: The type of the component (e.g., "roadrunner", "dfba", "maboss").
- `name::String`: The name of the component (e.g., "component.xml").
- `id::Int`: The id of the component (e.g., 1, 2, 3). This is used to link which cell definition(s) use which component(s). A value of -1 indicates that the id is not yet set.

# Examples
```jldoctest
julia> PhysiCellComponent("roadrunner", "test.xml")
PhysiCellComponent("roadrunner", "test.xml", -1)
```
```jldoctest
component = PhysiCellComponent("roadrunner", "test.xml")
PhysiCellComponent(component, 78) # set the id to 78; users should not need to do this
# output
PhysiCellComponent("roadrunner", "test.xml", 78)
"""
@auto_hash_equals fields = (type, name) struct PhysiCellComponent #! only compare the name and type for equality
    type::String #! type of the file (currently going to be "roadrunner", "dfba", or "maboss")
    name::String #! name of the file
    id::Int #! id of the component (will be -1 to indicate it is not yet known)

    function PhysiCellComponent(type::String, name::String)
        return new(type, name, -1)
    end

    function PhysiCellComponent(component::PhysiCellComponent, id::Int)
        return new(component.type, component.name, id)
    end
end

pathFromComponents(component::PhysiCellComponent) = joinpath(component.type, component.name)

function assembleIntracellular!(cell_to_components_dict::Dict{String,<:Union{PhysiCellComponent,Vector{PhysiCellComponent}}}; kwargs...)
    cell_to_vec_components_dict = Dict{String,Vector{PhysiCellComponent}}()
    for (cell_type, components) in cell_to_components_dict
        if components isa PhysiCellComponent
            cell_to_vec_components_dict[cell_type] = [components]
        else
            cell_to_vec_components_dict[cell_type] = components
        end
    end
    return assembleIntracellular!(cell_to_vec_components_dict; kwargs...)
end

"""
    assembleIntracellular!(cell_to_components_dict::Dict{String,Vector{PhysiCellComponent}}; name::String="assembled", skip_db_insert::Bool=false)

Assembles the intracellular components for the given cell types into a single file.

First, check if the components have been previously assembled.
If so, return that folder name.
If not, create a new folder and save the components there as a single file along with the assembly manifest; finally, update the database with the new folder.

# Arguments
- `cell_to_components_dict::Dict{String,Vector{PhysiCellComponent}}`: A dictionary mapping cell types to their components.
  - The keys are the cell type names (e.g., "T_cell", "B_cell").
  - The values can be either a single [`PhysiCellComponent`](@ref) or a vector of `PhysiCellComponent`s.
- `name::String`: The name of the folder to create (default is "assembled").
- `skip_db_insert::Bool`: If true, skip the database insert (default is false). Skipped when importing a project. Users should not need to set this.

# Returns
- `folder::String`: The name of the folder where the components were assembled.
"""
function assembleIntracellular!(cell_to_components_dict::Dict{String,Vector{PhysiCellComponent}}; name::String="assembled", skip_db_insert::Bool=false)
    #! get all components to assign IDs
    unique_components = PhysiCellComponent[]
    for components in values(cell_to_components_dict)
        for component in components
            if component in unique_components
                continue
            end
            push!(unique_components, component)
        end
    end
    temp_ids = Dict{PhysiCellComponent,Int}()
    for (i, c) in enumerate(unique_components)
        temp_ids[c] = i
    end

    #! create the assembly record first to compare and then to save (if assembling now)
    assembly_manifest = Dict{String,Dict{String,Any}}()
    assembly_manifest["cell_definitions"] = Dict{String,Any}()
    assembly_manifest["intracellulars"] = Dict{String,Any}()
    for (cell_type, components) in cell_to_components_dict
        if isempty(components)
            continue
        end
        assembly_manifest["cell_definitions"][cell_type] = Int[]
        for component in components
            id_str = string(temp_ids[component])
            push!(assembly_manifest["cell_definitions"][cell_type], temp_ids[component])
            assembly_manifest["intracellulars"][id_str] = Dict{String,Any}()
            assembly_manifest["intracellulars"][id_str]["type"] = component.type
            assembly_manifest["intracellulars"][id_str]["name"] = component.name
        end
    end

    #! compare against previously-assembled intracellulars
    path_to_folder = intracellularFolder(assembly_manifest)
    if !isnothing(path_to_folder)
        updateIntracellularComponentIDs!(cell_to_components_dict, path_to_folder)
        return splitpath(path_to_folder)[end]
    end

    #! pick a folder name, adding a number if it already exists
    path_to_folders = locationPath(:intracellular)
    folder = name
    n = 0
    while isdir(joinpath(path_to_folders, folder))
        n += 1
        folder = "$(name)_$(n)"
    end
    path_to_folder = joinpath(path_to_folders, folder)
    mkdir(path_to_folder)

    #! since we're here and creating a new folder, it is possible that prevoiusly defined ids could conflict, so let's no rely on them.
    for (cell_type, components) in cell_to_components_dict
        updated_components = PhysiCellComponent[]
        for component in components
            push!(updated_components, PhysiCellComponent(component, temp_ids[component]))
        end
        cell_to_components_dict[cell_type] = updated_components
    end

    xml_doc = XMLDocument()
    xml_root = create_root(xml_doc, "PhysiCell_intracellular_mappings")

    #! create cell definitions element
    e_cell_definitions = new_child(xml_root, "cell_definitions")
    for (cell_type, components) in cell_to_components_dict
        e_cell_definition = new_child(e_cell_definitions, "cell_definition")
        set_attribute(e_cell_definition, "name", cell_type)
        e_intracellular_ids = new_child(e_cell_definition, "intracellular_ids")
        for component in components
            e_intracellular_id = new_child(e_intracellular_ids, "ID")
            set_content(e_intracellular_id, string(component.id))
        end
    end

    #! create intracellulars element
    e_intracellulars = new_child(xml_root, "intracellulars")
    for (component, i) in temp_ids
        e_intracellular = new_child(e_intracellulars, "intracellular")
        set_attribute(e_intracellular, "ID", string(i))
        set_attribute(e_intracellular, "type", component.type)

        path_to_component_xml = joinpath(dataDir(), "components", pathFromComponents(component))
        component_xml_doc = parse_file(path_to_component_xml)
        component_xml_root = root(component_xml_doc)
        add_child(e_intracellular, component_xml_root)
        free(component_xml_doc)
    end

    save_file(xml_doc, joinpath(path_to_folder, "intracellular.xml"))
    free(xml_doc)

    #! record the assembly of the document
    open(joinpath(path_to_folder, "assembly.toml"), "w") do io
        TOML.print(io, assembly_manifest)
    end

    #! make sure the database is updated, variations.db intialized
    if pcmm_globals.initialized && !skip_db_insert
        insertFolder(:intracellular, splitpath(folder)[end])
    end

    #! return just the folder name
    return folder
end

"""
    intracellularFolder(assembly_manifest::Dict)

Get the folder that contains the intracellular assembly manifest that is equivalent to the given assembly manifest, if one exists.

If no such folder exists, return nothing.
"""
function intracellularFolder(assembly_manifest::Dict)
    path_to_location_folders = locationPath(:intracellular)

    for folder in readdir(path_to_location_folders; join=true, sort=false)
        #! only look in folders that have an assembly.toml file
        if !isdir(folder) || !isfile(joinpath(folder, "assembly.toml"))
            continue
        end
        previous_assembly_manifest = TOML.parsefile(joinpath(folder, "assembly.toml"))
        if intracellularAssemblyManifestsEquivalent(previous_assembly_manifest, assembly_manifest)
            return folder
        end
    end
    return nothing
end

"""
    intracellularAssemblyManifestsEquivalent(A::Dict, B::Dict)

Compare two intracellular assembly manifests to see if they are equivalent.

Two manifests may assign different IDs to the same components.
This function compares the component files to see if the manifests are equivalent.
"""
function intracellularAssemblyManifestsEquivalent(A::Dict, B::Dict)

    function _get_cell_to_components_dict(d::Dict)
        cell_to_components_dict = Dict{String,Vector{PhysiCellComponent}}()
        for (cell_type, ids) in d["cell_definitions"]
            cell_to_components_dict[cell_type] = PhysiCellComponent[]
            for id in string.(ids)
                component = PhysiCellComponent(d["intracellulars"][id]["type"], d["intracellulars"][id]["name"]) #! all will have PhysiCellComponent id -1
                @assert !(component in cell_to_components_dict[cell_type]) "Duplicate component in cell type $cell_type: $component"
                push!(cell_to_components_dict[cell_type], component)
            end
        end
        return cell_to_components_dict
    end

    dict_assembly_A = _get_cell_to_components_dict(A)
    dict_assembly_B = _get_cell_to_components_dict(B)
    all_cell_types = Set(union(keys(dict_assembly_A), keys(dict_assembly_B)))

    for cell_type in all_cell_types
        #! first check if the cell type actually has components in A or B
        has_intracellular_A = haskey(dict_assembly_A, cell_type) && !isempty(dict_assembly_A[cell_type])
        has_intracellular_B = haskey(dict_assembly_B, cell_type) && !isempty(dict_assembly_B[cell_type])
        if !has_intracellular_A && !has_intracellular_B
            continue
        end

        #! if one has the cell type and the other does not, then these are not the same (⊻ = XOR)
        if (has_intracellular_A ⊻ has_intracellular_B)
            return false
        end

        #! otherwise, both have it, check that these are the same
        if Set{PhysiCellComponent}(dict_assembly_A[cell_type]) != Set{PhysiCellComponent}(dict_assembly_B[cell_type])
            return false
        end
    end
    return true
end

"""
    updateIntracellularComponentIDs!(cell_to_components_dict::Dict{String,Vector{PhysiCellComponent}}, path_to_folder::String)

Update the IDs of the components in the given dictionary to match those in the assembly manifest in the given folder.
"""
function updateIntracellularComponentIDs!(cell_to_components_dict::Dict{String,Vector{PhysiCellComponent}}, path_to_folder::String)
    path_to_file = joinpath(path_to_folder, "assembly.toml")
    @assert isfile(path_to_file) "Assembly file does not exist: $path_to_file"
    assembly_manifest = TOML.parsefile(path_to_file)

    for (cell_type, components) in cell_to_components_dict
        if isempty(components)
            continue
        end
        new_components = PhysiCellComponent[]
        for component in components
            component_id = findComponentID(assembly_manifest, component)
            push!(new_components, PhysiCellComponent(component, parse(Int, component_id)))
        end
        cell_to_components_dict[cell_type] = new_components
    end
end

"""
    findComponentID(assembly_manifest::Dict, component::PhysiCellComponent)

Find the ID of the given component in the assembly manifest.
"""
function findComponentID(assembly_manifest::Dict, component::PhysiCellComponent)
    for (id, component_dict) in assembly_manifest["intracellulars"]
        if component_dict["name"] == component.name && component_dict["type"] == component.type
            return id
        end
    end
    @assert false "Component not found in assembly manifest: $component"
end