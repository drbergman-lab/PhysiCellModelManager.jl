```@meta
CollapsedDocStrings = true
```

# Loader

PhysiCell output loading is provided by the standalone
[PhysiCellOutput.jl](https://github.com/drbergman-lab/PhysiCellOutput.jl) package, which
PhysiCellModelManager.jl re-exports. PhysiCellOutput is *path-based* and stateless: its types
(`PhysiCellSnapshot`, `PhysiCellSequence`, `AbstractPhysiCellSequence`) are keyed on an
output-folder path, and its loaders (`loadCells!`, `loadSubstrates!`, `loadMesh!`,
`loadGraph!`), metadata readers (`cellLabels`, `cellTypeToNameDict`, `substrateNames`), and
helpers (`AgentID`, `AgentDict`, `cellDataSequence`, `pathToOutputFileBase`, `pathToOutputXML`)
operate directly on those objects. See the
[PhysiCellOutput.jl documentation](https://github.com/drbergman-lab/PhysiCellOutput.jl) for the
full folder-based API.

PhysiCellModelManager.jl re-adds its database identity on top: the methods documented below
accept a simulation ID (`<:Integer`) or a [`Simulation`](@ref), convert it to an output folder
via [`pathToOutputFolder`](@ref) (a ModelManager function), and delegate to PhysiCellOutput.
Object-based methods (e.g. `loadCells!(snapshot)`, `cellDataSequence(sequence, …)`) are used
directly from PhysiCellOutput and need no PhysiCellModelManager-specific method.

```@autodocs
Modules = [PhysiCellModelManager]
Pages = ["loader.jl"]
Private = false
```
