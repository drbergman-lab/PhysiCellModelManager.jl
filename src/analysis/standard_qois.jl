export endpointPopulationCounts, endpointPopulationFractions, meanPopulationTimeSeries
export endpointPopulationCountQoI, endpointPopulationFractionQoI, meanPopulationTimeSeriesQoI
export populationCountQoI

################## PhysiCell-specific measurements ##################
#
# The monad-level statistics and the `QoI` builders PCMM ships. All of them are PhysiCell-specific
# in one way only: they read simulation output through the PhysiCell loader (finalPopulationCount,
# PhysiCellSnapshot, MonadPopulationTimeSeries). Everything that consumes a `QoI` -- calibration
# (CalibrationProblem, ABCSMC, mseDistance), sensitivity analysis and the post-processing sink --
# lives in ModelManager, and one `QoI` reaches all three, so every builder lives here, including
# `populationCountQoI` at the bottom, which is aimed at `run(T; post_processor=...)`.
#

"""
    endpointPopulationCounts(monad_id::Int; cell_types=nothing, include_dead::Bool=false)

Built-in summary statistic: mean final-snapshot cell counts across all replicates in a monad.

Returns a `Dict{String,Float64}` mapping cell type name → mean count.

This is a **monad-level** function: it takes a monad ID and does its own averaging. A
`summary_statistic` measures a single `Simulation` and ModelManager reduces the replicates, so this
is not a valid `summary_statistic` argument — passing it fails when the first monad is measured.
Use [`endpointPopulationCountQoI`](@ref), which measures the same quantity in that shape. Keep this
one for analysing a monad directly.

# Arguments
- `monad_id`: ID of the monad whose replicates to average.
- `cell_types`: Optional `Vector{String}` to restrict which cell types are included.
  If `nothing`, all cell types present in the simulation are included.
- `include_dead`: Whether to include dead cells in the count (default `false`).

# Examples
```julia
counts = endpointPopulationCounts(monad_id; cell_types=["tumor", "immune"])

# For calibration, use the QoI form instead — it measures one simulation, as ModelManager 0.9 requires
problem = CalibrationProblem(inputs, parameters, observed,
                             endpointPopulationCountQoI(; cell_types=["tumor", "immune"]),
                             mseDistance)
```
"""
function endpointPopulationCounts(monad_id::Int; cell_types::Union{Nothing,Vector{String}}=nothing, include_dead::Bool=false)
    counts = finalPopulationCount(Monad(monad_id); include_dead=include_dead)
    ismissing(counts) && return counts
    isnothing(cell_types) && return counts
    return filter(p -> p.first in cell_types, counts)
end

"""
    endpointPopulationFractions(monad_id::Int; cell_types=nothing, include_dead::Bool=false)

Built-in summary statistic: mean final-snapshot cell fractions (out of total live cells)
across all replicates in a monad.

Returns a `Dict{String,Float64}` mapping cell type name → mean fraction.

This is a **monad-level** function and not a valid `summary_statistic` argument — see
[`endpointPopulationCounts`](@ref) for why. Use [`endpointPopulationFractionQoI`](@ref) for
calibration and keep this one for analysing a monad directly.

# Arguments
- `monad_id`: ID of the monad whose replicates to average.
- `cell_types`: Optional `Vector{String}` to restrict which cell types are included.
  If `nothing`, all cell types present in the simulation are included.
- `include_dead`: Whether to include dead cells in the denominator (default `false`).
"""
function endpointPopulationFractions(monad_id::Int; cell_types::Union{Nothing,Vector{String}}=nothing, include_dead::Bool=false)
    sim_ids = constituentIDs(Monad, monad_id)
    isempty(sim_ids) && error("Monad $monad_id has no simulations: cannot compute endpoint population fractions.")
    fractions_per_sim = Dict{String,Float64}[]
    for sim_id in sim_ids
        counts = finalPopulationCount(sim_id; include_dead=include_dead)
        ismissing(counts) && continue
        total = sum(values(counts))
        d = total == 0 ? Dict(k => 0.0 for k in keys(counts)) : Dict(k => Float64(v) / total for (k, v) in counts)
        push!(fractions_per_sim, d)
    end
    isempty(fractions_per_sim) && return missing
    length(fractions_per_sim) < length(sim_ids) &&
        @info _excludedReplicates(monad_id, length(sim_ids), length(fractions_per_sim)) maxlog=1
    return _averageStatDicts(fractions_per_sim, cell_types)
end

"""
    meanPopulationTimeSeries(monad_id::Int; cell_types=nothing, include_dead::Bool=false)

Built-in summary statistic: mean population time series across all replicates in a monad.

Returns a `Dict{String,Vector{Float64}}` mapping cell type name → mean count over time.
The time axis is shared across replicates (an error is thrown if they differ).
This is a **monad-level** function and not a valid `summary_statistic` argument — see
[`endpointPopulationCounts`](@ref) for why. Use [`meanPopulationTimeSeriesQoI`](@ref) when
calibrating against time-series data, and keep this one for analysing a monad directly.
The corresponding `observed_data` values should be `Vector{Float64}` on the same time grid.

# Arguments
- `monad_id`: ID of the monad whose replicates to average.
- `cell_types`: Optional `Vector{String}` to restrict which cell types are included.
  If `nothing`, all cell types present in the simulation are included.
- `include_dead`: Whether to include dead cells in the count (default `false`).

# Examples
```julia
series = meanPopulationTimeSeries(monad_id; cell_types=["tumor"])

# For calibration, use the QoI form instead — it measures one simulation, as ModelManager 0.9 requires
problem = CalibrationProblem(inputs, parameters, observed,
                             meanPopulationTimeSeriesQoI(; cell_types=["tumor"]),
                             mseDistance)
```
"""
function meanPopulationTimeSeries(monad_id::Int; cell_types::Union{Nothing,Vector{String}}=nothing, include_dead::Bool=false)
    mpts = MonadPopulationTimeSeries(monad_id; include_dead=include_dead)
    keys_to_use = isnothing(cell_types) ? collect(keys(mpts.cell_count)) : cell_types
    return Dict{String,Vector{Float64}}(k => Vector{Float64}(mpts.cell_count[k].mean) for k in keys_to_use)
end

################## Internal Helpers ##################

"""
    _excludedReplicates(monad_id, n_total, n_kept)

Message for replicates dropped from a monad-level aggregate because their output is gone.

Only the text is shared. The `@info` stays at each aggregation site, because `maxlog` is counted per
call site — one shared logging call would report once for all of them and hide which computation
lost data.
"""
_excludedReplicates(monad_id, n_total::Int, n_kept::Int) =
    "Excluding $(n_total - n_kept)/$(n_total) replicates of monad $(monad_id) with no output on disk (deleted or pruned)."

"""
    _averageStatDicts(dicts, cell_types)

Average a vector of `Dict{String,<:Real}` across entries, optionally filtering to
`cell_types`. Returns a `Dict{String,Float64}`.
"""
function _averageStatDicts(dicts::Vector{<:Dict}, cell_types::Union{Nothing,Vector{String}})
    isempty(dicts) && return Dict{String,Float64}()
    keys_to_use = isnothing(cell_types) ? collect(keys(first(dicts))) : cell_types
    result = Dict{String,Float64}()
    for k in keys_to_use
        vals = [Float64(get(d, k, 0)) for d in dicts]
        result[k] = mean(vals)
    end
    return result
end

################## QoI-returning builders ##################
#
# The `QoI` form of the three summary statistics above: one QoI each, whose value is a
# `Dict(cell_type => value)` — the same shape the monad-level function returns, and the same shape
# `populationCountQoI` uses for the sink.
#
# A single QoI is what makes that possible. Calibration hands `distance` a `SummaryValues` keyed by
# `(qoi name, cell type)`, in which a bare `"tumor"` resolves while only one QoI reports that key, so
# `mseDistance` compares one Dict-valued QoI against the same cell-type-keyed `observed_data` the
# monad-level functions want. It also means `cell_types` can stay optional: one QoI discovers them
# from the simulation like the monad-level functions do, where a vector of QoIs would have to name
# them at construction.
#
# No builder defines a `reduce`. All four reduce under ModelManager's default per-key mean, whose one
# rule is that the replicates of a monad carry the same keys -- satisfied by construction, because
# `populationCount` keys every cell type the model declares rather than only the ones with living
# cells, and replicates of a monad share a config and so a roster. No roster can be ragged, so nothing
# here zero-fills an absent cell type or drops a replicate from one key's average; the three bespoke
# reducers that did both are gone (#232). What is left is a difference of summation order against the
# monad-level functions, which keep their own: the tests assert `≈`, not `==`.
#
# Sensitivity analysis spreads a keyed `reduce` into one analysis per key -- labelled
# `"<qoi name>.<key>"`, the same reading the sink gives it -- so the two endpoint builders serve all
# three consumers with no per-cell-type rewrite. `meanPopulationTimeSeriesQoI` reaches calibration
# only, and now for one reason at both ends: every component it reports is a time series rather than
# the `Real` a sink column or a sensitivity index is computed from, so the sink refuses its `compute`
# and sensitivity analysis refuses its `reduce`. Reduce a series to a scalar to ask either question
# about it.
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

#! Restrict a per-simulation dict to `cell_types`, or leave it alone when none were named.
_restrict(d, cell_types) = isnothing(cell_types) ? d : filter(p -> p.first in cell_types, d)

#! `compute` of `endpointPopulationCountQoI`: one replicate's final counts, restricted.
function _endpointCountsOf(sim::Simulation, data)
    counts = finalPopulationCount(sim; include_dead=data.include_dead)
    return ismissing(counts) ? missing : _restrict(counts, data.cell_types)
end

#! `compute` of `endpointPopulationFractionQoI`. The denominator is every live cell, so `total` is
#! summed BEFORE restricting -- matching `endpointPopulationFractions`, which likewise divides by the
#! whole population and only then filters in `_averageStatDicts`. `_restrict` here, not only in
#! `reduce`: the post-processing sink calls `compute` and never `reduce`, so a builder that filtered
#! only in its reducer would write a column for every cell type and silently ignore `cell_types`.
function _endpointFractionsOf(sim::Simulation, data)
    counts = finalPopulationCount(sim; include_dead=data.include_dead)
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

"""
    endpointPopulationCountQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving mean final-snapshot counts per cell type across a
monad's replicates.

The keyword arguments travel in the QoI's `data` slot and its `compute` is a named top-level
function, so a calibration's `problem.jld2` is complete and `resumeABC(Calibration(id))` needs no
`problem=`.

Its value is a `Dict{String,Float64}` of cell type → mean count: the same shape
[`endpointPopulationCounts`](@ref) returns, so `observed_data` does not change between them. It
defines no `reduce`, so ModelManager's default per-key mean averages the replicates, and the two
agree up to floating-point summation order.

[`populationCountQoI`](@ref) measures the same quantity at the final snapshot, under a different
name and a different family of sink columns.

# Keyword Arguments
- `cell_types`: restrict to these cell types. `nothing` (default) measures every cell type present.
- `include_dead`: whether to include dead cells in the count (default `false`).

# Examples
```julia
problem = CalibrationProblem(inputs, parameters, observed, endpointPopulationCountQoI(), mseDistance)
```
"""
function endpointPopulationCountQoI(; cell_types::Union{Nothing,Vector{String}}=nothing,
                                      include_dead::Bool=false)
    return QoI("endpoint_population_count", _endpointCountsOf; data=(; cell_types, include_dead))
end

"""
    endpointPopulationFractionQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving mean final-snapshot fractions of total cells per cell
type across a monad's replicates. Restorable like [`endpointPopulationCountQoI`](@ref): the keyword
arguments travel in `data`, so resuming needs no `problem=`.

Its value is a `Dict{String,Float64}` of cell type → mean fraction, the same shape
[`endpointPopulationFractions`](@ref) returns and agreeing with it up to floating-point summation
order; like the other builders it defines no `reduce` and is averaged by ModelManager's default
per-key mean. The ratio is taken per simulation and only then averaged — mean-of-ratios, not
ratio-of-means — which is why it fits a per-simulation `compute` at all.

# Keyword Arguments
- `cell_types`: restrict to these cell types. `nothing` (default) measures every cell type present.
- `include_dead`: whether to include dead cells in the denominator (default `false`).

# Examples
```julia
problem = CalibrationProblem(inputs, parameters, observed, endpointPopulationFractionQoI(), mseDistance)
```
"""
function endpointPopulationFractionQoI(; cell_types::Union{Nothing,Vector{String}}=nothing,
                                         include_dead::Bool=false)
    return QoI("endpoint_population_fraction", _endpointFractionsOf; data=(; cell_types, include_dead))
end

"""
    meanPopulationTimeSeriesQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving the mean population time series per cell type across
a monad's replicates. Restorable like [`endpointPopulationCountQoI`](@ref): the keyword arguments
travel in `data`, so resuming needs no `problem=`.

Its value is a `Dict{String,Vector{Float64}}` of cell type → mean count over time, the same shape
[`meanPopulationTimeSeries`](@ref) returns and agreeing with it up to floating-point summation order,
so a `CalibrationProblem` using it wants `observed_data` values on that same time grid. Its `compute`
reports one replicate's counts on that replicate's own grid and it defines no `reduce`, so
ModelManager's default per-key mean averages them elementwise. No grid check is needed: replicates of
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

################## Per-snapshot population counts ##################

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
default applies: a mean per cell type. [`endpointPopulationCountQoI`](@ref) measures the same thing at
the final snapshot, under a different name and a different family of sink columns, and reduces under
that same default. Neither can trip the default's one requirement — that the replicates agree about
their keys — because [`populationCount`](@ref) keys every cell type the model declares rather than
only those with living cells, and the replicates of a monad share a config.

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
    #! from a calibration's `problem.jld2` (the restorability note above).
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
    #! The key is the bare cell type: ModelManager names the column `"<qoi name>.<key>"`, so a
    #! `"count_"` prefix (which 0.3.x carried, when the sink was one flat namespace) would only
    #! give `population_count.count_default`.
    return Dict(name => n for (name, n) in counts)
end
