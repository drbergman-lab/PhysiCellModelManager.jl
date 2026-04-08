"""
    clearSimulatorArtifacts(::PhysiCellSimulator)

Remove build artifacts from all custom code folders for a PhysiCell project.

Deletes the compiled executable, compilation logs (`compilation.log`, `compilation.err`),
and the macros file (`macros.txt`) from each subdirectory of the custom code location.
"""
function ModelManager.clearSimulatorArtifacts(::PhysiCellSimulator)
    for custom_code_folder in (readdir(locationPath(:custom_code), sort=false, join=true) |> filter(x -> isdir(x)))
        files = [baseToExecutable("project"), "compilation.log", "compilation.err", "macros.txt"]
        for file in files
            rm_hpc_safe(joinpath(custom_code_folder, file); force=true)
        end
    end
end