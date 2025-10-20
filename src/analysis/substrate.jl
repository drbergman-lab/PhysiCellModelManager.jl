using Statistics

@compat public AverageSubstrateTimeSeries, ExtracellularSubstrateTimeSeries

"""
    VoxelWeights

A struct to hold the voxel weights for a PhysiCell simulation.
# Fields
- `use_weights::Bool`: Whether to use weights for the voxel volumes. If all voxel volumes are the same, this is set to `false`.
- `weights::Vector{Real}`: The weights for the voxel volumes.
- `weight_total::Real`: The total weight of the voxel volumes.
"""
struct VoxelWeights
    use_weights::Bool
    weights::Vector{Real}
    weight_total::Real

    function VoxelWeights(weights::AbstractVector{<:Real})
        use_weights = length(unique(weights)) != 1
        weight_total = sum(weights)
        return new(use_weights, weights, weight_total)
    end

    function VoxelWeights(snapshot::PhysiCellSnapshot)
        loadSubstrates!(snapshot)
        weights = snapshot.substrates[!, :volume]
        return VoxelWeights(weights)
    end
end

"""
    averageSubstrate(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[], voxel_weights::VoxelWeights=VoxelWeights(snapshot))

Compute the average substrate concentrations for every substrate in a PhysiCell snapshot.

The voxel volumes are used as weights if they are not all the same.

# Arguments
- `snapshot::PhysiCellSnapshot`: The snapshot to analyze.
- `substrate_names::Vector{String}`: The names of the substrates in the simulation. If not provided, it is read from the snapshot files.
- `voxel_weights::VoxelWeights`: The voxel weights to use. If not provided, it is computed from the snapshot.

# Returns
- `data::Dict{String, Real}`: A dictionary mapping substrate names to their average concentrations.
"""
function averageSubstrate(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[], voxel_weights::VoxelWeights=VoxelWeights(snapshot))
    loadSubstrates!(snapshot, substrate_names)
    data = Dict{String, Real}()

    if voxel_weights.use_weights
        mean_fn = x -> (x .* voxel_weights.weights |> sum) / total_weight
    else
        mean_fn = mean
    end

    for substrate_name in substrate_names
        data[substrate_name] = mean_fn(snapshot.substrates[!, substrate_name])
    end
    return data
end

"""
    AverageSubstrateTimeSeries

A struct to hold the average substrate concentrations over time for a PhysiCell simulation.

Constructed using `AverageSubstrateTimeSeries(x)` where `x` is any of the following: `Integer` (simulation ID), `PhysiCellSequence`, or `Simulation`.

# Fields
- `simulation_id::Int`: The ID of the PhysiCell simulation.
- `time::Vector{Real}`: The time points at which the snapshots were taken.
- `substrate_concentrations::Dict{String, Vector{Real}}`: A dictionary mapping substrate names to vectors of their average concentrations over time.

# Example
```julia
asts = PhysiCellModelManager.AverageSubstrateTimeSeries(1) # Load average substrate time series for Simulation 1
asts.time # Get the time points
asts["time"] # alternative way to get the time points
asts["oxygen"] # Get the oxygen concentration over time
```
"""
struct AverageSubstrateTimeSeries
    simulation_id::Int
    time::Vector{Real}
    substrate_concentrations::Dict{String, Vector{Real}}
end

function AverageSubstrateTimeSeries(sequence::PhysiCellSequence)
    time = [snapshot.time for snapshot in sequence.snapshots]
    substrate_concentrations = Dict{String, Vector{Real}}()
    substrate_names = substrateNames(sequence)
    for substrate_name in substrate_names
        substrate_concentrations[substrate_name] = zeros(Float64, length(time))
    end
    voxel_weights = VoxelWeights(sequence.snapshots[1])
    for (i, snapshot) in enumerate(sequence.snapshots)
        snapshot_substrate_concentrations = averageSubstrate(snapshot, substrate_names, voxel_weights)
        for substrate_name in keys(snapshot_substrate_concentrations)
            substrate_concentrations[substrate_name][i] = snapshot_substrate_concentrations[substrate_name]
        end
    end
    return AverageSubstrateTimeSeries(sequence.simulation_id, time, substrate_concentrations)
end

function AverageSubstrateTimeSeries(simulation_id::Integer)
    print("Computing average substrate time series for Simulation $simulation_id...")
    simulation_folder = trialFolder(Simulation, simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "average_substrate_time_series.csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        asts = AverageSubstrateTimeSeries(simulation_id, df.time, Dict{String, Vector{Real}}(name => df[!, Symbol(name)] for name in names(df) if name != "time"))
    else
        sequence = PhysiCellSequence(simulation_id; include_cells=false, include_substrates=true)
        if ismissing(sequence)
            return missing
        end
        mkpath(path_to_summary)
        asts = AverageSubstrateTimeSeries(sequence)
        df = DataFrame(time=asts.time)
        for (name, concentrations) in pairs(asts.substrate_concentrations)
            df[!, Symbol(name)] = concentrations
        end
        CSV.write(path_to_file, df)
    end
    println("done.")
    return asts
end

AverageSubstrateTimeSeries(simulation::Simulation) = AverageSubstrateTimeSeries(simulation.id)

AverageSubstrateTimeSeries(pcmm_output::PCMMOutput{Simulation}) = AverageSubstrateTimeSeries(pcmm_output.trial)

function Base.getindex(asts::AverageSubstrateTimeSeries, name::String)
    if name in keys(asts.substrate_concentrations)
        return asts.substrate_concentrations[name]
    elseif name == "time"
        return asts.time
    else
        throw(ArgumentError("Invalid substrate name: $name"))
    end
end

function Base.show(io::IO, ::MIME"text/plain", asts::AverageSubstrateTimeSeries)
    println(io, "AverageSubstrateTimeSeries for Simulation $(asts.simulation_id)")
    println(io, "  Time: $(formatTimeRange(asts.time))")
    println(io, "  Substrates: $(join(keys(asts.substrate_concentrations), ", "))")
end

"""
    averageExtracellularSubstrate(snapshot::PhysiCellSnapshot, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), substrate_names::Vector{String}=String[], labels::Vector{String}=String[]; include_dead::Bool=false)

Compute the average extracellular substrate concentrations for each cell type in a PhysiCell snapshot.

# Arguments
- `snapshot::PhysiCellSnapshot`: The snapshot to analyze.
- `cell_type_to_name_dict::Dict{Int, String}`: A dictionary mapping cell type IDs to their names. If not provided, it is read from the snapshot files.
- `substrate_names::Vector{String}`: The names of the substrates in the simulation. If not provided, it is read from the snapshot files.
- `labels::Vector{String}`: The labels to use for the cells. If not provided, it is read from the snapshot files.

# Keyword Arguments
- `include_dead::Bool`: Whether to include dead cells in the analysis (default is `false`).

# Returns
- `Dict{String, Dict{String, Real}}`: A dictionary mapping cell type names to dictionaries mapping substrate names to their average concentrations.

That is, if `aes` is the output of this function, then `aes["cell_type_name"]["substrate_name"]` is the average concentration of `substrate_name` for cells of type `cell_type_name` in the snapshot.
"""
function averageExtracellularSubstrate(snapshot::PhysiCellSnapshot, cell_type_to_name_dict::Dict{Int,String}=Dict{Int,String}(), substrate_names::Vector{String}=String[], labels::Vector{String}=String[]; include_dead::Bool=false)
    #! if any of the necessary data is missing, return missing
    loadCells!(snapshot, cell_type_to_name_dict, labels) |> ismissing && return missing
    loadSubstrates!(snapshot, substrate_names) |> ismissing && return missing
    loadMesh!(snapshot) |> ismissing && return missing

    cells = snapshot.cells
    substrates = snapshot.substrates
    mesh = snapshot.mesh

    aes = Dict{String, Dict{String, Real}}()
    cells_to_keep = include_dead ? deepcopy(cells) : cells[.!cells.dead, :]
    for cell_type_name in values(cell_type_to_name_dict)
        cell_type_cells = cells_to_keep[cells_to_keep.cell_type_name .== cell_type_name, :]

        voxel_inds = computeVoxelIndices(cell_type_cells, mesh)
        aes[cell_type_name] = Dict{String, Real}()
        for substrate_name in substrate_names
            aes[cell_type_name][substrate_name] = substrates[voxel_inds, substrate_name] |> mean
        end
    end
    return aes
end

"""
    computeVoxelSubscripts(cells::DataFrame, mesh::Dict{String, Vector{Float64}})

Compute the voxel subscripts (1-nx, 1-ny, 1-nz) for a set of cells in a PhysiCell simulation.
"""
function computeVoxelSubscripts(cells::DataFrame, mesh::Dict{String, Vector{Float64}})
    voxel_subs = Vector{Tuple{Int, Int, Int}}()
    x, y, z = cells[!, [:position_1, :position_2, :position_3]] |> eachcol

    nearest_index(c, v) = (c .- v[1]) / (v[2] - v[1]) .|> round .|> Int .|> x -> x.+1
    is = length(mesh["x"]) == 1 ? fill(1, (length(x),)) : nearest_index(x, mesh["x"])
    js = length(mesh["y"]) == 1 ? fill(1, (length(x),)) : nearest_index(y, mesh["y"])
    ks = length(mesh["z"]) == 1 ? fill(1, (length(x),)) : nearest_index(z, mesh["z"])
    voxel_subs = [(i, j, k) for (i, j, k) in zip(is, js, ks)]
    return voxel_subs
end

"""
    computeVoxelIndices(cells::DataFrame, mesh::Dict{String, Vector{Float64}})

Compute the voxel (linear) indices (1-nx*ny*nz) for a set of cells in a PhysiCell simulation.
"""
function computeVoxelIndices(cells::DataFrame, mesh::Dict{String, Vector{Float64}})
    voxel_subs = computeVoxelSubscripts(cells, mesh)
    nx, ny = length(mesh["x"]), length(mesh["y"])
    voxel_inds = [i + nx * (j-1 + ny * (k-1)) for (i, j, k) in voxel_subs]
    return voxel_inds
end

"""
    ExtracellularSubstrateTimeSeries

A struct to hold the mean extracellular substrate concentrations per cell type over time for a PhysiCell simulation.

# Fields
- `simulation_id::Int`: The ID of the PhysiCell simulation.
- `time::Vector{Real}`: The time points at which the snapshots were taken.
- `data::Dict{String, Dict{String, Vector{Real}}}`: A dictionary mapping cell type names to dictionaries mapping substrate names to vectors of their average concentrations over time.

# Example
```julia
ests = PhysiCellModelManager.ExtracellularSubstrateTimeSeries(1) # Load extracellular substrate time series for Simulation 1
ests.time # Get the time points
ests["cancer"]["oxygen"] # Get the oxygen concentration over time for the cancer cell type

ests = PhysiCellModelManager.ExtracellularSubstrateTimeSeries(simulation; include_dead=true) # Load extracellular substrate time series for a Simulation object, including dead cells
ests["time"] # Alternate way to get the time points
ests["cd8"]["IFNg"] # Get the interferon gamma concentration over time for the CD8 cell type

ests = PhysiCellModelManager.ExtracellularSubstrateTimeSeries(sequence) # Load extracellular substrate time series for a PhysiCellSequence object
```
"""
struct ExtracellularSubstrateTimeSeries
    simulation_id::Int
    time::Vector{Real}
    data::Dict{String,Dict{String,Vector{Real}}}
end

function ExtracellularSubstrateTimeSeries(sequence::PhysiCellSequence; include_dead::Bool=false)
    time = [snapshot.time for snapshot in sequence.snapshots]
    data = Dict{String, Dict{String, Vector{Real}}}()
    cell_type_to_name_dict = sequence.cell_type_to_name_dict
    substrate_names = substrateNames(sequence)
    for (i, snapshot) in enumerate(sequence.snapshots)
        snapshot_data = averageExtracellularSubstrate(snapshot, cell_type_to_name_dict, substrate_names, sequence.labels; include_dead=include_dead)
        for cell_type_name in keys(snapshot_data)
            if !haskey(data, cell_type_name)
                data[cell_type_name] = Dict{String, Vector{Real}}()
            end
            for substrate_name in keys(snapshot_data[cell_type_name])
                if !(substrate_name in keys(data[cell_type_name]))
                    data[cell_type_name][substrate_name] = zeros(Float64, length(time))
                end
                data[cell_type_name][substrate_name][i] = snapshot_data[cell_type_name][substrate_name]
            end
        end
    end
    return ExtracellularSubstrateTimeSeries(sequence.simulation_id, time, data)
end

function ExtracellularSubstrateTimeSeries(simulation_id::Integer; include_dead::Bool=false)
    print("Computing extracellular substrate time series for Simulation $simulation_id...")
    simulation_folder = trialFolder(Simulation, simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "extracellular_substrate_time_series$(include_dead ? "_include_dead" : "").csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        data = Dict{String,Dict{String,Vector{Real}}}()
        for name in names(df)
            if name == "time"
                continue
            end
            cell_type_name, substrate_name = split(name, " AND ")
            if !haskey(data, cell_type_name)
                data[cell_type_name] = Dict{String, Vector{Real}}()
            end
            data[cell_type_name][substrate_name] = df[!, name]
        end
        ests = ExtracellularSubstrateTimeSeries(simulation_id, df.time, data)
    else
        sequence = PhysiCellSequence(simulation_id; include_cells=true, include_substrates=true, include_mesh=true)
        if ismissing(sequence)
            return missing
        end
        mkpath(path_to_summary)
        ests = ExtracellularSubstrateTimeSeries(sequence; include_dead=include_dead)
        df = DataFrame(time=ests.time)
        for (cell_type_name, data) in pairs(ests.data)
            for (substrate_name, concentrations) in pairs(data)
                df[!, Symbol(cell_type_name * " AND " * substrate_name)] = concentrations
            end
        end
        CSV.write(path_to_file, df)
    end
    println("done.")
    return ests
end

ExtracellularSubstrateTimeSeries(simulation::Simulation; kwargs...) = ExtracellularSubstrateTimeSeries(simulation.id; kwargs...)

ExtracellularSubstrateTimeSeries(pcmm_output::PCMMOutput{Simulation}; kwargs...) = ExtracellularSubstrateTimeSeries(pcmm_output.trial; kwargs...)

function Base.getindex(ests::ExtracellularSubstrateTimeSeries, name::String)
    if name in keys(ests.data)
        return ests.data[name]
    elseif name == "time"
        return ests.time
    else
        throw(ArgumentError("Invalid cell type name: $name"))
    end
end

function Base.show(io::IO, ::MIME"text/plain", ests::ExtracellularSubstrateTimeSeries)
    println(io, "ExtracellularSubstrateTimeSeries for Simulation $(ests.simulation_id)")
    println(io, "  Time: $(formatTimeRange(ests.time))")
    substrates = reduce(hcat, [keys(v) for v in values(ests.data)]) |> unique
    println(io, "  Substrates: $(join(substrates, ", "))")
end