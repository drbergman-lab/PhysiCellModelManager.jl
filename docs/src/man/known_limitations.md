# Known limitations
## Always select all simulations associated with a `Monad`
Anytime a group of simulation replicates (a `Monad` in PhysiCellModelManager.jl internals) is requested, all simulations in that group are used, regardless of the value of `n_replicates`.
If the number of simulations in the group is less than `n_replicates`, then additional simulations are run to reach `n_replicates`.
Note: if `use_previous=false`, then `n_replicates` will be run regardless and the returned `Monad` will only have the newly-run simulations.
If you do need an upper bound on the number of simulations in such a grouping, submit an issue.
It is assumed that most, if not all use cases, will benefit from more simulations.

## Initial conditions not loaded when launching PhysiCell Studio for a simulation.
When launching PhysiCell Studio from PhysiCellModelManager.jl, the initial conditions (cells and substrates) are not loaded.

## Limited intracellular models
Currently only supports ODE intracellular models (using libRoadRunner).
Does not support MaBoSS or dFBA.