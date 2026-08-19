# [Known limitations](@id known_limitations_man)
## Always select all simulations associated with a `Monad`
Anytime a group of simulation replicates (a `Monad` in PhysiCellModelManager.jl internals) is requested, all simulations in that group are used, regardless of the value of `n_replicates`.

## Initial conditions not loaded when launching PhysiCell Studio for a simulation.
When launching PhysiCell Studio from PhysiCellModelManager.jl, the initial conditions (cells and substrates) are not loaded.

## Limited intracellular models
Currently only supports ODE intracellular models (using libRoadRunner).
Does not support MaBoSS or dFBA.

## Compiled executables are not keyed to the machine that built them
PCMM names each executable for the PhysiCell version it was built against, so it recompiles when that version changes.
It does not track the operating system, architecture, or compiler flags used.
Move a `data/` folder to a machine those differ on and PCMM will reuse an executable that cannot run there.
Pass `force_recompile=true` to `run` once on the new machine, or delete the `project_*` files from `data/inputs/custom_codes/`.