export endpointPopulationCounts, endpointPopulationFractions, mseDistance

################## Summary Statistics ##################

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
    sim_ids = constituentIDs(Monad, monad_id)
    counts_per_sim = [finalPopulationCount(sim_id; include_dead=include_dead) for sim_id in sim_ids]
    return _averageStatDicts(counts_per_sim, cell_types)
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
    fractions_per_sim = map(sim_ids) do sim_id
        counts = finalPopulationCount(sim_id; include_dead=include_dead)
        total = sum(values(counts))
        total == 0 ? Dict(k => 0.0 for k in keys(counts)) : Dict(k => Float64(v) / total for (k, v) in counts)
    end
    return _averageStatDicts(fractions_per_sim, cell_types)
end

################## Distance Functions ##################

"""
    mseDistance(simulated::Dict{String,<:Any}, observed::Dict{String,<:Any})

Built-in distance function: mean squared error across matched keys.

Works for both scalar and vector values:
- Scalar values (endpoint data): `(sim - obs)^2`
- Vector values (time-series data): `mean((sim .- obs).^2)`

The per-key MSE contributions are averaged across all keys in `observed`.
Keys present in `observed` but missing from `simulated` contribute a squared error based
on the observed value alone (i.e., simulated is treated as zero for that key).
Pass as `distance` in a [`CalibrationProblem`](@ref).
"""
function mseDistance(simulated::Dict{String,<:Any}, observed::Dict{String,<:Any})
    if any(!in(keys(observed)), keys(simulated))
        @warn """
        Found keys in simulated that are not in the observed dict.
        - Keys in simulated but not observed: $(setdiff(keys(simulated), keys(observed)))
        - These will not contribute to the MSE calculation.
        """ maxlog=1
    end
    if any(!in(keys(simulated)), keys(observed))
        @warn """
        Found keys in observed that are not in the simulated dict.
        - Keys in observed but not simulated: $(setdiff(keys(observed), keys(simulated)))
        - The MSE will be calculated by assuming the simulated value is 0.
        """ maxlog=1
    end
    n = length(observed)
    n == 0 && return 0.0
    total = 0.0
    for (k, obs_val) in observed
        sim_val = get(simulated, k, _zeroLike(obs_val))
        total += _mseContribution(sim_val, obs_val)
    end
    return total / n
end

# Scalar contribution: single squared error term
_mseContribution(sim::Real, obs::Real) = Float64((sim - obs)^2)

# Vector contribution: mean squared error across the time series
function _mseContribution(sim::AbstractVector{<:Real}, obs::AbstractVector{<:Real})
    length(sim) == length(obs) || throw(DimensionMismatch(
        "Simulated and observed vectors have different lengths ($(length(sim)) vs $(length(obs))). " *
        "Ensure the time grids match."
    ))
    return mean((sim .- obs) .^ 2)
end

# Zero sentinel that matches the shape of the observed value (used for missing keys)
_zeroLike(::Real) = 0.0
_zeroLike(v::AbstractVector{<:Real}) = zeros(Float64, length(v))

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
