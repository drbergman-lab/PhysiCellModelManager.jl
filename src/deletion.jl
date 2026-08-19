"""
    clearSimulatorArtifacts(::PhysiCellSimulator)

Remove build artifacts from all custom code folders for a PhysiCell project.

Deletes every compiled executable, the compilation logs (`compilation.log`,
`compilation.err`), and the macros file (`macros.txt`) from each subdirectory of the custom
code location. Executables are named for the PhysiCell version they were built against, so a
folder can hold one per version ever used there; all of them go.
"""
function ModelManager.clearSimulatorArtifacts(::PhysiCellSimulator)
    for custom_code_folder in (readdir(locationPath(:custom_code), sort=false, join=true) |> filter(x -> isdir(x)))
        for filename in readdir(custom_code_folder; sort=false)
            path_to_file = joinpath(custom_code_folder, filename)
            if isfile(path_to_file) && isCompilationArtifact(filename)
                rm_hpc_safe(path_to_file; force=true)
            end
        end
    end
end