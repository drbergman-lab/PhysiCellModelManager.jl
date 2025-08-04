# Known limitations
## Always select all simulations associated with a `Monad`
Anytime a group of simulation replicates (a `Monad` in PhysiCellModelManager.jl internals) is requested, all simulations in that group are used, regardless of the value of `n_replicates`.

## Initial conditions not loaded when launching PhysiCell Studio for a simulation.
When launching PhysiCell Studio from PhysiCellModelManager.jl, the initial conditions (cells and substrates) are not loaded.

## Limited intracellular models
Currently only supports ODE intracellular models (using libRoadRunner).
Does not support MaBoSS or dFBA.