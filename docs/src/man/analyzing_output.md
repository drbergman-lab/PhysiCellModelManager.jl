# Analyzing output

## Install dependencies
Julia has several packages for plotting.
Here, we will use `Plots.jl` which you can install with
```julia-repl
pkg> add Plots
```

## Loading output

### `PhysiCellSnapshot`
The base unit of PhysiCell output is the `PhysiCellSnapshot`.
These are currently considered PhysiCellModelManager internals and so the API may change.
Each snapshot records the path to the PhysiCell output folder, its index in the sequence of outputs, the time of the snapshot in the simulation, and optionally the cell, substrate, and mesh data at that snapshot.

### `PhysiCellSequence`
A `PhysiCellSequence` is the full sequence of snapshots corresponding to a single PhysiCell simulation.
As with `PhysiCellSnapshot`'s, these are currently considered internals and their API may change.
In addition to the path to the PhysiCell output folder and the vector of `PhysiCellSnapshot`'s, it holds metadata for the simulation.

### `cellDataSequence`
The main function to get sequences of cell data is `cellDataSequence`.
It accepts any of a simulation ID (`<:Integer`), a simulation (`::Simulation`), or a sequence (`::PhysiCellSequence`) and either a single label (`::String`) or a vector of labels (`::Vector{String}`).
For each cell in the simulation (as determined by the cell ID), the output creates a dictionary entry (the key is the integer cell ID) whose value is a named tuple with the input labels as keys as well as `:time`.
This means that if one sets

```julia
data = cellDataSequence(1, "position")
```
Then one can access the positions of the cell with ID 78 by
```julia
cell_78_positions = data[78].position # an Nx3 matrix for the N integer-indexed outputs (ignores the `initial_*` and `final_*` files)
```
and plot the x-coordinates of this cell over time using
```julia
cell_78_times = data[78].time

using Plots
plot(cell_78_times, cell_78_positions[:,1])
```

**Note**: Each call to `cellDataSequence` will load *all* the data unless a `PhysiCellSequence` is passed in.
Plan your analyses accordingly as loading simulation data is not fast.

## Population plots

### Group by Monad
Plotting population plots is one the most basic analysis tasks and PhysiCellModelManager makes it super easy!
If you call `plot` on a `Simulation`, `Monad`, `Sampling`, or the return value of a call to `run` (though not for a sensitivity analysis),
then a sequence of panels will be generated in a single figure.
Each panel will correspond to a `Monad` (replicates using the same parameter values) and will plot mean +/- SD for each cell type.

Finer-grained control of the output is possible, too!
- to include dead cells in your counts: `plot(...; ..., include_dead=true, ...)`
- select a subset of cell types to include: `plot(...; ..., include_cell_type_names="cancer", ...)`
- select a subset of cell types to exclude: `plot(...; ..., exclude_cell_type_names="cancer", ...)`
- choose time units for the x-axis: `plot(...; ..., time_unit=:h, ...)`

The `include_cell_type_names` and `exclude_cell_type_names` can also accept a `Vector{String}` to include or exclude certain cell types, respectively.
Furthermore, if the value of `include_cell_type_names` is a `Vector` and one of its entries is a `Vector{String}`, PhysiCellModelManager will interpret this to sum up those cell types.
In other words, to get the total tumor cell count in addition to the epithelial (`"epi"`) and mesenchymal (`"mes"`) components, you could use
```julia
using Plots
plot(Monad(1); include_cell_type_names=["epi", "mes", ["epi", "mes"]])
``` 

Finally, this makes use of Julia's Plot Recipes (see [RecipesBase.jl](https://docs.juliaplots.org/stable/RecipesBase/)) so any standard plotting keywords can be passed in:
```julia
using Plots
colors = [:blue :red] # Note the absence of a `,` or `;`. This is how Julia requires different series parameters to be passed in 
plot(Simulation(1); color=colors, include_cell_type_names=["cd8", "cancer"]) # will plot cd8s in blue and cancer in red.
```

### Group by cell type
Invert the above by including all data for a single cell type across all monads in a single panel with a call to `plotbycelltype`.
This function works on any `T<:AbstractTrial` (`Simulation`, `Monad`, `Sampling`, or `Trial`) as well as any `PCMMOutput` object (the return value to `run`).
Everything above for `plot` applies here.

```julia
using Plots
plotbycelltype(Sampling(1); include_cell_type_names=["epi", "mes", ["epi", "mes"]], color=[:blue :red :purple], labels=["epi" "mes" "both"], legend=true)
```

## Substrate analysis
PhysiCellModelManager supports two ways to summarize substrate information over time.

### `AverageSubstrateTimeSeries`
An `AverageSubstrateTimeSeries` gives the time series for the average substrate across the entire domain.

```julia
simulation_id = 1
asts = PhysiCellModelManager.AverageSubstrateTimeSeries(simulation_id)
using Plots
plot(asts.time, asts["oxygen"])
```

### `ExtracellularSubstrateTimeSeries`
An `ExtracellularSubstrateTimeSeries` gives the time series for the average substrate concentration in the extracellular space neighboring all cells of a given cell type.
In a simulation with `cd8` cells and `IFNg` diffusible substrate, plot the average concentration of IFNg experienced by CD8+ T cells using the following:

```julia
simulation_id = 1
ests = PhysiCellModelManager.ExtracellularSubstrateTimeSeries(simulation_id)
using Plots
plot(ests.time, ests["cd8"]["IFNg"])
```

## Motility analysis
The `motilityStatistics` function returns the time alive, distance traveled, and mean speed for each cell in the simulation.
For each cell, these values are split amongst the cell types the given cell assumed throughout (or at least at the save times).
To calculate these values, the cell type at the start of the save interval is used and the net displacement is used to calculate the speed.
Optionally, users can pass in a coordinate direction to only consider speed in a given axis.

```julia
simulation_id = 1
mss = motilityStatistics(simulation_id)
all_mean_speeds_as_mes = [ms["mes"].speed for ms in mss if haskey(ms, "mes")] # concatenate all speeds as a "mes" cell type (if the given cell ever was a "mes")
all_times_as_mes = [ms["mes"].time for ms in mss if haskey(ms, "mes")] # similarly, get the time spent in the "mes" state
mean_mes_speed = all_mean_speeds_as_mes .* all_times_as_mes |> sum # start computing the weighted average of their speeds
mean_mes_speed /= sum(all_times_as_mes) # finish computing weighted average
```

```julia
mss = motilityStatistics(simulation_id; direction=:x) # only consider the movement in the x direction
```

## Pair correlation function (PCF)
Sometimes referred to as radial distribution functions, the pair correlation function (PCF) computes the density of target cells around center cells.
If the two sets of cells are the same (centers = targets), this is called PCF.
If the two are not equal, this is sometimes called cross-PCF.
Both can be computed with a call to `PhysiCellModelManager.pcf` (or just `pcf` if `using PairCorrelationFunction` has been called).

### Arguments
PCF computations can readily be called on `PhysiCellSnapshot`'s, `PhysiCellSequence`'s, or `Simulation`'s.
If the first argument in a call to `pcf` is an `Integer`, this is treated as a simulation ID.
If this is followed by an index (of type `Integer` or value `:initial` or `:final`), this is treated as a snapshot; otherwise, it computes the PCF for the entire simulation.

The next argument is the cell type to use as the center cells as either a `String` or `Vector{String}`, representing the name of the cell type(s).
If the target cells are different from the center cells, the next argument is the target cell type as either a `String` or `Vector{String}`.
If omitted, the target cell type is the same as the center cell type and a (non-cross) PCF is computed.
The resulting sets of center and target cell types must either be identical or have no overlap.

### Keyword arguments
The following keyword arguments are available:
- `include_dead::Union{Bool, Tuple{Bool,Bool}} = false`: whether to include dead cells in the PCF computation.
  - If `true`, all cells are included.
  - If `false`, only live cells are included.
  - If a tuple, the first value is for the center cells and the second is for the target cells.
- `dr::Float64 = 20.0`: the step size for the radial bins in micrometers.

### Output
The output of `pcf` is a `PCMMPCFResult` object which has two fields: `time` and `pcf_result`.
The `time` field is always a vector of the time points at which the PCF was computed, even if computing PCF for a single snapshot.
The `pcf_result` is of type `PairCorrelationFunction.PCFResult` and has two fields: `radii` and `g`.
The `radii` is the set of cutoffs used to compute the PCF and `g` is either a vector or a matrix of the PCF values of size `length(radii)-1` by `length(time)`.

### Plotting
An API to make use of the `PairCorrelationFunction` package plotting interface is available through the `plot` function.
Simply pass in the `PCMMPCFResult`!
You can pass in as many such objects as you like or pass in a `Vector{PCMMPCFResult}`.
In this case, these are interpreted as stochastic realizations of the same PCF and summary statistics are used to plot.
See the `PairCorrelationFunction` documentation for more details.

The PhysiCellModelManager implementation supports two keyword arguments:
- `time_unit::Symbol = :min`: the time unit to use for the time axis (only relevant if the `PCMMPCFResult` has more than one time point).
  - The default is `:min` and the other options are `:s`, `:h`, `:d`, `:w`, `:mo`, `:y`.
- `distance_unit::Symbol = :um`: the distance unit to use for the distance axis.
  - The default is `:um` and the other options are `:mm` and `:cm`.

Finally, a keyword argument supported by `PairCorrelationFunction` is `colorscheme` which can be used to change the colorscheme of the color map.
PhysiCellModelManager overrides the default from `PairCorrelationFunction` (`:tofino`) with `:cork` to use white to represent values near one.

### Examples
```julia
simulation_id = 1
result = PhysiCellModelManager.pcf(simulation_id, "cancer", "cd8") # using PairCorrelationFunction will obviate the need to prefix with `PhysiCellModelManager`
plot(result) # heatmap of proximity of (living) cd8s to (living) cancer cells throughout simulation 1
```
```julia
monad = Monad(1) # let's assume that there are >1 simulations in this monad
results = [PhysiCellModelManager.pcf(simulation_id, :final, "cancer", "cd8") for simulation_id in simulationIDs(monad)] # one vector of PCF values for each simulation at the final snapshot
plot(results) # line plot of average PCF values against radius across the monad +/- 1 SD
```
```julia
monad = Monad(1) # let's assume that there are >1 simulations in this monad
results = [PhysiCellModelManager.pcf(simulation_id, "cancer", "cd8") for simulation_id in simulationIDs(monad)] # one matrix of PCF values for each simulation across all time points
plot(results) # heatmap of average PCF values with time on the x-axis and radius on the y-axis; averages omit NaN values that can occur at higher radii
```

## Graph analysis
Every PhysiCell simulation produces three different directed graphs at each save time point.
For each graph, the vertices are the cell agents and the edges are as follows:
- `:neighbors`: the cells overlap based on their positions and radii
- `:attachments`: manually-defined attachments between cells
- `:spring_attachments`: spring attachments formed automatically using attachment rates
Each of these graphs is expected to be symmetric, i.e., if cell A is attached to cell B, then cell B is attached to cell A.
Nonetheless, PhysiCellModelManager holds the data in a directed graph.

Currently, PhysiCellModelManager supports computing connected components for any of these graphs using the [`connectedComponents`](@ref) function.
For an [`PhysiCellModelManager.AbstractPhysiCellSequence`](@ref) object, the graphs can be loaded using the [`loadGraph!`](@ref) function for any other analysis.

### Examples
For all examples that follow, we will assume a [`PhysiCellSnapshot`](@ref) object called `snapshot` has been created, e.g., as follows:
```julia
simulation_id = 1
index = :final
snapshot = PhysiCellSnapshot(simulation_id, index)
```

To get a list of the connected components for the `:neighbors` graph for all living cells in a simulation at the final timepoint, use
```julia
connected_components = connectedComponents(snapshot) # defaults to the :neighbors graph, all cells, and exclude dead cells
```
The `connected_components` object is a `Dict` with the cell type names in a single vector as the only key with value a vector of vectors.
Each element is a vector of the cell IDs belonging to that connected component in the wrapper type [`PhysiCellModelManager.AgentID`](@ref).

If you want to compute connected components for subsets of cells, pass in a vector of vectors of cell type names (`String`s) such that each vector corresponds to a subset of cell types.
```julia
subset_1 = ["cd8_active", "cd8_inactive"]
subset_2 = ["cancer_epi", "cancer_mes"]
connected_components = connectedComponents(snapshot; include_cell_type_names=[subset_1, subset_2])
```
In this case, the `connected_components` object is a `Dict` with `subset_1` and `subset_2` as the keys (the values stored in them, not the strings `"subset_1"` and `"subset_2"`).
The value `connected_components[subset_1]` is a vector of vectors of the cell IDs belonging to each connected component just considering the cells in `subset_1`.
Similarly for `subset_2`.

Including dead cells is possible though not recommended.
This is because dead cells automatically clear their neighbors and attachments.
The optional keyword argument `include_dead` can be set to `true` to include dead cells in the graph.
```julia
connected_components = connectedComponents(snapshot; include_dead=true)
```

Finally, to combine a single connected component with the dataframe of cell data, the following can be used:
```julia
connected_components = connectedComponents(snapshot)
connected_components_1 = connected_components |> # julia's pipe operator
                         values |>  # get the value for each key
                         first |> # get the connected components for the first subset of cells (in this case there's only one subset consisting of all cells)
                         first # get the first connected component for this subset

loadCells!(snapshot) # make sure the cell data is loaded
cells_df = snapshot.cells # this is the cell data

agent_ids = DataFrame(ID=[a.id for a in connected_components_1]) # get the IDs for the agents in the connected component
component_df = rightjoin(cells_df, agent_ids, on=:ID) # join on the agent IDs, keeping only the rows in the connected component
```