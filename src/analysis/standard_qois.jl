export endpointPopulationCounts, endpointPopulationFractions, meanPopulationTimeSeries
export endpointPopulationCountQoI, endpointPopulationFractionQoI, meanPopulationTimeSeriesQoI

################## PhysiCell-specific Calibration Summary Statistics ##################
#
# These summary statistics are PhysiCell-specific: they read simulation output files
# via the PhysiCell loader (finalPopulationCount, MonadPopulationTimeSeries).
# The framework-agnostic calibration infrastructure (CalibrationProblem, ABCSMC,
# mseDistance, etc.) lives in ModelManager/src/calibration/.
#

"""
    endpointPopulationCounts(monad_id::Int; cell_types=nothing, include_dead::Bool=false)

Built-in summary statistic: mean final-snapshot cell counts across all replicates in a monad.

Returns a `Dict{String,Float64}` mapping cell type name → mean count.

This is a **monad-level** function: it takes a monad ID and does its own averaging. Since
ModelManager 0.9 a `summary_statistic` measures a single `Simulation` and ModelManager reduces the
replicates, so this is no longer a valid `summary_statistic` argument — passing it fails when the
first monad is measured. Use [`endpointPopulationCountQoI`](@ref), which measures the same
quantity in that shape. Keep this one for analysing a monad directly.

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

This is a **monad-level** function and not a valid `summary_statistic`
argument — see [`endpointPopulationCounts`](@ref) for why. Use
[`endpointPopulationFractionQoI`](@ref) for calibration and keep this one for analysing a monad
directly.

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
This is a **monad-level** function and not a valid `summary_statistic`
argument — see [`endpointPopulationCounts`](@ref) for why. Use [`meanPopulationTimeSeriesQoI`](@ref)
when calibrating against time-series data, and keep this one for analysing a monad directly.
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
# A single QoI is what makes that possible. `_evaluateSummary` passes one QoI's value through
# unwrapped and only keys a `Dict` by QoI name when given several, so one Dict-valued QoI hands
# `mseDistance` the flat cell-type-keyed dict it compares against `observed_data`. It also means
# `cell_types` can stay optional: one QoI discovers them from the simulation like the monad-level
# functions do, where a vector of QoIs would have to name them at construction.
#
# Each `reduce` is the corresponding monad-level function's own aggregation step, so the two agree by
# construction rather than by coincidence — which matters because the three disagree with each other
# about whether an absent cell type is zero-filled and about summation order. The tests still assert
# `==` between them.
#
# The one Dict used to cost something: sensitivity analysis wanted a `Real` from `reduce`, so these
# reached calibration and the sink but not `functions=`. ModelManager spreads a keyed reduce
# into one analysis per key -- labelled `"<qoi name>.<key>"`, the same reading the sink gives it --
# so the two endpoint builders now serve all three consumers with no per-cell-type rewrite.
#
# `meanPopulationTimeSeriesQoI` still does not: its values are `Vector`s, and a `Vector` is
# deliberately not spread by index, because only length can be checked across a design and equal
# length is not equal meaning. Reduce a series to a scalar to ask a sensitivity question about it.

"""
    _reduceKept(combine)

Wrap `combine` so it sees only the replicates that produced a value.

Neither half is the default: ModelManager hands `reduce` every replicate's value including
`missing`, so a plain `mean` would return `missing` for any monad with a pruned replicate; and a
monad with nothing readable reduces to `missing` rather than erroring.
"""
_reduceKept(combine) = per_sim -> begin
    #! `collect(skipmissing(...))`, not `filter(!ismissing, ...)`: filter keeps the
    #! `Union{Missing,T}` element type, so `combine` would be handed a vector no method written for
    #! `Vector{<:Dict}` can accept -- `_averageStatDicts` among them.
    kept = collect(skipmissing(per_sim))
    isempty(kept) && return missing
    return combine(kept)
end

#! Restrict a per-simulation dict to `cell_types`, or leave it alone when none were named.
_restrict(d, cell_types) = isnothing(cell_types) ? d : filter(p -> p.first in cell_types, d)

"""
    endpointPopulationCountQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving mean final-snapshot counts per cell type across a
monad's replicates.

Its value is a `Dict{String,Float64}` of cell type → mean count: the same thing
[`endpointPopulationCounts`](@ref) returns, so `observed_data` does not change between them.

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
    return QoI("endpoint_population_count",
               sim -> begin
                   counts = finalPopulationCount(sim; include_dead=include_dead)
                   return ismissing(counts) ? missing : _restrict(counts, cell_types)
               end;
               #! `finalPopulationCount(::Monad)`'s own aggregation: union of the keys, and a
               #! generator mean that zero-fills a cell type a replicate does not have.
               reduce = _reduceKept(kept -> begin
                   all_keys = union(keys.(kept)...)
                   return Dict{String,Float64}(k => mean(get(c, k, 0) for c in kept) for k in all_keys)
               end))
end

"""
    endpointPopulationFractionQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving mean final-snapshot fractions of total cells per cell
type across a monad's replicates.

Its value is a `Dict{String,Float64}` of cell type → mean fraction, matching
[`endpointPopulationFractions`](@ref). The ratio is taken per simulation and only then averaged —
mean-of-ratios, not ratio-of-means — which is why it fits a per-simulation `compute` at all.

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
    return QoI("endpoint_population_fraction",
               sim -> begin
                   counts = finalPopulationCount(sim; include_dead=include_dead)
                   ismissing(counts) && return missing
                   #! The denominator is every live cell, so `total` is summed BEFORE restricting --
                   #! matching `endpointPopulationFractions`, which likewise divides by the whole
                   #! population and only then filters in `_averageStatDicts`.
                   total = sum(values(counts))
                   fractions = total == 0 ? Dict(k => 0.0 for k in keys(counts)) :
                                            Dict(k => Float64(v) / total for (k, v) in counts)
                   #! `_restrict` here, not only in `reduce`: the post-processing sink calls `compute`
                   #! and never `reduce`, so a builder that filtered only in its reducer would write a
                   #! column for every cell type and silently ignore `cell_types`.
                   return _restrict(fractions, cell_types)
               end;
               #! `_averageStatDicts` is the monad-level function's aggregation, reused rather than
               #! reimplemented -- including its zero-fill of a cell type absent from a replicate.
               reduce = _reduceKept(kept -> _averageStatDicts(kept, cell_types)))
end

"""
    meanPopulationTimeSeriesQoI(; cell_types=nothing, include_dead::Bool=false)

Return a [`QoI`](@ref ModelManager.QoI) giving the mean population time series per cell type across
a monad's replicates.

Its value is a `Dict{String,Vector{Float64}}` on the shared time grid, matching
[`meanPopulationTimeSeries`](@ref), so a `CalibrationProblem` using it wants `observed_data` values
on that same grid.

Unlike the two endpoint builders, a replicate lacking a cell type is **excluded** from that cell
type's average rather than contributing a zero — `MonadPopulationTimeSeries` divides by the number
of replicates having the cell type, and zero-filling would divide by a larger denominator.

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
    return QoI("mean_population_time_series",
               sim -> SimulationPopulationTimeSeries(sim; include_dead=include_dead, verbose=false);
               #! `MonadPopulationTimeSeries`'s own aggregation: a column per replicate that HAS the
               #! cell type, then an elementwise mean over however many that was.
               reduce = _reduceKept(kept -> begin
                   grid = first(kept).time
                   all(spts -> spts.time == grid, kept) || throw(ArgumentError(
                       "Replicates of this monad have different times in their time series, so they " *
                       "cannot be averaged over."))
                   names = isnothing(cell_types) ? union(keys.(getfield.(kept, :cell_count))...) : cell_types
                   return Dict{String,Vector{Float64}}(
                       name => vec(mean(reduce(hcat, [spts.cell_count[name] for spts in kept
                                                      if haskey(spts.cell_count, name)]), dims=2))
                       for name in names)
               end))
end
