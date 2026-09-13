export populationCountQoI

################## Ready-made `post_processor` builders ##################
#
# These build a `QoI` aimed at `run(T; post_processor=...)`, which stores one row per simulation in
# ModelManager's post-processing sink (see `postProcessingTable`). What distinguishes them from
# `standard_qois.jl` is where the value goes, not what they receive -- since ModelManager #46 every
# measurement function takes a `Simulation` -- and that the sink never calls `reduce`, so a `compute`
# returning a `Dict` of many columns is useful here and not there.
#
# Since ModelManager 0.9.1 the sink names a spread column `"<qoi name>.<key>"`, so the key carries the
# cell type alone and the QoI's name supplies the rest.
#

"""
    populationCountQoI(; index::Union{Integer,Symbol}=:final, cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) that records per-cell-type population counts.

Reads the snapshot at `index` — `:final` (default), `:initial`, or an integer snapshot
index — via [`PhysiCellSnapshot`](@ref) and [`populationCount`](@ref). Each cell type becomes
one entry keyed by its name, stored by [`run`](@ref ModelManager.run) in the post-processing
sink under the column `population_count.<cell_type>` (e.g. `population_count.default`) and
readable back with [`postProcessingTable`](@ref) or `simulationsTable(...; post_processing=true)`.

If the requested snapshot doesn't exist (e.g. it was pruned), `compute` returns `missing` and
nothing is recorded for that simulation rather than throwing.

One QoI covers every cell type: they are read from the simulation's own output and so are not known
until it has run, and ModelManager expands a `Dict` return into one column per key. The keyword
arguments travel in the QoI's `data` slot, so a calibration's `problem.jld2` written from it is
complete.

This QoI defines no `reduce` of its own, so wherever it is reduced across replicates ModelManager's
default applies: a mean per cell type, which refuses a monad whose replicates report different cell
types. [`endpointPopulationCountQoI`](@ref) measures the same thing at the final snapshot and
zero-fills a cell type a replicate lacks instead.

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
    #! The keywords ride in `data` and `compute` is a named function, so the QoI restores by name
    #! from a calibration's `problem.jld2` (see the note in `standard_qois.jl`).
    return QoI("population_count", _populationCountsAt; data=(; index, cell_types, include_dead))
end

#! `compute` of `populationCountQoI`.
function _populationCountsAt(simulation::Simulation, data)
    snapshot = PhysiCellSnapshot(simulationID(simulation), data.index; include_cells=true)
    #! `missing`, never `nothing`: `missing` records nothing for this simulation, where
    #! ModelManager refuses `nothing` as the value a block returns by accident.
    ismissing(snapshot) && return missing
    counts = populationCount(snapshot; include_dead=data.include_dead)
    ismissing(counts) && return missing
    isnothing(data.cell_types) || (counts = filter(p -> p.first in data.cell_types, counts))
    #! The key is the bare cell type. It used to be `"count_$(name)"`, from when the sink put
    #! every key in one flat namespace and a prefix was the only thing keeping two QoIs' "tumor"
    #! apart. ModelManager 0.9.1 names the column `"<qoi name>.<key>"`, which does that job, so
    #! the prefix would only give `population_count.count_default`.
    return Dict(name => n for (name, n) in counts)
end
