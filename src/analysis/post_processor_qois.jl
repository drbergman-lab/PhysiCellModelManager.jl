export populationCountQoI

################## Ready-made `post_processor` builders ##################
#
# These build a `post_processor` (see `run`) suitable for `run(T; post_processor=...)`.
#
# Since ModelManager #46 there is one argument contract everywhere: a measurement function -- a
# `post_processor`, a `summary_statistic`, or a `QoI`'s `compute` -- receives a `Simulation`. What
# still distinguishes these from `standard_qois.jl` is where the value goes, not what they are
# handed: these store one row per simulation in ModelManager's post-processing sink (see
# `postProcessingTable`), while those are reduced across a monad's replicates.
#

"""
    populationCountQoI(; index::Union{Integer,Symbol}=:final, cell_types=nothing, include_dead::Bool=false)

Return a `post_processor` (see [`run`](@ref ModelManager.run)) that records per-cell-type
population counts as quantities of interest.

Reads the snapshot at `index` — `:final` (default), `:initial`, or an integer snapshot
index — via [`PhysiCellSnapshot`](@ref) and [`populationCount`](@ref). Each cell type
becomes a `count_<cell_type>` entry (e.g. `count_default`), stored by [`run`](@ref
ModelManager.run) in the post-processing sink and readable back with
[`postProcessingTable`](@ref) or `simulationsTable(...; post_processing=true)`.

If the requested snapshot doesn't exist (e.g. it was pruned), returns `nothing` so no QoI
is recorded for that simulation rather than throwing.

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
    return function (simulation::Simulation)
        snapshot = PhysiCellSnapshot(simulationID(simulation), index; include_cells=true)
        ismissing(snapshot) && return nothing
        counts = populationCount(snapshot; include_dead=include_dead)
        ismissing(counts) && return nothing
        isnothing(cell_types) || (counts = filter(p -> p.first in cell_types, counts))
        return Dict("count_$(name)" => n for (name, n) in counts)
    end
end
