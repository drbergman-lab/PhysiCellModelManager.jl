export endpointPopulationCounts, endpointPopulationFractions, meanPopulationTimeSeries
export endpointPopulationCountQoIs, endpointPopulationFractionQoIs, meanPopulationTimeSeriesQoIs

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

Returns a `Dict{String,Float64}` mapping cell type name → mean count. Pass this (or a
closure wrapping it) as `summary_statistic` in a [`CalibrationProblem`](@ref).

# Arguments
- `monad_id`: ID of the monad whose replicates to average.
- `cell_types`: Optional `Vector{String}` to restrict which cell types are included.
  If `nothing`, all cell types present in the simulation are included.
- `include_dead`: Whether to include dead cells in the count (default `false`).

# Examples
```julia
problem = CalibrationProblem(
    inputs, parameters, observed,
    monad_id -> endpointPopulationCounts(monad_id; cell_types=["tumor", "immune"]),
    mseDistance
)
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

Returns a `Dict{String,Float64}` mapping cell type name → mean fraction. Pass this (or a
closure wrapping it) as `summary_statistic` in a [`CalibrationProblem`](@ref).

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
Pass this (or a closure wrapping it) as `summary_statistic` in a
[`CalibrationProblem`](@ref) when calibrating against time-series data.
The corresponding `observed_data` values should be `Vector{Float64}` on the same time grid.

# Arguments
- `monad_id`: ID of the monad whose replicates to average.
- `cell_types`: Optional `Vector{String}` to restrict which cell types are included.
  If `nothing`, all cell types present in the simulation are included.
- `include_dead`: Whether to include dead cells in the count (default `false`).

# Examples
```julia
problem = CalibrationProblem(
    inputs, parameters, observed,
    monad_id -> meanPopulationTimeSeries(monad_id; cell_types=["tumor"]),
    mseDistance
)
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
# The `Vector{QoI}` form of the three summary statistics above, so the same quantity reaches
# sensitivity analysis and the post-processing sink and not just `CalibrationProblem`.
#
# One QoI per cell type, named for the cell type, because a summary statistic's reduced value is
# wrapped as `Dict(name => value)` and `mseDistance` compares that against `observed_data` keyed by
# cell type. A single QoI named "counts" would nest one level too deep. That is also why
# `cell_types` is required: the vector is built before any simulation runs, so it cannot discover
# them from output -- the monad-level functions above remain the discover-everything path.
#
# Each builder keeps its own `reduce`. The three statistics disagree about whether a cell type
# absent from a replicate is zero-filled and about summation order, so a shared reducer would
# silently change one of them; the tests assert `==` against the monad-level functions to hold that.
# The one thing they do share is factored into `_reduceKept`.
"""
    _reduceKept(combine)

Wrap `combine` so it sees only the replicates that produced a value.

Every builder below needs the same two things, and neither is the default: ModelManager hands
`reduce` every replicate's value including `missing`, so a plain `mean` would return `missing` for
any monad with a pruned replicate; and a monad with nothing readable reduces to `missing` rather
than erroring. What `combine` does with the survivors is what differs between the three, so that
part stays explicit at each call site.
"""
_reduceKept(combine) = per_sim -> begin
    kept = filter(!ismissing, per_sim)
    isempty(kept) && return missing
    return combine(kept)
end

"""
    endpointPopulationCountQoIs(cell_types::Vector{String}; include_dead::Bool=false)

Return one [`QoI`](@ref ModelManager.QoI) per cell type giving mean final-snapshot counts across a
monad's replicates.

Equivalent to [`endpointPopulationCounts`](@ref) with the same `cell_types`, but usable anywhere a
`QoI` is accepted — `CalibrationProblem`'s `summary_statistic`, `run(::GSAMethod, ...; functions=)`,
or `run(...; post_processor=)`.

# Arguments
- `cell_types`: the cell types to measure. Required: the QoIs are built before any simulation runs,
  so the cell types cannot be discovered from output.

# Keyword Arguments
- `include_dead`: whether to include dead cells in the count (default `false`).

# Examples
```julia
qois = endpointPopulationCountQoIs(["tumor", "immune"])
problem = CalibrationProblem(inputs, parameters, observed, qois, mseDistance)
```
"""
function endpointPopulationCountQoIs(cell_types::Vector{String}; include_dead::Bool=false)
    return [QoI(cell_type,
                sim -> begin
                    counts = finalPopulationCount(sim; include_dead=include_dead)
                    #! Zero-fill, matching `finalPopulationCount(::Monad)`: a cell type absent from a
                    #! replicate contributes a 0 rather than shrinking the denominator.
                    ismissing(counts) ? missing : get(counts, cell_type, 0)
                end;
                #! A generator, not `mean(kept)`: `finalPopulationCount(::Monad)` reduces
                #! `mean(get(c, k, 0) for c in ...)`, and a generator accumulates sequentially where
                #! an array may not. Matching each function's own form is what lets the migration
                #! test assert `==` rather than a tuned tolerance.
                reduce = _reduceKept(kept -> mean(x for x in kept)))
            for cell_type in cell_types]
end

"""
    endpointPopulationFractionQoIs(cell_types::Vector{String}; include_dead::Bool=false)

Return one [`QoI`](@ref ModelManager.QoI) per cell type giving mean final-snapshot fractions of
total cells across a monad's replicates.

Equivalent to [`endpointPopulationFractions`](@ref) with the same `cell_types`. The ratio is taken
per simulation and only then averaged — mean-of-ratios, not ratio-of-means — which is what the
monad-level function does and is why it fits a per-simulation `compute` at all.

# Arguments
- `cell_types`: the cell types to measure. Required, as for [`endpointPopulationCountQoIs`](@ref).

# Keyword Arguments
- `include_dead`: whether to include dead cells in the denominator (default `false`).

# Examples
```julia
qois = endpointPopulationFractionQoIs(["tumor", "immune"])
problem = CalibrationProblem(inputs, parameters, observed, qois, mseDistance)
```
"""
function endpointPopulationFractionQoIs(cell_types::Vector{String}; include_dead::Bool=false)
    return [QoI(cell_type,
                sim -> begin
                    counts = finalPopulationCount(sim; include_dead=include_dead)
                    ismissing(counts) && return missing
                    #! `_averageStatDicts` reads the per-simulation dict with `get(d, k, 0)`, and the
                    #! dict only holds keys present in that replicate's counts -- so a cell type the
                    #! replicate does not have contributes 0.0, not a shrunken denominator.
                    haskey(counts, cell_type) || return 0.0
                    total = sum(values(counts))
                    return total == 0 ? 0.0 : Float64(counts[cell_type]) / total
                end;
                #! A materialised `Vector`, unlike the counts builder's generator: `_averageStatDicts`
                #! builds `vals = [...]` and calls `mean(vals)`. The two disagree, so each is matched
                #! to its own form rather than unified.
                reduce = _reduceKept(kept -> mean(Float64[x for x in kept])))
            for cell_type in cell_types]
end

"""
    meanPopulationTimeSeriesQoIs(cell_types::Vector{String}; include_dead::Bool=false)

Return one [`QoI`](@ref ModelManager.QoI) per cell type giving the mean population time series
across a monad's replicates.

Equivalent to [`meanPopulationTimeSeries`](@ref) with the same `cell_types`. Each QoI reduces to a
`Vector{Float64}` on the shared time grid, so a `CalibrationProblem` using these wants
`observed_data` values on that same grid.

Unlike the two endpoint builders, a replicate lacking a cell type is **excluded** from that cell
type's average rather than contributing a zero — `MonadPopulationTimeSeries` divides by the number
of replicates having the cell type, and zero-filling here would divide by a larger denominator and
return a smaller number.

# Arguments
- `cell_types`: the cell types to measure. Required, as for [`endpointPopulationCountQoIs`](@ref).

# Keyword Arguments
- `include_dead`: whether to include dead cells in the count (default `false`).

# Examples
```julia
qois = meanPopulationTimeSeriesQoIs(["tumor"])
problem = CalibrationProblem(inputs, parameters, observed, qois, mseDistance)
```
"""
function meanPopulationTimeSeriesQoIs(cell_types::Vector{String}; include_dead::Bool=false)
    return [QoI(cell_type,
                sim -> begin
                    spts = SimulationPopulationTimeSeries(sim; include_dead=include_dead, verbose=false)
                    ismissing(spts) && return missing
                    #! The whole grid travels with the counts so that `reduce` can perform the
                    #! cross-replicate time-axis check `MonadPopulationTimeSeries` performs in its
                    #! constructor. `nothing` marks a replicate that has no such cell type, which is
                    #! distinct from a replicate that failed to load.
                    return (time=spts.time, counts=get(spts.cell_count, cell_type, nothing))
                end;
                reduce = _reduceKept(kept -> begin
                    grid = first(kept).time
                    all(k -> k.time == grid, kept) || throw(ArgumentError(
                        "Replicates of this monad have different times in their time series, so " *
                        "cell type \"$(cell_type)\" cannot be averaged over them."))
                    #! No zero-fill, unlike the two endpoint builders: only replicates that HAVE this
                    #! cell type contribute a column, matching `MonadPopulationTimeSeries`, which
                    #! divides by however many it collected rather than by the replicate count.
                    vectors = [k.counts for k in kept if !isnothing(k.counts)]
                    isempty(vectors) && return missing
                    return Vector{Float64}(vec(mean(reduce(hcat, vectors), dims=2)))
                end))
            for cell_type in cell_types]
end
