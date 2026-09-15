export populationCountQoI, populationFractionQoI, meanPopulationTimeSeriesQoI

################## PhysiCell-specific measurements ##################
#
# The `QoI` builders PCMM ships. All of them are PhysiCell-specific in one way only: they read
# simulation output through the PhysiCell loader (PhysiCellSnapshot, populationCount,
# SimulationPopulationTimeSeries). Everything that consumes a `QoI` -- calibration
# (CalibrationProblem, ABCSMC, mseDistance), sensitivity analysis and the post-processing sink --
# lives in ModelManager, and one `QoI` reaches all three, so every builder lives here.
#
# One builder per quantity, each measuring ONE simulation, which is what every consumer asks for.
# The monad-level summary statistics that used to sit above them -- taking a monad ID and doing their
# own averaging, the pre-0.9 measurement contract -- are gone (#232): under the default reducer each
# was its builder's value computed a second way. `finalPopulationCount(::Monad)` and
# `MonadPopulationTimeSeries` in `population.jl` remain for analysing a finished monad directly.
#
# A single QoI per quantity is what lets `cell_types` stay optional and keeps `observed_data` keyed
# by bare cell type. Calibration hands `distance` a `SummaryValues` keyed by `(qoi name, cell type)`,
# in which a bare `"tumor"` resolves while only one QoI reports that key, so `mseDistance` compares
# one Dict-valued QoI against cell-type-keyed `observed_data`. It also means one QoI discovers the
# cell types from the simulation's own output, where a vector of QoIs would have to name them at
# construction.
#
# No builder defines a `reduce`. All three reduce under ModelManager's default per-key mean, whose one
# rule is that the replicates of a monad carry the same keys -- satisfied by construction, because
# `populationCount` keys every cell type the model declares rather than only the ones with living
# cells, and replicates of a monad share a config and so a roster. No roster can be ragged, so nothing
# here zero-fills an absent cell type or drops a replicate from one key's average; the three bespoke
# reducers that did both are gone (#232).
#
# Sensitivity analysis spreads a keyed `reduce` into one analysis per key -- labelled
# `"<qoi name>.<key>"`, the same reading the sink gives it -- so `populationCountQoI` and
# `populationFractionQoI` serve all three consumers with no per-cell-type rewrite.
# `meanPopulationTimeSeriesQoI` reaches calibration only, and for one reason at both ends: every
# component it reports is a time series rather than the `Real` a sink column or a sensitivity index is
# computed from, so the sink refuses its `compute` and sensitivity analysis refuses its `reduce`.
# Reduce a series to a scalar to ask either question about it.
#
# The reducer sees only the replicates that produced a value: `QoI`'s default `skip_missing=true`
# drops the `missing` ones and reduces a monad with none to `missing` before `reduce` is called.
#
# Restorability. A builder's keyword arguments travel in the QoI's `data` slot and its `compute` is
# one of the named top-level functions below, so JLD2 can bring a `problem.jld2` written from a
# builder back by name and `resumeABC(Calibration(id))` needs no `problem=`. A closure capturing
# `cell_types` would be saved as `nothing` -- ModelManager stores functions by name only -- and force
# every resume of a PCMM calibration to re-supply the problem. `data !== nothing` is what selects the
# two-argument calling convention, `compute(sim, data)` and `reduce(values, data)`, ModelManager's
# default reducer included: it takes `data` and ignores it, which is what lets a builder keep `data`
# for `compute` alone and define no `reduce`.

################## Internal helpers ##################

#! Restrict a per-simulation dict to `cell_types`, or leave it alone when none were named.
_restrict(d, cell_types) = isnothing(cell_types) ? d : filter(p -> p.first in cell_types, d)

#! One simulation's unrestricted cell counts at snapshot `index`, or `missing` when the snapshot is
#! not on disk (pruned, or never written). Shared by the count and fraction computes so the snapshot
#! handling has one definition -- and so the fraction's denominator is the same population the count
#! reports. `missing`, never `nothing`: `missing` records nothing for this simulation, where
#! ModelManager refuses `nothing` as the value a block returns by accident.
function _populationCountsAt(simulation::Simulation, index, include_dead::Bool)
    snapshot = PhysiCellSnapshot(simulationID(simulation), index; include_cells=true)
    ismissing(snapshot) && return missing
    return populationCount(snapshot; include_dead=include_dead)
end

#! `compute` of `populationCountQoI`. The key is the bare cell type: ModelManager names the column
#! `"<qoi name>.<key>"`, so a `"count_"` prefix (which 0.3.x carried, when the sink was one flat
#! namespace) would only give `population_count.count_default`.
function _populationCountsOf(simulation::Simulation, data)
    counts = _populationCountsAt(simulation, data.index, data.include_dead)
    ismissing(counts) && return missing
    return Dict(name => n for (name, n) in _restrict(counts, data.cell_types))
end

#! `compute` of `populationFractionQoI`. The denominator is the whole population at that snapshot, so
#! `total` is summed BEFORE restricting: filtering to one cell type reports its share of everything,
#! not 1.0. `_restrict` here, not only in `reduce`: the post-processing sink calls `compute` and never
#! `reduce`, so a builder that filtered only in its reducer would write a column for every cell type
#! and silently ignore `cell_types`.
function _populationFractionsOf(simulation::Simulation, data)
    counts = _populationCountsAt(simulation, data.index, data.include_dead)
    ismissing(counts) && return missing
    total = sum(values(counts))
    fractions = total == 0 ? Dict(k => 0.0 for k in keys(counts)) :
                             Dict(k => Float64(v) / total for (k, v) in counts)
    return _restrict(fractions, data.cell_types)
end

#! `compute` of `meanPopulationTimeSeriesQoI`: one replicate's counts per cell type, on that
#! replicate's own time grid, restricted. A `Dict` of `Vector`s rather than the
#! `SimulationPopulationTimeSeries` it reads, because the default reducer averages a keyed value per
#! key and a `Vector` component averages elementwise -- which is the whole of what
#! `MonadPopulationTimeSeries` does to these series. The grid is neither carried nor compared across
#! replicates: replicates of one monad share a config and therefore a save schedule.
function _populationTimeSeriesOf(sim::Simulation, data)
    spts = SimulationPopulationTimeSeries(sim; include_dead=data.include_dead, verbose=false)
    ismissing(spts) && return missing
    return Dict{String,Vector{Float64}}(_restrict(spts.cell_count, data.cell_types))
end

################## QoI-returning builders ##################

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
default applies: a mean per cell type. That makes one builder serve calibration, sensitivity
analysis and the sink alike. It cannot trip the default's one requirement — that the replicates agree
about their keys — because [`populationCount`](@ref) keys every cell type the model declares rather
than only those with living cells, and the replicates of a monad share a config. To average a
finished monad's final counts directly, without a `QoI`, call
[`finalPopulationCount`](@ref) on a `Monad`.

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

problem = CalibrationProblem(inputs, parameters, observed, populationCountQoI(), mseDistance)
```
"""
function populationCountQoI(; index::Union{Integer,Symbol}=:final,
                              cell_types::Union{Nothing,Vector{String}}=nothing,
                              include_dead::Bool=false)
    #! The keywords ride in `data` and `compute` is a named function, so the QoI restores by name
    #! from a calibration's `problem.jld2` (the restorability note above).
    return QoI("population_count", _populationCountsOf; data=(; index, cell_types, include_dead))
end

"""
    populationFractionQoI(; index::Union{Integer,Symbol}=:final, cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) that records each cell type's fraction of the total
population.

The exact analogue of [`populationCountQoI`](@ref): it reads the same snapshot at the same `index`
and divides each cell type's count by the total over **all** cell types before restricting to
`cell_types`, so filtering to one type reports its share of the whole population rather than 1.0.
Its value is a `Dict{String,Float64}` of cell type → fraction, written to the sink under
`population_fraction.<cell_type>` and labelled that way by sensitivity analysis. `missing` when the
snapshot is not on disk.

The ratio is taken per simulation and only then averaged — mean-of-ratios, not ratio-of-means — which
is what fits it to a per-simulation `compute`. Like the other builders it defines no `reduce` and is
averaged across a monad's replicates by ModelManager's default per-key mean, and its keyword
arguments travel in `data` with a named `compute`, so `resumeABC(Calibration(id))` needs no
`problem=`.

# Arguments
- `index`: Which snapshot to measure — `:final`, `:initial`, or an integer snapshot index.
- `cell_types`: restrict to these cell types. `nothing` (default) reports every cell type present.
- `include_dead`: whether to include dead cells, in the numerator and the denominator alike
  (default `false`).

# Examples
```julia
problem = CalibrationProblem(inputs, parameters, observed, populationFractionQoI(), mseDistance)
run(sampling; post_processor = populationFractionQoI(; cell_types=["tumor"]))
```
"""
function populationFractionQoI(; index::Union{Integer,Symbol}=:final,
                                 cell_types::Union{Nothing,Vector{String}}=nothing,
                                 include_dead::Bool=false)
    return QoI("population_fraction", _populationFractionsOf; data=(; index, cell_types, include_dead))
end

"""
    meanPopulationTimeSeriesQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving the mean population time series per cell type across
a monad's replicates. Restorable like [`populationCountQoI`](@ref): the keyword arguments
travel in `data`, so resuming needs no `problem=`.

Its value is a `Dict{String,Vector{Float64}}` of cell type → mean count over time, so a
`CalibrationProblem` using it wants `observed_data` values on that same time grid. Its `compute`
reports one replicate's counts on that replicate's own grid and it defines no `reduce`, so
ModelManager's default per-key mean averages them elementwise — which is what
`MonadPopulationTimeSeries` does to the same series. No grid check is needed: replicates of
one monad share a config and therefore a save schedule.

Calibration is its only consumer. Every component is a time series rather than the `Real` a sink
column or a sensitivity index is computed from, so the post-processing sink refuses its `compute` and
sensitivity analysis refuses its `reduce`.

# Keyword Arguments
- `cell_types`: restrict to these cell types. `nothing` (default) measures every cell type present.
- `include_dead`: whether to include dead cells in the count (default `false`).

# Examples
```julia
problem = CalibrationProblem(inputs, parameters, observed, meanPopulationTimeSeriesQoI(), mseDistance)
```
"""
function meanPopulationTimeSeriesQoI(; cell_types::Union{Nothing,Vector{String}}=nothing,
                                       include_dead::Bool=false)
    return QoI("mean_population_time_series", _populationTimeSeriesOf; data=(; cell_types, include_dead))
end
