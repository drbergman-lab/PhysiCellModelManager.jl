```@meta
CollapsedDocStrings = true
```

# Pruner

Prune files from a simulation immediately after finishing the simulation.

To motivate this functionality, consider the following scenario. A user has been testing their model, including making movies, and is ready to do a large virtual clinical trial with thousands of simulations. Saving all the SVGs will require gigabytes of storage, which is not ideal for the user. The user could choose to create a new variation on the SVG parameters (e.g., increase the SVG save interval), but then PhysiCellModelManager will not be able to reuse previous simulations as they have different variation IDs. Alternatively, the user can use the `PruneOptions` to delete the SVGs after each simulation is finished. This way, there are fewer variations in the database and more capability to reuse simulations.

## Public API
```@autodocs
Modules = [PhysiCellModelmanager]
Pages = ["pruner.jl"]
Private = false
```

## Private API
```@autodocs
Modules = [PhysiCellModelmanager]
Pages = ["pruner.jl"]
Public = false
```