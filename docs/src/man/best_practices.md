# Best practices

## Do NOT manually edit files inside `inputs`.
If parameter values need to be changed, use variations as shown in `VCT/GenerateData.jl`.
Let PhysiCellModelManager.jl manage the databases that track simulation parameters.