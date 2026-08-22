"""
    clearSimulatorArtifacts(::PhysiCellSimulator)

Remove build artifacts from all custom code folders for a PhysiCell project.

Deletes the build folder, which holds one executable per PhysiCell version ever compiled
there, along with the compilation logs (`compilation.log`, `compilation.err`) and the macros
file (`macros.txt`), from each subdirectory of the custom code location.

Nothing is matched by pattern: the build folder is a directory PCMM owns and everything else
is named exactly (see `isCompilationArtifact`), so a file the user keeps alongside their
`main.cpp` is never at risk.
"""
function ModelManager.clearSimulatorArtifacts(::PhysiCellSimulator)
    custom_code_folders = readdir(locationPath(:custom_code); sort=false) |> filter(x -> isdir(locationPath(:custom_code, x)))
    for custom_code_folder in custom_code_folders
        path_to_build_folder = buildFolder(custom_code_folder)
        if isdir(path_to_build_folder)
            for filename in readdir(path_to_build_folder; sort=false)
                rm_hpc_safe(joinpath(path_to_build_folder, filename); force=true)
            end
            rm(path_to_build_folder; force=true, recursive=true)
        end
        path_to_custom_code_folder = locationPath(:custom_code, custom_code_folder)
        for filename in readdir(path_to_custom_code_folder; sort=false)
            path_to_file = joinpath(path_to_custom_code_folder, filename)
            if isfile(path_to_file) && isCompilationArtifact(filename)
                rm_hpc_safe(path_to_file; force=true)
            end
        end
    end
end
