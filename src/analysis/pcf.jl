using PairCorrelationFunction, RecipesBase

import PairCorrelationFunction: pcf

@compat public pcf

"""
    PCMMPCFResult

A struct to hold the results of the pair correlation function (PCF) calculation.

The start and end radii for each annulus are stored in the `radii` field.
Thus, there is one more radius than there are annuli, i.e. `length(radii) == size(g, 1) + 1`.
Each column of `g` corresponds to a time point in the `time` field, hence `size(g, 2) == length(time)`.

# Fields
- `time::Vector{Float64}`: The time points at which the PCF was calculated.
- `pcf_result::PairCorrelationFunction.PCFResult`: The result of the PCF calculation.

# Example
```jldoctest
using PairCorrelationFunction
time = 12.0
radii = [0.0, 1.0, 2.0]
g = [0.5, 1.2]
PhysiCellModelManager.PCMMPCFResult(time, PairCorrelationFunction.PCFResult(radii, g))
# output
PCMMPCFResult:
  Time: 12.0
  Radii: 0.0 - 2.0 with 2 annuli, Δr = 1.0
  g: 0.5 - 1.2 (min - max)
```
```jldoctest
using PairCorrelationFunction
time = [12.0; 24.0; 36.0]
radii = [0.0, 1.0, 2.0]
g = [0.5 0.6 0.4; 1.2 1.15 1.4]
PhysiCellModelManager.PCMMPCFResult(time, PairCorrelationFunction.PCFResult(radii, g))
# output
PCMMPCFResult:
  Time: 12.0 - 36.0 (n = 3)
  Radii: 0.0 - 2.0 with 2 annuli, Δr = 1.0
  g: 0.4 - 1.4 (min - max)
```
"""
struct PCMMPCFResult
    time::Vector{Float64}
    pcf_result::PairCorrelationFunction.PCFResult

    function PCMMPCFResult(time::Float64, result::PairCorrelationFunction.PCFResult)
        @assert size(result.g, 2) == 1 "If time is a single value, g must be a vector or a matrix with one column. Found $(size(result.g, 2)) columns."
        return new([time], result)
    end

    function PCMMPCFResult(time::Vector{Float64}, result::PairCorrelationFunction.PCFResult)
        @assert size(result.g, 2) == length(time) "If time is a vector, g must be a matrix with matching number of columns. Found $(length(time)) timepoints but $(size(result.g, 2)) columns."
        return new(time, result)
    end
end

function Base.hcat(gs::Vararg{PCMMPCFResult})
    time = reduce(vcat, [g.time for g in gs])
    pcf_result = hcat([g.pcf_result for g in gs]...)
    return PCMMPCFResult(time, pcf_result)
end

function Base.show(io::IO, p::PCMMPCFResult)
    println(io, "PCMMPCFResult:")
    if length(p.time) == 1
        println(io, "  Time: $(p.time[1])")
    else
        println(io, "  Time: $(p.time[1]) - $(p.time[end]) (n = $(length(p.time)))")
    end
    print(io, "  Radii: $(p.pcf_result.radii[1]) - $(p.pcf_result.radii[end]) with $(length(p.pcf_result.radii)-1) annuli")
    rs = p.pcf_result.radii
    drs = diff(rs)
    display_tol = 0.01 #! if the radii deltas are within 1%, just display it as being the same for simplicity
    if all(drs .> drs[1] * (1-display_tol)) && all(drs .< drs[1] * (1 + display_tol))
        println(io, ", Δr = $(drs[1])")
    else
        println(io, ", Δr varying on [min = $(minimum(drs)), max = $(maximum(drs))]")
    end
    temp_g = filter(!isnan, p.pcf_result.g)
    println(io, "  g: $(minimum(temp_g)) - $(maximum(temp_g)) (min - max)")
end

"""
    pcf(S::AbstractPhysiCellSequence, center_cell_types, target_cell_types=center_cell_types; include_dead::Union{Bool,Tuple{Bool,Bool}}=false, dr::Float64=20.0)
    pcf(simulation::Simulation[, index], args...; kwargs...)
    pcf(simulation_id::Integer[, index], args...; kwargs...)
    pcf(pcmm_output::PCMMOutput{Simulation}[, index], args...; kwargs...)

Calculate the pair correlation function (PCF) between two sets of cell types in a PhysiCell simulation snapshot or sequence.

The `center_cell_types` and `target_cell_types` can be strings or vectors of strings.
This will compute one PCF rather than one for each pair of (center, target) cell types, i.e., all centers are compared to all targets.
If omitted, the target_cell_types will be the same as the center_cell_types, i.e., not a cross-PCF.
The `include_dead` argument can be a boolean or a tuple of booleans to indicate whether to include the dead centers and/or targets, respectively.
The `dr` argument specifies the bin size (thickness of each annulus) for the PCF calculation.

In the signatures with an `index`, if it is provided then a single snapshot is analyzed, otherwise the entire sequence is analyzed.
The `index` must be an integer or either the symbol `:initial` or `:final`.

# Arguments
- `S::AbstractPhysiCellSequence`: A [`PhysiCellSnapshot`](@ref) or [`PhysiCellSequence`](@ref) object.
- `center_cell_types`: The cell type name(s) to use as the center of the PCF.
- `target_cell_types`: The cell type name(s) to use as the target of the PCF.
- `simulation::Simulation`: The simulation object.
- `simulation_id::Integer`: The ID of the PhysiCell simulation.
- `pcmm_output::PCMMOutput{Simulation}`: The output of a PCMM simulation run.
- `index::Union{Integer, Symbol}`: The index of the snapshot to analyze (can be an integer or the symbol `:initial` or `:final`).

# Keyword Arguments
- `include_dead::Union{Bool,Tuple{Bool,Bool}}`: Whether to include dead cells in the PCF calculation. If a tuple, the first element indicates whether to include dead centers and the second element indicates whether to include dead targets.
- `dr::Float64`: The bin size for the PCF calculation.

# Alternate methods
- `pcf(simulation::Simulation, index::Union{Integer, Symbol}, center_cell_types, target_cell_types=center_cell_types; kwargs...)`: Calculate the PCF for a specific snapshot in a simulation.
- `pcf(simulation_id::Integer, index::Union{Integer, Symbol}, center_cell_types, target_cell_types=center_cell_types; kwargs...)`: Calculate the PCF for a specific snapshot in a simulation by ID.
- `pcf(simulation_id::Integer, center_cell_types, target_cell_types=center_cell_types; kwargs...)`: Calculate the PCF for all snapshots in a simulation by ID.
- `pcf(simulation::Simulation, center_cell_types, target_cell_types=center_cell_types; kwargs...)`: Calculate the PCF for all snapshots in a simulation.

# Returns
A [`PCMMPCFResult`](@ref) object containing the time, radii, and g values of the PCF.
Regardless of the type of `S`, the time and radii will always be vectors.
If `S` is a snapshot, the g values will be a vector of the PCF.
If `S` is a sequence, the g values will be a (length(radii)-1 x length(time)) matrix of the PCF.
"""
function pcf(snapshot::PhysiCellSnapshot, center_cell_types, target_cell_types=center_cell_types; include_dead::Union{Bool,Tuple{Bool,Bool}}=false, dr::Float64=20.0)
    args = preparePCF!(snapshot, center_cell_types, target_cell_types, include_dead, dr)
    return pcfSnapshotCalculation(snapshot, args...)
end

function pcf(sequence::PhysiCellSequence, center_cell_types, target_cell_types=center_cell_types; include_dead::Union{Bool,Tuple{Bool,Bool}}=false, dr::Float64=20.0)
    args = preparePCF!(sequence, center_cell_types, target_cell_types, include_dead, dr)
    all_results = [pcfSnapshotCalculation(snapshot, args...) for snapshot in sequence.snapshots]
    return hcat(all_results...)
end

pcf(simulation::Simulation, index::Union{Integer, Symbol}, args...; kwargs...) = pcf(PhysiCellSnapshot(simulation, index), args...; kwargs...)
pcf(simulation_id::Integer, index::Union{Integer, Symbol}, center_cell_types, target_cell_types=center_cell_types; kwargs...) = pcf(PhysiCellSnapshot(simulation_id, index), center_cell_types, target_cell_types; kwargs...)

function pcf(simulation_id::Integer, center_cell_types, target_cell_types=center_cell_types; kwargs...)
    print("Computing PCF sequence for simulation ID $(simulation_id)...")
    result = pcf(PhysiCellSequence(simulation_id), center_cell_types, target_cell_types; kwargs...)
    println(" done.")
    return result
end

pcf(simulation::Simulation, args...; kwargs...) = pcf(simulation.id, args...; kwargs...)

pcf(pcmm_output::PCMMOutput{Simulation}, args...; kwargs...) = pcf(pcmm_output.trial, args...; kwargs...)

#! pcf helper functions
"""
    preparePCF!(S::AbstractPhysiCellSequence, center_cell_types, target_cell_types, include_dead::Union{Bool,Tuple{Bool,Bool}}, dr::Float64)

Prepare the arguments for the PCF calculation.
"""
function preparePCF!(S::AbstractPhysiCellSequence, center_cell_types, target_cell_types, include_dead::Union{Bool,Tuple{Bool,Bool}}, dr::Float64)
    loadCells!(S)
    loadMesh!(S)
    center_cell_types, target_cell_types = processPCFCellTypes.([center_cell_types, target_cell_types])
    temp = cellTypeToNameDict(S)
    cell_name_to_type_dict = [type_name => type_id for (type_id, type_name) in temp] |> Dict{String,Int}
    is_cross_pcf = isCrossPCF(center_cell_types, target_cell_types)
    if include_dead isa Bool
        include_dead = (include_dead, include_dead)
    end
    constants = pcfConstants(S, dr)
    return (center_cell_types, target_cell_types, cell_name_to_type_dict, include_dead, is_cross_pcf, constants)
end

"""
    pcfConstants(S::AbstractPhysiCellSequence, dr::Float64)

Create a `Constants` object for the PCF calculation based on the mesh of the snapshot or sequence.
"""
function pcfConstants(snapshot::PhysiCellSnapshot, dr::Float64)
    dx = snapshot.mesh["x"][2] - snapshot.mesh["x"][1]
    dy = snapshot.mesh["y"][2] - snapshot.mesh["y"][1]
    xlims = (snapshot.mesh["x"][1] .- dx/2, snapshot.mesh["x"][end] .+ dx/2)
    ylims = (snapshot.mesh["y"][1] .- dy/2, snapshot.mesh["y"][end] .+ dy/2)
    constants_lims = [xlims, ylims]
    is_3d = length(snapshot.mesh["z"]) > 1
    if is_3d
        dz = snapshot.mesh["z"][2] - snapshot.mesh["z"][1]
        zlims = (snapshot.mesh["z"][1] .- dz/2, snapshot.mesh["z"][end] .+ dz/2)
        push!(constants_lims, zlims)
    end
    return Constants(constants_lims..., dr)
end

function pcfConstants(sequence::PhysiCellSequence, dr::Float64)
    snapshot = sequence.snapshots[1]
    return pcfConstants(snapshot, dr)
end

"""
    pcfSnapshotCalculation(snapshot::PhysiCellSnapshot, center_cell_types::Vector{String}, target_cell_types::Vector{String}, cell_name_to_type_dict::Dict{String,Int}, include_dead::Union{Bool,Tuple{Bool,Bool}}, is_cross_pcf::Bool, constants::Constants)

Calculate the pair correlation function (PCF) for a given snapshot.
"""
function pcfSnapshotCalculation(snapshot::PhysiCellSnapshot, center_cell_types::Vector{String}, target_cell_types::Vector{String}, cell_name_to_type_dict::Dict{String,Int}, include_dead::Union{Bool,Tuple{Bool,Bool}}, is_cross_pcf::Bool, constants::Constants)
    is_3d = ndims(constants) == 3
    cells = snapshot.cells
    centers = cellPositionsForPCF(cells, center_cell_types, cell_name_to_type_dict, include_dead[1], is_3d)
    if is_cross_pcf
        targets = cellPositionsForPCF(cells, target_cell_types, cell_name_to_type_dict, include_dead[2], is_3d)
        pcf_result = pcf(centers, targets, constants)
    else
        pcf_result = pcf(centers, constants)
    end
    return PCMMPCFResult(snapshot.time, pcf_result)
end

"""
    processPCFCellTypes(cell_types)

Process the cell types for the PCF calculation so that they are always a vector of strings.
"""
function processPCFCellTypes(cell_types)
    if cell_types isa String
        return [cell_types]
    elseif cell_types isa AbstractVector{<:AbstractString}
        return cell_types
    end
    throw(ArgumentError("Cell types must be a string or a vector of strings. Got $(typeof(cell_types))."))
end

"""
    isCrossPCF(center_cell_types::Vector{String}, target_cell_types::Vector{String})

Check if the center and target cell types are the same (PCF) or disjoint (cross-PCF); if neither, throw an error.
"""
function isCrossPCF(center_cell_types::Vector{String}, target_cell_types::Vector{String})
    center_set = Set(center_cell_types)
    target_set = Set(target_cell_types)
    if center_set == target_set
        return false
    elseif isdisjoint(center_set, target_set)
        return true
    else
        throw(ArgumentError("Center and target cell types must be the same or disjoint. Found $(center_cell_types) and $(target_cell_types)."))
    end
end

"""
    cellPositionsForPCF(cells::DataFrame, cell_types::Vector{String}, cell_name_to_type_dict::Dict{String,Int}, include_dead::Bool, is_3d::Bool)

Get the positions of the cells for the PCF calculation.
"""
function cellPositionsForPCF(cells::DataFrame, cell_types::Vector{String}, cell_name_to_type_dict::Dict{String,Int}, include_dead::Bool, is_3d::Bool)
    cell_type_id_set = [cell_name_to_type_dict[cell_type] for cell_type in cell_types] |> Set
    cell_type_df = cells[[ct in cell_type_id_set for ct in cells.cell_type], :]
    if !include_dead
        cell_type_df = cell_type_df[.!cell_type_df.dead, :]
    end
    position_labels = [:position_1, :position_2]
    if is_3d
        push!(position_labels, :position_3)
    end
    return reduce(hcat, [cell_type_df[!, label] for label in position_labels])
end

#! plotting functions
@recipe function f(results::Vararg{PCMMPCFResult}; time_unit=:min, distance_unit=:um)
    args = preparePCFPlot([results...]; time_unit=time_unit, distance_unit=distance_unit)
    @series begin
        colorscheme --> :cork
        PairCorrelationFunction.PCFPlot(args)
    end
end

@recipe function f(results::Vector{PCMMPCFResult}; time_unit=:min, distance_unit=:um)
    args = preparePCFPlot(results; time_unit=time_unit, distance_unit=distance_unit)
    @series begin
        colorscheme --> :cork
        PairCorrelationFunction.PCFPlot(args)
    end
end

"""
    preparePCFPlot(results::Vector{PCMMPCFResult}; time_unit=:min, distance_unit=:um)

Prepare the time and radii for the PCF plot.
"""
function preparePCFPlot(results::Vector{PCMMPCFResult}; time_unit=:min, distance_unit=:um)
    @assert all([r.time == results[1].time for r in results]) "All PCFResults must have the same time vector."
    time = processTime(results[1].time, time_unit) #! we need to make a copy of the time vector anyways, so no need to have a ! function
    radii = processDistance(results[1].pcf_result.radii, distance_unit)
    return time, radii, [r.pcf_result for r in results]
end

"""
    processTime(time::Vector{Float64}, time_unit::Symbol)

Process the time vector to convert it to the desired time unit.
Options are :min, :s, :h, :d, :w, :mo, and :y.
"""
function processTime(time, time_unit)
    time_unit = Symbol(time_unit)
    if time_unit in [:min, :minute, :minutes]
    elseif time_unit in [:s, :second, :seconds]
        time = time .* 60
    elseif time_unit in [:h, :hour, :hours]
        time = time ./ 60
    elseif time_unit in [:d, :day, :days]
        time = time ./ 1440
    elseif time_unit in [:w, :week, :weeks]
        time = time ./ 10080
    elseif time_unit in [:mo, :month, :months]
        time = time ./ 43200 #! assumes 30 days in a month
    elseif time_unit in [:y, :year, :years]
        time = time ./ 525600 #! assumes exactly 365 days in a year
    else
        throw(ArgumentError("Invalid time unit: $(time_unit). Must be one of :min, :s, :h, :d, :w, or :y."))
    end
    return time
end

"""
    processDistance(distance::Vector{Float64}, distance_unit::Symbol)

Process the distance vector to convert it to the desired distance unit.
Options are :um, :mm, and :cm.
"""
function processDistance(distance, distance_unit)
    distance_unit = Symbol(distance_unit)
    if distance_unit in [:um, :micrometer, :micrometers, :μm, :micron, :microns]
        #! default PhysiCell distance unit
    elseif distance_unit in [:mm, :millimeter, :millimeters]
        distance = distance ./ 1000
    elseif distance_unit in [:cm, :centimeter, :centimeters]
        distance = distance ./ 100
    else
        throw(ArgumentError("Invalid distance unit: $(distance_unit). Must be one of :um, :mm, or :cm."))
    end
    return distance
end