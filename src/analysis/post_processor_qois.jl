export populationCountQoI

################## Ready-made `post_processor` builders ##################
#
# These build a `QoI` aimed at `run(T; post_processor=...)`, which stores one row per simulation in
# ModelManager's post-processing sink (see `postProcessingTable`). What distinguishes them from
# `standard_qois.jl` is where the value goes, not what they receive -- since ModelManager #46 every
# measurement function takes a `Simulation` -- and that the sink never calls `reduce`, so a `compute`
# returning a `Dict` of many columns is useful here and not there.
#

"""
    populationCountQoI(; index::Union{Integer,Symbol}=:final, cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) that records per-cell-type population counts.

Reads the snapshot at `index` — `:final` (default), `:initial`, or an integer snapshot
index — via [`PhysiCellSnapshot`](@ref) and [`populationCount`](@ref). Each cell type
becomes a `count_<cell_type>` entry (e.g. `count_default`), stored by [`run`](@ref
ModelManager.run) in the post-processing sink and readable back with
[`postProcessingTable`](@ref) or `simulationsTable(...; post_processing=true)`.

If the requested snapshot doesn't exist (e.g. it was pruned), `compute` returns `nothing` and
nothing is recorded for that simulation rather than throwing.

One QoI covers every cell type, rather than one QoI each, because the cell types are read from the
simulation's own output and so are not known until it has run — a `QoI` names its column at
construction, but ModelManager expands a `Dict` return into one column per key. That is also why
this suits the sink specifically: `reduce` is never called there. To measure named cell types across
a monad's replicates instead, use [`endpointPopulationCountQoI`](@ref).

# Arguments
- `index`: Which snapshot to count — `:final`, `:initial`, or an integer snapshot index.
- `cell_types`: Optional `Vector{String}` to restrict which cell types are recorded.
  If `nothing`, all cell types present in the simulation are included.
- `include_dead`: Whether to include dead cells in the count (default `false`).

# Examples
```julia
run(sampling; post_processor = populationCountQoI())                       # final counts
run(sampling; post_processor = populationCountQoI(; index=0))              # counts at snapshot 0
run(sampling; post_processor = populationCountQoI(; include_dead=true))    # include dead cells
run(sampling; post_processor = populationCountQoI(; cell_types=["tumor"])) # only "tumor"
```
"""
function populationCountQoI(; index::Union{Integer,Symbol}=:final,
                              cell_types::Union{Nothing,Vector{String}}=nothing,
                              include_dead::Bool=false)
    return QoI("population_count", function (simulation::Simulation)
        snapshot = PhysiCellSnapshot(simulationID(simulation), index; include_cells=true)
        ismissing(snapshot) && return nothing
        counts = populationCount(snapshot; include_dead=include_dead)
        ismissing(counts) && return nothing
        isnothing(cell_types) || (counts = filter(p -> p.first in cell_types, counts))
        return Dict("count_$(name)" => n for (name, n) in counts)
    end)
end
