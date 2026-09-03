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
    #! See the note in `finalPopulationCount(::Monad)` for why this is `@info ... maxlog=1` and
    #! why it is inlined here rather than shared.
    length(fractions_per_sim) < length(sim_ids) &&
        @info "Excluding $(length(sim_ids) - length(fractions_per_sim))/$(length(sim_ids)) replicates of monad $(monad_id) with no output on disk (deleted or pruned)." maxlog=1
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
# ModelManager's `QoI` is one measurement usable by sensitivity analysis, calibration and the
# post-processing sink alike. These builders return the `Vector{QoI}` form of the three summary
# statistics above, so the same quantity can be handed to any consumer instead of only to
# `CalibrationProblem`.
#
# Why a vector rather than one QoI per statistic: `_asSummaryStatistic` wraps the reduced value as
# `Dict(q.name => value)`, and `mseDistance` compares that dict elementwise against `observed_data`,
# whose keys are cell types. One QoI named "counts" would hand it
# `Dict("counts" => Dict("tumor" => ...))` and the comparison would break. One QoI per cell type,
# each named for its cell type, reproduces the flat dict exactly.
#
# The consequence is that `cell_types` is REQUIRED here. A `Vector{QoI}` is built before any
# simulation runs, so the cell types cannot be discovered from output the way the monad-level
# functions above discover them. Use those when you want everything.
#
# Each builder carries its own `reduce`, and they are deliberately NOT shared. The three statistics
# above disagree with each other in ways that are invisible unless reproduced exactly:
#
#   * missing replicates are skipped, never propagated -- so `reduce` must filter, because
#     ModelManager hands it every replicate's value including `missing`, and the default `mean`
#     would return `missing` for the whole monad;
#   * counts and fractions zero-fill a cell type absent from a replicate, the time series does not;
#   * counts averages over a *generator* and fractions over a materialised *Vector*, which is
#     observable: `sum`'s pairwise reduction over an array and the sequential one over a generator
#     produce different `Float64`s from 16 replicates up.
#
# The tests assert these builders equal their monad-level counterparts exactly (`==`, not
# `isapprox`) on a monad with a pruned replicate and on a 16-replicate monad. That equality is the
# whole point: migrating to `QoI` must not quietly move anyone's numbers.

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
                reduce = per_sim -> begin
                    kept = filter(!ismissing, per_sim)
                    isempty(kept) && return missing
                    #! A generator, not `mean(kept)`. `finalPopulationCount(::Monad)` reduces
                    #! `mean(get(c, k, 0) for c in counts_per_sim)`, and a generator accumulates
                    #! sequentially where an array uses pairwise summation -- a different `Float64`
                    #! from 16 replicates up. Bit-exactness is not a promise to users; it is what
                    #! lets the migration test be `==` instead of a hand-tuned tolerance.
                    return mean(x for x in kept)
                end)
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
                reduce = per_sim -> begin
                    kept = filter(!ismissing, per_sim)
                    isempty(kept) && return missing
                    #! A materialised `Vector{Float64}`, unlike the counts builder's generator.
                    #! `_averageStatDicts` builds `vals = [...]` and calls `mean(vals)`, taking
                    #! `sum`'s pairwise path. The two existing functions genuinely disagree here, so
                    #! reproducing each one means matching its own form rather than picking a house
                    #! style for both.
                    return mean(Float64[x for x in kept])
                end)
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
                reduce = per_sim -> begin
                    kept = filter(!ismissing, per_sim)
                    isempty(kept) && return missing
                    grids = unique(k.time for k in kept)
                    length(grids) == 1 || throw(ArgumentError(
                        "Replicates have different times in their time series, so cell type " *
                        "\"$(cell_type)\" cannot be averaged over them. Found $(length(grids)) distinct time grids."))
                    #! No zero-fill: only replicates that HAVE this cell type contribute a column,
                    #! matching `MonadPopulationTimeSeries`, which pushes a column only when
                    #! `spts.cell_count` has the name and then divides by however many it collected.
                    vectors = [k.counts for k in kept if !isnothing(k.counts)]
                    isempty(vectors) && return missing
                    #! `Base.reduce` explicitly: `reduce` is the name of the keyword this closure is
                    #! being passed as, and the same shape as the original's `reduce(hcat, vectors)`.
                    return Vector{Float64}(vec(mean(Base.reduce(hcat, vectors), dims=2)))
                end)
            for cell_type in cell_types]
end
