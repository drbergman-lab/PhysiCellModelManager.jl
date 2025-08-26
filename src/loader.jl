using DataFrames, MAT, Graphs, MetaGraphsNext, Dates

export cellDataSequence, getCellDataSequence, PhysiCellSnapshot, PhysiCellSequence,
       loadCells!, loadSubstrates!, loadMesh!, loadGraph!

"""
    AbstractPhysiCellSequence

Abstract type representing either a single snapshot or a sequence of snapshots from a PhysiCell simulation.
"""
abstract type AbstractPhysiCellSequence end

"""
    PhysiCellSnapshot

A single snapshot of a PhysiCell simulation.

The `cells`, `substrates`, `mesh`, and graphs (`attachments`, `spring_attachments`, `neighbors`) fields may remain empty until they are needed for analysis or explicitly loaded by the user.

# Constructors
- `PhysiCellSnapshot(simulation_id::Int, index::Union{Integer, Symbol}, labels::Vector{String}=String[], substrate_names::Vector{String}=String[]; kwargs...)`
- `PhysiCellSnapshot(simulation::Simulation, args...; kwargs...)`

# Fields
- `simulation_id::Int`: The ID of the simulation.
- `index::Union{Int,Symbol}`: The index of the snapshot. Can be an integer or a symbol (`:initial` or `:final`).
- `time::Float64`: The time of the snapshot (in minutes).
- `runtime::Nanosecond`: The runtime to reach this snapshot (in nanoseconds).
- `cells::DataFrame`: A DataFrame containing cell data.
- `substrates::DataFrame`: A DataFrame containing substrate data.
- `mesh::Dict{String, Vector{Float64}}`: A dictionary containing mesh data.
- `attachments::MetaGraph`: A graph of cell attachment data with vertices labeled by cell IDs.
- `spring_attachments::MetaGraph`: A graph of spring attachment data with vertices labeled by cell IDs.
- `neighbors::MetaGraph`: A graph of cell neighbor data with vertices labeled by cell IDs.

# Optional Arguments
- `labels::Vector{String}=String[]`: A vector of cell data labels. Users should let PhysiCellModelManager.jl load this.
- `substrate_names::Vector{String}=String[]`: A vector of substrate names. Users should let PhysiCellModelManager.jl load this.

# Keyword Arguments
- `include_cells::Bool=false`: Whether to load cell data.
- `cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}()`: A dictionary mapping cell type IDs to cell type names.
- `include_substrates::Bool=false`: Whether to load substrate data.
- `include_mesh::Bool=false`: Whether to load mesh data.
- `include_attachments::Bool=false`: Whether to load attachment data.
- `include_spring_attachments::Bool=false`: Whether to load spring attachment data.
- `include_neighbors::Bool=false`: Whether to load neighbor data.

# Examples
```julia
simulation_id = 1
index = 3 # index of the snapshot in the output folder
snapshot = PhysiCellSnapshot(simulation_id, index)

simulation = Simulation(simulation_id)
index = :initial # :initial or :final are the accepted symbols
snapshot = PhysiCellSnapshot(simulation, index)

# Load with specific data types
snapshot = PhysiCellSnapshot(simulation_id, index; include_cells=true, include_substrates=true)
```
"""
struct PhysiCellSnapshot <: AbstractPhysiCellSequence
    simulation_id::Int
    index::Union{Int,Symbol}
    time::Float64
    runtime::Nanosecond
    cells::DataFrame
    substrates::DataFrame
    mesh::Dict{String,Vector{Float64}}
    attachments::MetaGraph
    spring_attachments::MetaGraph
    neighbors::MetaGraph
end

function PhysiCellSnapshot(simulation_id::Int, index::Union{Integer, Symbol},
    labels::Vector{String}=String[],
    substrate_names::Vector{String}=String[];
    include_cells::Bool=false,
    cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(),
    include_substrates::Bool=false,
    include_mesh::Bool=false,
    include_attachments::Bool=false,
    include_spring_attachments::Bool=false,
    include_neighbors::Bool=false)

    filepath_base = pathToOutputFileBase(simulation_id, index)
    path_to_xml = joinpath("$(filepath_base).xml")
    if !isfile(path_to_xml)
        println("Could not find file $path_to_xml. Returning missing.")
        return missing
    end
    xml_doc = parse_file("$(filepath_base).xml")
    time = getContent(xml_doc, ["metadata","current_time"]) |> x->parse(Float64, x)
    seconds_to_nanoseconds = x -> round(x * 1e9) |> Nanosecond
    runtime = getContent(xml_doc, ["metadata", "current_runtime"]) |> x -> parse(Float64, x) |> seconds_to_nanoseconds
    cells = DataFrame()
    if include_cells
        if _loadCells!(cells, filepath_base, cell_type_to_name_dict, labels) |> ismissing
            println("Could not load cell data for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    substrates = DataFrame()
    if include_substrates
        if _loadSubstrates!(substrates, filepath_base, substrate_names) |> ismissing
            println("Could not load substrate data for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    mesh = Dict{String, Vector{Float64}}()
    if include_mesh
        _loadMesh!(mesh, xml_doc)
    end

    attachments = physicellEmptyGraph()
    if include_attachments
        if _loadGraph!(attachments, "$(filepath_base)_attached_cells_graph.txt") |> ismissing
            println("Could not load attachments for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end

    spring_attachments = physicellEmptyGraph()
    if include_spring_attachments
        if _loadGraph!(spring_attachments, "$(filepath_base)_spring_attached_cells_graph.txt") |> ismissing
            println("Could not load spring attachments for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end

    neighbors = physicellEmptyGraph()
    if include_neighbors
        if _loadGraph!(neighbors, "$(filepath_base)_cell_neighbor_graph.txt") |> ismissing
            println("Could not load neighbors for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    free(xml_doc)
    return PhysiCellSnapshot(simulation_id, index, time, runtime, DataFrame(cells), substrates, mesh, attachments, spring_attachments, neighbors)
end

PhysiCellSnapshot(simulation::Simulation, index::Union{Integer,Symbol}, args...; kwargs...) = PhysiCellSnapshot(simulation.id, index, args...; kwargs...)

function Base.show(io::IO, ::MIME"text/plain", snapshot::PhysiCellSnapshot)
    println(io, "PhysiCellSnapshot (SimID=$(snapshot.simulation_id), Index=$(snapshot.index))")
    println(io, "  Time: $(snapshot.time)")
    println(io, "  Current runtime: $(canonicalize(snapshot.runtime))")
    println(io, "  Cells: $(isempty(snapshot.cells) ? "NOT LOADED" : "($(nrow(snapshot.cells)) cells x $(ncol(snapshot.cells)) features) DataFrame")")
    println(io, "  Substrates: $(isempty(snapshot.substrates) ? "NOT LOADED" : "($(size(snapshot.substrates, 1)) voxels x [x, y, z, volume, $(size(snapshot.substrates, 2)-4) substrates]) DataFrame")")
    println(io, "  Mesh: $(isempty(snapshot.mesh) ? "NOT LOADED" : meshInfo(snapshot))")
    println(io, "  Attachments: $(nv(snapshot.attachments)==0 ? "NOT LOADED" : graphInfo(snapshot.attachments))")
    println(io, "  Spring Attachments: $(nv(snapshot.spring_attachments)==0 ? "NOT LOADED" : graphInfo(snapshot.spring_attachments))")
    println(io, "  Neighbors: $(nv(snapshot.neighbors)==0 ? "NOT LOADED" : graphInfo(snapshot.neighbors))")
end

"""
    indexToFilename(index)

Convert an index to a filename in the output folder.

The index can be an integer or a symbol (`:initial` or `:final`).

```jldoctest
julia> PhysiCellModelManager.indexToFilename(0)
"output00000000"
```
```jldoctest
julia> PhysiCellModelManager.indexToFilename(:initial)
"initial"
```
"""
function indexToFilename(index::Symbol)
    @assert index in [:initial, :final] "The non-integer index must be either :initial or :final"
    return string(index)
end

indexToFilename(index::Int) = "output$(lpad(index,8,"0"))"

"""
    AgentID

A wrapper for the agent ID used in PhysiCell.

The purpose of this struct is to make it easier to interpret the data in the MetaGraphs loaded from PhysiCell.
The MetaGraphs use `Int`s to index the vertices, which could cause confusion when looking at the mappings to the agent ID metadata if also using `Int`s.
"""
struct AgentID
    id::Int
end

Base.parse(::Type{AgentID}, s::AbstractString) = AgentID(parse(Int, s))

"""
    AgentDict{T} <: AbstractDict{AgentID,T}

A dictionary-like structure that maps `AgentID`s to values of type `T`.
Integers can be passed as keys and they will be converted to `AgentID`s.
"""
struct AgentDict{T} <: AbstractDict{AgentID,T}
    dict::Dict{AgentID,T}

    function AgentDict(d::Dict{AgentID,T}) where T
        return new{T}(d)
    end

    function AgentDict(d::Dict{<:Integer,T}) where T
        return AgentDict([AgentID(k) => v for (k, v) in d])
    end

    function AgentDict(ps::Vector{<:Pair{AgentID,T}}) where T
        return AgentDict(Dict{AgentID,T}(ps))
    end

    function AgentDict(ps::Vector{<:Pair{<:Integer,T}}) where {T}
        return AgentDict([AgentID(k) => v for (k, v) in ps])
    end
end

#! functions to make AgentDict work like a normal dictionary
Base.getindex(d::AgentDict, args...) = getindex(d.dict, args...)
Base.length(d::AgentDict) = length(d.dict)
Base.iterate(d::AgentDict, args...) = iterate(d.dict, args...)
Base.haskey(d::AgentDict, k::AgentID) = haskey(d.dict, k)
Base.setindex!(d::AgentDict, v, k::AgentID) = setindex!(d.dict, v, k)
Base.delete!(d::AgentDict, k::AgentID) = delete!(d.dict, k)

#! allow users to use integers as keys
Base.getindex(d::AgentDict, k::Integer) = d.dict[AgentID(k)]
Base.haskey(d::AgentDict, k::Integer) = haskey(d.dict, AgentID(k))
Base.setindex!(d::AgentDict, v, k::Integer) = setindex!(d.dict, v, AgentID(k))
Base.delete!(d::AgentDict, k::Integer) = delete!(d.dict, AgentID(k))

"""
    physicellEmptyGraph()

Create an empty graph for use with PhysiCell.

For all PhysiCell graphs, the vertices are labeled with `AgentID`s and the vertices carry no other information.
The edges also carry no extra information other than that the edge exists.
"""
function physicellEmptyGraph()
    return MetaGraph(SimpleDiGraph();
        label_type=AgentID,
        vertex_data_type=Nothing,
        edge_data_type=Nothing)
end

"""
    readPhysiCellGraph!(g::MetaGraph, path_to_txt_file::String)

Read a PhysiCell graph from a text file into a MetaGraph.

Users should use [`loadGraph!`](@ref) instead of this function directly.
"""
function readPhysiCellGraph!(g::MetaGraph, path_to_txt_file::String)
    lines = readlines(path_to_txt_file)
    for line in lines
        cell_id, attached_ids = split(line, ": ")
        cell_id = parse(AgentID, cell_id)
        g[cell_id] = nothing
        if attached_ids == ""
            continue
        end
        for attached_id in split(attached_ids, ",")
            attached_id = parse(AgentID, attached_id)
            g[attached_id] = nothing
            g[cell_id, attached_id] = nothing
        end
    end
end

"""
    PhysiCellSequence

A sequence of PhysiCell snapshots.

By default, only the simulation ID, index, and time are recorded for each PhysiCellSnapshot in the sequence.
To include any of `cells`, `substrates`, `mesh`, `attachments`, `spring_attachments`, or `neighbors`, pass in the corresponding keyword argument as `true` (see below).

# Fields
- `simulation_id::Int`: The ID of the simulation.
- `snapshots::Vector{PhysiCellSnapshot}`: A vector of PhysiCell snapshots.
- `cell_type_to_name_dict::Dict{Int, String}`: A dictionary mapping cell type IDs to cell type names.
- `labels::Vector{String}`: A vector of cell data labels.
- `substrate_names::Vector{String}`: A vector of substrate names.

# Examples
```julia
sequence = PhysiCellSequence(1; include_cells=true, include_substrates=true) # loads cell and substrate data for simulation ID 1
sequence = PhysiCellSequence(simulation; include_attachments=true, include_spring_attachments=true) # loads attachment data for a Simulation object
sequence = PhysiCellSequence(1; include_mesh=true, include_neighbors=true) # loads mesh and neighbor data for simulation ID 1
```
"""
struct PhysiCellSequence <: AbstractPhysiCellSequence
    simulation_id::Int
    snapshots::Vector{PhysiCellSnapshot}
    cell_type_to_name_dict::Dict{Int,String}
    labels::Vector{String}
    substrate_names::Vector{String}
end

function PhysiCellSequence(simulation_id::Integer;
    include_cells::Bool=false,
    include_substrates::Bool=false,
    include_mesh::Bool=false,
    include_attachments::Bool=false,
    include_spring_attachments::Bool=false,
    include_neighbors::Bool=false)

    path_to_xml = pathToOutputXML(simulation_id, :initial)
    cell_type_to_name_dict = cellTypeToNameDict(path_to_xml)
    if isempty(cell_type_to_name_dict)
        println("Could not find cell type information in $path_to_xml. This means that there is no initial.xml file, possibly due to pruning. Returning missing.")
        return missing
    end
    labels = cellLabels(path_to_xml)
    substrate_names = include_substrates ? substrateNames(path_to_xml) : String[]
    index_to_snapshot = index -> PhysiCellSnapshot(simulation_id, index, labels, substrate_names;
                                                   include_cells=include_cells,
                                                   cell_type_to_name_dict=cell_type_to_name_dict,
                                                   include_substrates=include_substrates,
                                                   include_mesh=include_mesh,
                                                   include_attachments=include_attachments,
                                                   include_spring_attachments=include_spring_attachments,
                                                   include_neighbors=include_neighbors)

    snapshots = PhysiCellSnapshot[]
    index = 0
    while isfile(pathToOutputXML(simulation_id, index))
        push!(snapshots, index_to_snapshot(index))
        index += 1
    end
    return PhysiCellSequence(simulation_id, snapshots, cell_type_to_name_dict, labels, substrate_names)
end

PhysiCellSequence(simulation::Simulation; kwargs...) = PhysiCellSequence(simulation.id; kwargs...)

function Base.show(io::IO, ::MIME"text/plain", sequence::PhysiCellSequence)
    println(io, "PhysiCellSequence (SimID=$(sequence.simulation_id))")
    println(io, "  #Snapshots: $(length(sequence.snapshots))")
    println(io, "  Cell Types: $(join(values(sequence.cell_type_to_name_dict), ", "))")
    println(io, "  Substrates: $(join(sequence.substrate_names, ", "))")
    loadMesh!(sequence.snapshots[1])
    println(io, "  Mesh: $(meshInfo(sequence))")
end

"""
    pathToOutputFolder(simulation_id::Integer)

Return the path to the output folder for a PhysiCell simulation.
"""
pathToOutputFolder(simulation_id::Integer) = joinpath(trialFolder(Simulation, simulation_id), "output")

"""
    pathToOutputFileBase(simulation_id::Integer, index::Union{Integer,Symbol})

Return the path to the output files for a snapshot of a PhysiCell simulation, i.e., everything but the file extension.
"""
pathToOutputFileBase(simulation_id::Integer, index::Union{Integer,Symbol}) = joinpath(pathToOutputFolder(simulation_id), indexToFilename(index))

"""
    pathToOutputFileBase(snapshot::PhysiCellSnapshot)

Return the path to the output files for a snapshot of a PhysiCell simulation, i.e., everything but the file extension.
"""
pathToOutputFileBase(snapshot::PhysiCellSnapshot) = pathToOutputFileBase(snapshot.simulation_id, snapshot.index)

"""
    pathToOutputXML(simulation_id::Integer, index::Union{Integer,Symbol}=:initial)

Return the path to the XML output file for a snapshot of a PhysiCell simulation.
Can also pass in a `Simulation` object for the first argument.
"""
pathToOutputXML(simulation_id::Integer, index::Union{Integer,Symbol}=:initial) = "$(pathToOutputFileBase(simulation_id, index)).xml"

pathToOutputXML(simulation::Simulation, index::Union{Integer,Symbol}=:initial) = pathToOutputXML(simulation.id, index)

"""
    pathToOutputXML(snapshot::PhysiCellSnapshot)

Return the path to the XML output file for a snapshot of a PhysiCell simulation.
"""
pathToOutputXML(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot.simulation_id, snapshot.index)

"""
    cellLabels(simulation::Simulation)

Return the labels from the XML file for a PhysiCell simulation, i.e., the names of the cell data fields.

# Arguments
- `simulation`: The simulation object. Can also use the simulation ID, an [`AbstractPhysiCellSequence`](@ref), `XMLDocument`, or the path to the XML file (`String`).
"""
function cellLabels(path_to_file::String)
    if !isfile(path_to_file)
        return String[]
    end
    xml_doc = parse_file(path_to_file)
    labels = cellLabels(xml_doc)
    free(xml_doc)
    return labels
end

function cellLabels(xml_doc::XMLDocument)
    labels = String[]
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "labels"]
    labels_element = retrieveElement(xml_doc, xml_path; required=true)

    for label in child_elements(labels_element)
        label_name = content(label)
        label_ind_width = attribute(label, "size"; required=true) |> x -> parse(Int, x)
        if label_ind_width > 1
            label_name = [label_name * "_$i" for i in 1:label_ind_width]
            append!(labels, label_name)
        else
            if label_name == "elapsed_time_in_phase" && label_name in labels
                label_name = "elapsed_time_in_phase_2" #! hack to get around a MultiCellDS duplicate?
            end
            push!(labels, label_name)
        end
    end
    return labels
end

cellLabels(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot) |> cellLabels
cellLabels(sequence::PhysiCellSequence) = sequence.labels
cellLabels(simulation_id::Integer) = cellLabels(pathToOutputXML(simulation_id, :initial))
cellLabels(simulation::Simulation) = cellLabels(simulation.id)

"""
    cellTypeToNameDict(simulation::Simulation)

Return a dictionary mapping cell type IDs to cell type names from the simulation.

# Arguments
- `simulation`: The simulation object. Can also use the simulation ID, an [`AbstractPhysiCellSequence`](@ref), `XMLDocument`, or the path to the XML file (`String`).
"""
function cellTypeToNameDict(path_to_file::String)
    if !isfile(path_to_file)
        return Dict{Int,String}()
    end
    xml_doc = parse_file(path_to_file)
    cell_type_to_name_dict = cellTypeToNameDict(xml_doc)
    free(xml_doc)
    return cell_type_to_name_dict
end

function cellTypeToNameDict(xml_doc::XMLDocument)
    cell_type_to_name_dict = Dict{Int, String}()
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "cell_types"]
    cell_types_element = retrieveElement(xml_doc, xml_path; required=true)

    for cell_type_element in child_elements(cell_types_element)
        cell_type_id = attribute(cell_type_element, "ID"; required=true) |> x -> parse(Int, x)
        cell_type_name = content(cell_type_element)
        cell_type_to_name_dict[cell_type_id] = cell_type_name
    end
    return cell_type_to_name_dict
end

cellTypeToNameDict(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot) |> cellTypeToNameDict
cellTypeToNameDict(sequence::PhysiCellSequence) = sequence.cell_type_to_name_dict
cellTypeToNameDict(simulation_id::Integer) = cellTypeToNameDict(pathToOutputXML(simulation_id, :initial))
cellTypeToNameDict(simulation::Simulation) = cellTypeToNameDict(simulation.id)

"""
    substrateNames(simulation::Simulation)

Return the names of the substrates from the simulation.

# Arguments
- `simulation`: The simulation object. Can also use the simulation ID, an [`AbstractPhysiCellSequence`](@ref), `XMLDocument`, or the path to the XML file (`String`).
"""
function substrateNames(path_to_file::String)
    if !isfile(path_to_file)
        return String[]
    end
    xml_doc = parse_file(path_to_file)
    substrate_names = substrateNames(xml_doc)
    free(xml_doc)
    return substrate_names
end

function substrateNames(xml_doc::XMLDocument)
    xml_path = ["microenvironment", "domain", "variables"]
    variables_element = retrieveElement(xml_doc, xml_path; required=true)
    substrate_dict = Dict{Int, String}()
    for element in child_elements(variables_element)
        if name(element) != "variable"
            continue
        end
        variable_id = attribute(element, "ID"; required=true) |> x -> parse(Int, x)
        substrate_name = attribute(element, "name"; required=true)
        substrate_dict[variable_id] = substrate_name
    end
    substrate_names = String[]
    for i in (substrate_dict |> keys |> collect |> sort)
        push!(substrate_names, substrate_dict[i])
    end
    return substrate_names
end

substrateNames(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot) |> substrateNames
substrateNames(sequence::PhysiCellSequence) = sequence.substrate_names
substrateNames(simulation_id::Integer) = substrateNames(pathToOutputXML(simulation_id, :initial))
substrateNames(simulation::Simulation) = substrateNames(simulation.id)

"""
    _loadCells!(cells::DataFrame, filepath_base::String, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])

Internal function to load cell data into a DataFrame associated with an [`AbstractPhysiCellSequence`](@ref) object.
"""
function _loadCells!(cells::DataFrame, filepath_base::String, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    if !isempty(cells)
        return
    end

    if isempty(labels) || isempty(cell_type_to_name_dict)
        xml_doc = parse_file("$(filepath_base).xml")
        if isempty(labels)
            labels = cellLabels(xml_doc)
        end
        if isempty(cell_type_to_name_dict)
            cell_type_to_name_dict = cellTypeToNameDict(xml_doc)
        end
        free(xml_doc)

        #! confirm that these were both found
        @assert !isempty(labels) && !isempty(cell_type_to_name_dict) "Could not find cell type information and/or labels in $(filepath_base).xml"
    end

    mat_file = "$(filepath_base)_cells.mat"
    if !isfile(mat_file)
        println("When loading cells, could not find file $mat_file. Returning missing.")
        return missing
    end
    A = matread(mat_file)["cell"]
    conversion_dict = Dict("ID" => Int, "dead" => Bool, "cell_type" => Int)
    for (label, row) in zip(labels, eachrow(A))
        if label in keys(conversion_dict)
            cells[!, label] = convert.(conversion_dict[label], row)
        else
            cells[!, label] = row
        end
    end
    cells[!, :cell_type_name] = [cell_type_to_name_dict[ct] for ct in cells[!, :cell_type]]
    return
end

"""
    loadCells!(S::AbstractPhysiCellSequence[, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[]])

Load the cell data for a PhysiCell simulation into an [`AbstractPhysiCellSequence`](@ref) object.

If the `cell_type_to_name_dict` and `labels` are not provided, they will be loaded from the XML file.
Users do not need to compute and pass these in.

# Arguments
- `S::AbstractPhysiCellSequence`: The sequence or snapshot to load the cell data into.
- `cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}()`: A dictionary mapping cell type IDs to cell type names. If not provided, it will be loaded from the XML file.
- `labels::Vector{String}=String[]`: A vector of cell data labels. If not provided, they will be loaded from the XML file.

# Examples
```julia
simulation = Simulation(1)
sequence = PhysiCellSequence(simulation) # does not load cell data without setting `PhysiCellSequence(simulation; include_cells=true)`
loadCells!(sequence)
```
"""
function loadCells!(snapshot::PhysiCellSnapshot, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    _loadCells!(snapshot.cells, pathToOutputFileBase(snapshot), cell_type_to_name_dict, labels)
end

function loadCells!(sequence::PhysiCellSequence)
    cell_type_to_name_dict = cellTypeToNameDict(sequence)
    labels = cellLabels(sequence)
    for snapshot in sequence.snapshots
        loadCells!(snapshot, cell_type_to_name_dict, labels)
    end
end

"""
    _loadSubstrates!(substrates::DataFrame, filepath_base::String, substrate_names::Vector{String}=String[])

Internal function to load substrate data into a DataFrame associated with an [`AbstractPhysiCellSequence`](@ref) object.
"""
function _loadSubstrates!(substrates::DataFrame, filepath_base::String, substrate_names::Vector{String})
    if !isempty(substrates)
        return
    end

    if isempty(substrate_names)
        substrate_names = "$(filepath_base).xml" |> substrateNames
        @assert !isempty(substrate_names) "Could not find substrate names in $(filepath_base).xml"
    end

    mat_file = "$(filepath_base)_microenvironment0.mat"
    if !isfile(mat_file)
        println("When loading substrates, could not find file $mat_file. Returning missing.")
        return missing
    end
    A = matread(mat_file) |> values |> first #! julia seems to read in the multiscale_microenvironment and assign the key multiscale_microenvironmen (note the missing 't'); do this to make sure we get the data
    col_names = [:x; :y; :z; :volume; substrate_names]
    for (col_name, row) in zip(col_names, eachrow(A))
        substrates[!, col_name] = row
    end
end

"""
    loadSubstrates!(S::AbstractPhysiCellSequence[, substrate_names::Vector{String}=String[]])

Load the substrate data for a PhysiCell simulation into an [`AbstractPhysiCellSequence`](@ref) object.

If the `substrate_names` are not provided, they will be loaded from the XML file.
Users do not need to compute and pass these in.

# Arguments
- `S::AbstractPhysiCellSequence`: The sequence or snapshot to load the substrate data into.
- `substrate_names::Vector{String}=String[]`: The names of the substrates to load. If not provided, they will be loaded from the XML file.
"""
function loadSubstrates!(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[])
    _loadSubstrates!(snapshot.substrates, pathToOutputFileBase(snapshot), substrate_names)
end

function loadSubstrates!(sequence::PhysiCellSequence)
    for snapshot in sequence.snapshots
        loadSubstrates!(snapshot, sequence.substrate_names)
    end
end

"""
    _loadMesh!(mesh::Dict{String, Vector{Float64}}, xml_doc::XMLDocument)

Internal function to load mesh data into a dictionary associated with an [`AbstractPhysiCellSequence`](@ref) object.
"""
function _loadMesh!(mesh::Dict{String, Vector{Float64}}, xml_doc::XMLDocument)
    if !isempty(mesh)
        return
    end
    xml_path = ["microenvironment", "domain", "mesh"]
    mesh_element = retrieveElement(xml_doc, xml_path; required=true)
    mesh["bounding_box"] = parse.(Float64, split(content(find_element(mesh_element, "bounding_box")), " "))
    for tag in ["x_coordinates", "y_coordinates", "z_coordinates"]
        coord_element = find_element(mesh_element, tag)
        mesh[string(tag[1])] = parse.(Float64, split(content(coord_element), attribute(coord_element, "delimiter"; required=true)))
    end
end

"""
    loadMesh!(S::AbstractPhysiCellSequence)

Load the mesh data for a PhysiCell simulation into an [`AbstractPhysiCellSequence`](@ref) object.

# Arguments
- `S::AbstractPhysiCellSequence`: The sequence or snapshot to load the mesh data into.
"""
function loadMesh!(snapshot::PhysiCellSnapshot)
    path_to_file = pathToOutputXML(snapshot)
    @assert isfile(path_to_file) "Could not find file $path_to_file. However, snapshot required this file to be created."
    xml_doc = parse_file(path_to_file)
    _loadMesh!(snapshot.mesh, xml_doc)
    free(xml_doc)
    return
end

function loadMesh!(sequence::PhysiCellSequence)
    for snapshot in sequence.snapshots
        loadMesh!(snapshot)
    end
end

"""
    meshInfo(S::AbstractPhysiCellSequence)

Return a string describing the mesh for an [`AbstractPhysiCellSequence`](@ref) object.
"""
function meshInfo(snapshot::PhysiCellSnapshot)
    mesh = snapshot.mesh
    grid_size = [length(mesh[k]) for k in ["x", "y", "z"] if length(mesh[k]) > 1]
    domain_size = [[mesh[k][1], mesh[k][end]] + 0.5*(mesh[k][2] - mesh[k][1]) * [-1, 1] for k in ["x", "y", "z"] if length(mesh[k]) > 1]
    return "$(join(grid_size, " x ")) grid on $(join(domain_size, " x "))"
end

meshInfo(sequence::PhysiCellSequence) = meshInfo(sequence.snapshots[1])

"""
    _loadGraph!(G::MetaGraph, path_to_txt_file::String)

Load a graph from a text file into a `MetaGraph`.

Users should use `loadGraph!` with an [`AbstractPhysiCellSequence`](@ref) object instead of this function directly.`
"""
function _loadGraph!(G::MetaGraph, path_to_txt_file::String)
    if nv(G) > 0 #! If the graph is already loaded, do nothing
        return
    end
    if !isfile(path_to_txt_file)
        println("When loading graph, could not find file $path_to_txt_file. Returning missing.")
        return missing
    end
    readPhysiCellGraph!(G, path_to_txt_file)
end

"""
    loadGraph!(S::AbstractPhysiCellSequence, graph::Symbol)

Load a graph for a snapshot or sequence into a MetaGraph(s).

# Arguments
- `S::AbstractPhysiCellSequence`: The [`AbstractPhysiCellSequence`](@ref) object to load the graph into.
- `graph`: The type of graph to load (must be one of `:attachments`, `:spring_attachments`, or `:neighbors`). Can also be a string.
"""
function loadGraph!(snapshot::PhysiCellSnapshot, graph::Symbol)
    @assert graph in [:attachments, :spring_attachments, :neighbors] "Graph must be one of [:attachments, :spring_attachments, :neighbors]"
    if graph == :attachments
        path_to_txt_file = pathToOutputFileBase(snapshot) * "_attached_cells_graph.txt"
    elseif graph == :spring_attachments
        path_to_txt_file = pathToOutputFileBase(snapshot) * "_spring_attached_cells_graph.txt"
    elseif graph == :neighbors
        path_to_txt_file = pathToOutputFileBase(snapshot) * "_cell_neighbor_graph.txt"
    end
    _loadGraph!(getfield(snapshot, graph), path_to_txt_file)
end

function loadGraph!(sequence::PhysiCellSequence, graph::Symbol)
    for snapshot in sequence.snapshots
        loadGraph!(snapshot, graph)
    end
end

loadGraph!(S::AbstractPhysiCellSequence, graph::String) = loadGraph!(S, Symbol(graph))

"""
    graphInfo(g::MetaGraph)

Return a string describing the graph.

Used for printing the graph information in the `show` function.
"""
function graphInfo(g::MetaGraph)
    return "directed graph with $(nv(g)) vertices and $(ne(g)) edges"
end

"""
    cellDataSequence(simulation_id::Integer, labels::Vector{String}; include_dead::Bool=false, include_cell_type_name::Bool=false)

Return an [`AgentDict`](@ref) where the keys are cell IDs from the PhysiCell simulation and the values are NamedTuples containing the time and the values of the specified labels for that cell.

For scalar values, such as `volume`, the values are in a length `N` vector, where `N` is the number of snapshots in the simulation.
In the case of a label that has multiple columns, such as `position`, the values are concatenated into a length(snapshots) x number of columns array.
Note: If doing multiple calls to this function, it is recommended to use the `PhysiCellSequence` object so that all the data is loaded one time instead of once per call.

# Arguments
- `simulation_id::Integer`: The ID of the PhysiCell simulation. Alternatively, can be a `Simulation` object or a `PhysiCellSequence` object.
- `labels::Vector{String}`: The labels to extract from the cell data. If a label has multiple columns, such as `position`, the columns are concatenated into a single array. Alternatively, a single label string can be passed.
- `include_dead::Bool=false`: Whether to include dead cells in the data.
- `include_cell_type_name::Bool=false`: Whether to include the cell type name in the data. Equivalent to including `\"cell_type_name\"` in `labels`.

# Examples
```
data = cellDataSequence(sequence, ["position", "elapsed_time_in_phase"]; include_dead=true, include_cell_type_name=true)
data[1] # the data for cell with ID 1
data[1].position # an Nx3 array of the cell's position over time
data[1].elapsed_time_in_phase # an Nx1 array of the cell's elapsed time in phase over time
data[1].cell_type_name # an Nx1 array of the cell type name of the first cell over time
```
"""
function cellDataSequence(simulation_id::Integer, labels::Vector{String}; kwargs...)
    sequence = PhysiCellSequence(simulation_id)
    return cellDataSequence(sequence, labels; kwargs...)
end

function cellDataSequence(simulation_id::Integer, label::String; kwargs...)
    return cellDataSequence(simulation_id, [label]; kwargs...)
end

function cellDataSequence(simulation::Simulation, labels::Vector{String}; kwargs...)
    sequence = PhysiCellSequence(simulation)
    return cellDataSequence(sequence, labels; kwargs...)
end

function cellDataSequence(simulation::Simulation, label::String; kwargs...)
    return cellDataSequence(simulation, [label]; kwargs...)
end

function cellDataSequence(sequence::PhysiCellSequence, label::String; kwargs...)
    return cellDataSequence(sequence, [label]; kwargs...)
end

function cellDataSequence(sequence::PhysiCellSequence, labels::Vector{String}; include_dead::Bool=false, include_cell_type_name::Bool=false)
    loadCells!(sequence)
    cell_features = cellLabels(sequence)
    label_features = Symbol[]
    temp_dict = Dict{Symbol, Vector{Symbol}}()
    for label in labels
        if label in cell_features
            L = Symbol(label)
            push!(label_features, L)
            temp_dict[L] = [L]
        else
            index = 1
            while "$(label)_$(index)" in cell_features
                index += 1
            end
            @assert index > 1 "Label $label not found in cell data"
            new_labels = [Symbol("$(label)_$(i)") for i in 1:(index-1)]
            append!(label_features, new_labels)
            temp_dict[Symbol(label)] = new_labels
        end
    end
    labels = Symbol.(labels)
    if include_cell_type_name && !(:cell_type_name in labels)
        push!(labels, :cell_type_name)
        push!(label_features, :cell_type_name)
        temp_dict[:cell_type_name] = [:cell_type_name]
    end
    types = eltype.(eachcol(sequence.snapshots[1].cells)[label_features])
    data = Dict{Int, NamedTuple{(:time, label_features...), Tuple{Vector{Float64}, [Vector{type} for type in types]...}}}()
    for snapshot in sequence.snapshots
        for row in eachrow(snapshot.cells)
            if !include_dead && row[:dead]
                continue
            end
            if row.ID in keys(data)
                push!(data[row.ID].time, snapshot.time)
                for label_feature in label_features
                    push!(data[row.ID][label_feature], row[label_feature])
                end
            else
                data[row.ID] = NamedTuple{(:time, label_features...)}([[snapshot.time], [[row[label_feature]] for label_feature in label_features]...])
            end
        end
    end

    if all(length.(values(temp_dict)) .== 1)
        return AgentDict(data)
    end
    C(v, label) = begin #! Concatenation of columns that belong together
        if length(temp_dict[label]) == 1
            return v[temp_dict[label][1]]
        end
        return hcat(v[temp_dict[label]]...)
    end
    return [ID => NamedTuple{(:time, labels...)}([[v.time]; [C(v,label) for label in labels]]) for (ID, v) in data] |> AgentDict
end

"""
    getCellDataSequence(args...; kwargs...)

Deprecated alias for [`cellDataSequence`](@ref). Use `cellDataSequence` instead.
"""
function getCellDataSequence(args...; kwargs...)
    Base.depwarn("`getCellDataSequence` is deprecated. Use `cellDataSequence` instead.", :getCellDataSequence; force=true)
    return cellDataSequence(args...; kwargs...)
end
