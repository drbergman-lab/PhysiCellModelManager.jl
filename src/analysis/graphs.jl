using Graphs, MetaGraphsNext

include(joinpath(@__DIR__, "..", "..", "deps", "DeprecateKeywords.jl"))
import .DeprecateKeywords: @depkws

export connectedComponents

"""
    connectedComponents(snapshot::PhysiCellSnapshot, graph=:neighbors; include_cell_type_names=:all_in_one, exclude_cell_type_names::String[], include_dead::Bool=false)
    connectedComponents(simulation::Simulation, index, graph; kwargs...)
    connectedComponents(pcmm_output::PCMMOutput{Simulation}, args...; kwargs...)

Find the connected components of a graph in a PhysiCell snapshot.

The computation can be done on subsets of cells based on their cell types.

# Arguments
- `snapshot::PhysiCellSnapshot`: The snapshot to analyze
- `graph`: The graph data to use (default is `:neighbors`); must be one of `:neighbors`, `:attachments`, or `:spring_attachments`; can also be a string
- `simulation::Simulation`: The simulation object to analyze
- `index`: The index of the snapshot to analyze (can be an integer or a symbol)
- `pcmm_output::PCMMOutput{Simulation}`: The output of a PCMM simulation run to analyze

# Keyword Arguments
- `include_cell_type_names`: The cell types to include in the analysis (default is `:all_in_one`). Full list of options:
    - `:all` - compute connected components for all cell types individually
    - `:all_in_one` - compute connected components for all cell types together
    - `"cell_type_1"` - compute connected components only for the cells of type `cell_type_1`
    - `["cell_type_1", "cell_type_2"]` - compute connected components for the cells of type `cell_type_1` and `cell_type_2` separately
    - `[["cell_type_1", "cell_type_2"]]` - compute connected components for the cells of type `cell_type_1` and `cell_type_2` together
    - `[["cell_type_1", "cell_type_2"], "cell_type_3"]` - compute connected components for the cells of type `cell_type_1` and `cell_type_2` together, and for the cells of type `cell_type_3` separately
- `exclude_cell_type_names`: The cell types to exclude from the analysis (default is `String[]`); can be a single string or a vector of strings
- `include_dead`: Whether to include dead cells in the analysis (default is `false`)

# Returns
A dictionary in which each key is one of the following:
- cell type name (String)
- list of cell type names (Vector{String})
- list of cell type names followed by the symbol :include_dead (Vector{Any})

For each key, the value is a list of connected components in the graph.
Each component is represented as a vector of vertex labels.
As of this writing, the vertex labels are the simple `AgentID` class that wraps the cell ID.
"""
@depkws force=true function connectedComponents(snapshot::PhysiCellSnapshot, graph::Symbol=:neighbors; include_cell_type_names=:all_in_one, exclude_cell_type_names=String[], include_dead::Bool=false,
    @deprecate(include_cell_types, include_cell_type_names), @deprecate(exclude_cell_types, exclude_cell_type_names))
    is_all_in_one = include_cell_type_names == :all_in_one
    cell_type_to_name_dict = cellTypeToNameDict(snapshot)
    cell_type_names = values(cell_type_to_name_dict) |> collect

    include_cell_type_names = processIncludeCellTypes(include_cell_type_names, cell_type_names)
    exclude_cell_type_names = processExcludeCellTypes(exclude_cell_type_names)

    loadGraph!(snapshot, graph)
    if is_all_in_one
        G = getfield(snapshot, graph) |> deepcopy
        if include_dead
            key = [include_cell_type_names[1]; :include_dead]
        else
            key = include_cell_type_names[1]
            loadCells!(snapshot)
            dead_cell_ids = snapshot.cells.ID[snapshot.cells.dead] |> Set
            vertices_to_remove = [v for v in vertices(G) if G.vertex_labels[v].id in dead_cell_ids]
            sort!(vertices_to_remove; rev=true)
            for v in vertices_to_remove
                rem_vertex!(G, v)
            end
        end
        return Dict(key => _connectedComponents(G))
    end

    loadCells!(snapshot)

    #! if not all_in_one, then we need to manage the cells carefully
    data = Dict{Any,Any}()
    if include_dead
        id_to_name = [row.ID => cell_type_to_name_dict[row.cell_type] for row in eachrow(snapshot.cells)] |> Dict
    else
        #! map any dead cells to the Symbol :dead so it cannot be in the list of String cell types
        id_to_name = [row.ID => (row.dead ? :dead : cell_type_to_name_dict[row.cell_type]) for row in eachrow(snapshot.cells)] |> Dict
    end

    for cell_group in include_cell_type_names
        if cell_group isa String
            internal_keys = [cell_group] #! standardize so that all are vectors
        else
            internal_keys = cell_group
            @assert internal_keys isa Vector{String} "include_cell_type_names must be a vector of strings"
        end
        setdiff!(internal_keys, exclude_cell_type_names) #! remove any cell types that are to be excluded (also removes duplicates)
        if isempty(internal_keys)
            continue
        end
        G = getfield(snapshot, graph) |> deepcopy
        vertices_to_remove = [v for v in vertices(G) if !in(id_to_name[G.vertex_labels[v].id], internal_keys)]
        sort!(vertices_to_remove; rev=true)
        for v in vertices_to_remove
            rem_vertex!(G, v)
        end

        output_key = include_dead ? [internal_keys; :include_dead] : internal_keys
        if length(output_key) == 1
            output_key = output_key[1]
        end
        data[output_key] = _connectedComponents(G)
    end
    return data
end

connectedComponents(snapshot::PhysiCellSnapshot, graph::String; kwargs...) = connectedComponents(snapshot, Symbol(graph); kwargs...)

function connectedComponents(simulation::Simulation, index::Union{Integer, Symbol}, graph::Union{Symbol,String}=:neighbors; kwargs...)
    snapshot = PhysiCellSnapshot(simulation, index)
    return connectedComponents(snapshot, graph; kwargs...)
end

connectedComponents(pcmm_output::PCMMOutput{Simulation}, args...; kwargs...) = connectedComponents(pcmm_output.trial, args...; kwargs...)

"""
    _connectedComponents(G::MetaGraph)

Find the connected components of a graph.

First compute the transitive closure of the underlying `Graphs.Graph` object.
Then, update the edge data of the `MetaGraph` object to reflect the new edges.
Finally, loop over vertex labels and find the vertices they are connected to until all vertices are accounted for.
Returns a list of connected components, where each component is represented as a vector of vertex labels.
"""
function _connectedComponents(G::MetaGraph)
    transitiveclosure!(G.graph)
    for e in edges(G.graph)
        edge_datum = (G.vertex_labels[e.src], G.vertex_labels[e.dst])
        G.edge_data[edge_datum] = nothing
    end
    remaining_labels = Set(G.vertex_labels |> values)
    components = []
    while !isempty(remaining_labels)
        next_label = pop!(remaining_labels)
        next_label_ind = G.vertex_properties[next_label][1]
        neighbor_inds = all_neighbors(G.graph, next_label_ind)
        neighbor_labels = [G.vertex_labels[i] for i in neighbor_inds]
        component = vcat(next_label, neighbor_labels)
        push!(components, component)
        setdiff!(remaining_labels, component)
    end
    return components
end