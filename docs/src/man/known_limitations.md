# [Known limitations](@id known_limitations_man)

Behavior that is known to surprise, and what to do about it; the headings alone are the list.

## [Always select all simulations associated with a `Monad`](@id all_simulations_in_monad)

!!! tierbrief
    Whenever a group of simulation replicates (a `Monad`) is requested, all simulations in that
    group are used, regardless of the value of `n_replicates`.

## Initial conditions not loaded when launching PhysiCell Studio for a simulation

!!! tierbrief
    When launching PhysiCell Studio from PhysiCellModelManager.jl, the initial conditions (cells and
    substrates) are not loaded. See [Using PhysiCell Studio](@ref physicell_studio_man).

## Limited intracellular models

!!! tierbrief
    Only ODE intracellular models are supported, through libRoadRunner. MaBoSS and dFBA are not.

## Compiled executables are not keyed to the machine that built them

!!! tierbrief
    PCMM names each executable for the PhysiCell version it was built against, so it recompiles when
    that version changes. It does not track the operating system, architecture, or compiler flags
    used, so moving a `data/` folder to a machine those differ on will have PCMM reuse an executable
    that cannot run there.

!!! tierbrief
    **The fix.** Pass `force_recompile=true` to `run` once on the new machine, or delete the
    `pcmm_build/` folders under `data/inputs/custom_codes/`.
