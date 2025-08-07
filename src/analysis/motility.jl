export motilityStatistics

"""
    _motilityStatistics(p[; direction=:any])

Compute the motility statistics for a single cell in the PhysiCell simulation.

Accounts for cell type transitions and computes the distance traveled, time spent, and mean speed for each cell type the given cell has taken on during the simulation.
The speed can be restricted to a specific direction (x, y, z) or calculated in any direction.
In either case, the distance is unsigned.

This function is used internally by [`motilityStatistics`](@ref).

# Returns
A `Dict{String, NamedTuple}` where each key is a cell type name visited by the cell and the value is a `NamedTuple` with fields `:time`, `:distance`, and `:speed`.
The values in this named tuple are the time, distance traveled, and mean speed for the cell in that cell type, i.e., all scalars.
"""
function _motilityStatistics(p; direction=:any)::Dict{String, NamedTuple}
    x, y, z = [col for col in eachcol(p.position)]
    cell_type_name = p.cell_type_name
    dx = x[2:end] .- x[1:end-1]
    dy = y[2:end] .- y[1:end-1]
    dz = z[2:end] .- z[1:end-1]
    if direction == :x
        dist_fn = (dx, _, _) -> abs(dx)
    elseif direction == :y
        dist_fn = (_, dy, _) -> abs(dy)
    elseif direction == :z
        dist_fn = (_, _, dz) -> abs(dz)
    elseif direction == :any
        dist_fn = (dx, dy, dz) -> sqrt(dx ^ 2 + dy ^ 2 + dz ^ 2)
    else
        error("Invalid direction: $direction")
    end
    type_change = cell_type_name[2:end] .!= cell_type_name[1:end-1]
    start_ind = 1
    cell_type_names = unique(cell_type_name)
    distance_dict = Dict{String, Float64}(zip(cell_type_names, zeros(Float64, length(cell_type_names))))
    time_dict = Dict{String, Float64}(zip(cell_type_names, zeros(Float64, length(cell_type_names))))
    while start_ind <= length(type_change)
        I = findfirst(type_change[start_ind:end]) #! from s to I, cell_type_name is constant. at I+1 it changes
        I = isnothing(I) ? length(type_change)+2-start_ind : I #! if the cell_type_name is constant till the end, set I to be at the end
        #! If start_ind = 1 (at start of sim) and I = 2 (so cell_type_name[3] != cell_type_name[2], meaning that for steps [1,2] cell_type_name is constnat), only use dx in stepping from 1->2 since somewhere in 2->3 the type changes. That is, use dx[1]
        distance_dict[cell_type_name[start_ind]] += sum(dist_fn.(dx[start_ind:I-1], dy[start_ind:I-1], dz[start_ind:I-1]))  #! only count distance travelled while remaining in the initial cell_type_name
        time_dict[cell_type_name[start_ind]] += p.time[start_ind+I-1] - p.time[start_ind] #! record time spent in this cell_type_name (note p.time is not diffs like dx and dy are, hence the difference in indices)
        start_ind += I #! advance the start to the first instance of a new cell_type_name
    end
    speed_dict = [k => distance_dict[k] / time_dict[k] for k in cell_type_names] |> Dict{String,Float64} #! convert to speed
    per_type_stats = Dict{String, NamedTuple}()
    for cell_type_name in cell_type_names
        per_type_stats[cell_type_name] = [:time=>time_dict[cell_type_name], :distance=>distance_dict[cell_type_name], :speed=>speed_dict[cell_type_name]] |> NamedTuple
    end
    return per_type_stats
end

"""
    motilityStatistics(simulation_id::Integer[; direction=:any])
    motilityStatistics(simulation::Simulation[; direction=:any])
    motilityStatistics(pcmm_output::PCMMOutput{Simulation}[; direction=:any])

Return the mean speed, distance traveled, and time alive for each cell in the simulation, broken down by cell type in the case of cell type transitions.

The time is counted from when the cell first appears in simulation output until it dies or the simulation ends, whichever comes first.
If the cell transitions to a new cell type during the simulation, the time is counted for each cell type separately.
Each cell type taken on by a given cell will be a key in the dictionary returned at that entry.

# Arguments
- `simulation_id::Integer`: The ID of the PhysiCell simulation. A `Simulation` object can also be passed in.
- `simulation::Simulation`: The simulation object.
- `pcmm_output::PCMMOutput{Simulation}`: The output of a PCMM simulation run.

# Keyword Arguments
- `direction::Symbol`: The direction to compute the mean speed. Can be `:x`, `:y`, `:z`, or `:any` (default). If `:x`, for example, the mean speed is calculated using only the x component of the cell's movement.

# Returns
- `AgentDict{Dict{String, NamedTuple}}`: An [`AgentDict`](@ref), i.e., one entry per cell in the simulation. Each dictionary has keys for each cell type taken on by the cell. The values are NamedTuples with fields `:time`, `:distance`, and `:speed`.

# Example
```julia
ms = motilityStatistics(1) # an AgentDict{Dict{String, NamedTuple}}, one per cell in the simulation
ms[1]["epithelial"] # NamedTuple with fields :time, :distance, :speed for the cell with ID 1 in the simulation corresponding to its time as an `epithelial` cell
ms[1]["mesenchymal"].time # time spent as a `mesenchymal` cell for the cell with ID 1 in the simulation
ms[1]["mesenchymal"].distance # distance traveled as a `mesenchymal` cell for the cell with ID 1 in the simulation
ms[1]["mesenchymal"].speed # mean speed as a `mesenchymal` cell for the cell with ID 1 in the simulation
```
"""
function motilityStatistics(simulation_id::Integer; direction=:any)
    sequence = PhysiCellSequence(simulation_id; include_cells=true)
    if ismissing(sequence)
        return missing
    end
    pos = cellDataSequence(sequence, "position"; include_dead=false, include_cell_type_name=true)
    return [k => _motilityStatistics(p; direction=direction) for (k, p) in pairs(pos) if length(p.time) > 1] |> AgentDict
end

motilityStatistics(simulation::Simulation; kwargs...) = motilityStatistics(simulation.id; kwargs...)

motilityStatistics(pcmm_output::PCMMOutput{Simulation}; kwargs...) = motilityStatistics(pcmm_output.trial, kwargs...)