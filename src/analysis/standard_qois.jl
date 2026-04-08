export endpointPopulationCounts, endpointPopulationFractions, meanPopulationTimeSeries

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
