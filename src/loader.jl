#! PhysiCell output loading lives in the standalone PhysiCellOutput.jl package (path-based,
#! stateless: its types are keyed on an output-folder path, with no database identity). PCMM
#! exports critical types and functions from PhysiCellOutput.
#!
#! This file re-adds PhysiCellModelManager's database identity on top: it provides
#! `simulation_id::Integer`- and `Simulation`-based entry points that convert to an output
#! folder via `pathToOutputFolder` (a ModelManager function) and then delegate to
#! PhysiCellOutput. Object-based methods (`loadCells!(snapshot)`, `cellDataSequence(sequence,
#! …)`, `cellLabels(snapshot)`, …) are used directly from PhysiCellOutput and need no adapter.
#!
#! These id-/`Simulation`-based methods extend functions owned by PhysiCellOutput with argument
#! types owned by ModelManager/Base — i.e. type piracy. It is deliberately confined to this one
#! file and is tolerable because PhysiCellModelManager is the terminal application in this
#! package stack (nothing depends on PCMM's loading API the way PCMM depends on PhysiCellOutput
#! and ModelManager). See PCMM_MIGRATION.md §5 and progress.md (2026-07-23) for the rationale.

import PhysiCellOutput: PhysiCellSnapshot, PhysiCellSequence,
    cellLabels, cellTypeToNameDict, substrateNames,
    cellDataSequence, pathToOutputFileBase, pathToOutputXML

export cellDataSequence, getCellDataSequence, PhysiCellSnapshot, PhysiCellSequence,
       loadCells!, loadSubstrates!, loadMesh!, loadGraph!

"""
    PhysiCellSnapshot(simulation_id::Integer, index::Union{Integer,Symbol}, labels=String[], substrate_names=String[]; kwargs...)
    PhysiCellSnapshot(simulation::Simulation, index::Union{Integer,Symbol}, args...; kwargs...)

Load a single snapshot of a PhysiCell simulation identified by its database id (or a
[`Simulation`](@ref)).

This is PhysiCellModelManager's database-identity entry point: it asserts that a project is
initialized, converts `simulation_id` to its output folder via `pathToOutputFolder`, and
delegates to the folder-based `PhysiCellOutput.PhysiCellSnapshot`. See that method for the
full list of `include_*` keyword arguments and the returned fields.

Returns `missing` (with a printed message) if the snapshot's files are not present, e.g. for a
pruned simulation.

# Examples
```julia
snapshot = PhysiCellSnapshot(1, 3; include_cells=true, include_substrates=true)
snapshot = PhysiCellSnapshot(Simulation(1), :final; include_cells=true)
```
"""
function PhysiCellSnapshot(simulation_id::Integer, index::Union{Integer,Symbol},
                           labels::Vector{String}=String[],
                           substrate_names::Vector{String}=String[]; kwargs...)
    assertInitialized()
    return PhysiCellSnapshot(pathToOutputFolder(simulation_id), index, labels, substrate_names; kwargs...)
end

PhysiCellSnapshot(simulation::Simulation, index::Union{Integer,Symbol}, args...; kwargs...) =
    PhysiCellSnapshot(simulation.id, index, args...; kwargs...)

"""
    PhysiCellSequence(simulation_id::Integer; kwargs...)
    PhysiCellSequence(simulation::Simulation; kwargs...)

Load the full sequence of snapshots for a PhysiCell simulation identified by its database id
(or a [`Simulation`](@ref)).

Asserts that a project is initialized, converts `simulation_id` to its output folder via
`pathToOutputFolder`, and delegates to the folder-based `PhysiCellOutput.PhysiCellSequence`.
See that method for the full list of `include_*` keyword arguments and the returned fields.

Returns `missing` (with a printed message) if the simulation has no readable initial output,
e.g. for a pruned simulation.

# Examples
```julia
sequence = PhysiCellSequence(1; include_cells=true, include_substrates=true)
sequence = PhysiCellSequence(Simulation(1); include_mesh=true)
```
"""
function PhysiCellSequence(simulation_id::Integer; kwargs...)
    assertInitialized()
    return PhysiCellSequence(pathToOutputFolder(simulation_id); kwargs...)
end

PhysiCellSequence(simulation::Simulation; kwargs...) = PhysiCellSequence(simulation.id; kwargs...)

"""
    folderToSimulationID(apcs::AbstractPhysiCellSequence)

Return the database id of the simulation corresponding to a PhysiCell sequence (or snapshot) based on the output folder path.
function folderToSimulationID(apcs::AbstractPhysiCellSequence)
    try
        sim_id_str = splitpath(apcs.folder)[end-1]
        return parse(Int, sim_id_str)
    catch e
        throw(ArgumentError("Could not parse simulation ID from folder path: $(apcs.folder)"))
    end
end

"""
    cellDataSequence(simulation_id::Integer, labels; kwargs...)
    cellDataSequence(simulation::Simulation, labels; kwargs...)

Return an `AgentDict` of per-cell time series for a simulation identified by its
database id (or a [`Simulation`](@ref)). `labels` may be a single `String` or a
`Vector{String}`.

Asserts that a project is initialized, converts `simulation_id` to its output folder via
`pathToOutputFolder`, and delegates to the folder-based `PhysiCellOutput.cellDataSequence`.
See that method for the meaning of the returned data and the `include_dead` /
`include_cell_type_name` keyword arguments.

# Examples
```julia
data = cellDataSequence(1, ["position", "elapsed_time_in_phase"]; include_dead=true)
data = cellDataSequence(Simulation(1), "position")
```
"""
function cellDataSequence(simulation_id::Integer, labels::Vector{String}; kwargs...)
    assertInitialized()
    return cellDataSequence(pathToOutputFolder(simulation_id), labels; kwargs...)
end

cellDataSequence(simulation_id::Integer, label::String; kwargs...) =
    cellDataSequence(simulation_id, [label]; kwargs...)

cellDataSequence(simulation::Simulation, labels::Vector{String}; kwargs...) =
    cellDataSequence(simulation.id, labels; kwargs...)

cellDataSequence(simulation::Simulation, label::String; kwargs...) =
    cellDataSequence(simulation.id, [label]; kwargs...)

"""
    cellLabels(simulation_id::Integer)
    cellLabels(simulation::Simulation)

Return the cell-data labels (names of the cell data fields) for a simulation identified by its
database id (or a [`Simulation`](@ref)), read from its initial-snapshot XML file.

Delegates to the path-based `PhysiCellOutput.cellLabels` after resolving the output folder.
Returns an empty vector if the XML file is not present (e.g. a pruned simulation).
"""
function cellLabels(simulation_id::Integer)
    assertInitialized()
    return cellLabels(pathToOutputXML(pathToOutputFolder(simulation_id), :initial))
end

cellLabels(simulation::Simulation) = cellLabels(simulation.id)

"""
    cellTypeToNameDict(simulation_id::Integer)
    cellTypeToNameDict(simulation::Simulation)

Return a dictionary mapping cell type IDs to cell type names for a simulation identified by its
database id (or a [`Simulation`](@ref)), read from its initial-snapshot XML file.

Delegates to the path-based `PhysiCellOutput.cellTypeToNameDict` after resolving the output
folder. Returns an empty dictionary if the XML file is not present (e.g. a pruned simulation).
"""
function cellTypeToNameDict(simulation_id::Integer)
    assertInitialized()
    return cellTypeToNameDict(pathToOutputXML(pathToOutputFolder(simulation_id), :initial))
end

cellTypeToNameDict(simulation::Simulation) = cellTypeToNameDict(simulation.id)

"""
    substrateNames(simulation_id::Integer)
    substrateNames(simulation::Simulation)

Return the substrate names for a simulation identified by its database id (or a
[`Simulation`](@ref)), read from its initial-snapshot XML file.

Delegates to the path-based `PhysiCellOutput.substrateNames` after resolving the output folder.
Returns an empty vector if the XML file is not present (e.g. a pruned simulation).
"""
function substrateNames(simulation_id::Integer)
    assertInitialized()
    return substrateNames(pathToOutputXML(pathToOutputFolder(simulation_id), :initial))
end

substrateNames(simulation::Simulation) = substrateNames(simulation.id)

"""
    pathToOutputFileBase(simulation_id::Integer, index::Union{Integer,Symbol})
    pathToOutputFileBase(simulation::Simulation, index::Union{Integer,Symbol})

Return the path to the output files for a snapshot (everything but the file extension) for a
simulation identified by its database id (or a [`Simulation`](@ref)).
"""
function pathToOutputFileBase(simulation_id::Integer, index::Union{Integer,Symbol})
    assertInitialized()
    return pathToOutputFileBase(pathToOutputFolder(simulation_id), index)
end

pathToOutputFileBase(simulation::Simulation, index::Union{Integer,Symbol}) =
    pathToOutputFileBase(simulation.id, index)

"""
    pathToOutputXML(simulation_id::Integer, index::Union{Integer,Symbol}=:initial)
    pathToOutputXML(simulation::Simulation, index::Union{Integer,Symbol}=:initial)

Return the path to the XML output file for a snapshot for a simulation identified by its
database id (or a [`Simulation`](@ref)).
"""
function pathToOutputXML(simulation_id::Integer, index::Union{Integer,Symbol}=:initial)
    assertInitialized()
    return pathToOutputXML(pathToOutputFolder(simulation_id), index)
end

pathToOutputXML(simulation::Simulation, index::Union{Integer,Symbol}=:initial) =
    pathToOutputXML(simulation.id, index)
