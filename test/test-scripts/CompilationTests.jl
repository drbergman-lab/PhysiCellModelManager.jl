filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

physicell_commit_hash = PhysiCellModelManager.physiCellCommitHash()

#! the PhysiCell version is what names the executable
@test PhysiCellModelManager.executableName() == PhysiCellModelManager.baseToExecutable("project_$(physicell_commit_hash)")
@test PhysiCellModelManager.executableName("1.14.2-download") == PhysiCellModelManager.baseToExecutable("project_1.14.2-download")
@test PhysiCellModelManager.sanitizedForFilename("v1.2_3-4") == "v1.2_3-4"
@test PhysiCellModelManager.sanitizedForFilename("a/b c:d") == "a_b_c_d"
@test PhysiCellModelManager.executableName("a/b") == PhysiCellModelManager.baseToExecutable("project_a_b")

#! files PCMM writes while compiling, and so may delete
for artifact in ["project", "project_abc123", PhysiCellModelManager.executableName(),
    "compilation.log", "compilation.err", "macros.txt", "physicell_commit_hash.txt"]
    @test PhysiCellModelManager.isCompilationArtifact(artifact)
end
for keeper in ["main.cpp", "Makefile", "custom_modules"]
    @test !PhysiCellModelManager.isCompilationArtifact(keeper)
end

#! the bookkeeping of PCMM v0.3.3 and earlier is removed, not read
let path_to_legacy_folder = mktempdir()
    touch(joinpath(path_to_legacy_folder, PhysiCellModelManager.baseToExecutable("project")))
    write(joinpath(path_to_legacy_folder, "physicell_commit_hash.txt"), "$(physicell_commit_hash)\n")
    touch(joinpath(path_to_legacy_folder, "main.cpp"))
    PhysiCellModelManager.removeLegacyBuildArtifacts(path_to_legacy_folder)
    @test !isfile(joinpath(path_to_legacy_folder, PhysiCellModelManager.baseToExecutable("project")))
    @test !isfile(joinpath(path_to_legacy_folder, "physicell_commit_hash.txt"))
    @test isfile(joinpath(path_to_legacy_folder, "main.cpp")) #! the inputs themselves are untouched
    rm(path_to_legacy_folder; force=true, recursive=true)
end

#! RunnerTests.jl has already compiled this folder
simulation = Simulation(1)
custom_code_folder = simulation.inputs[:custom_code].folder
path_to_custom_code = PhysiCellModelManager.locationPath(:custom_code, custom_code_folder)

@test PhysiCellModelManager.executableExists(custom_code_folder)
@test isfile(joinpath(path_to_custom_code, "macros.txt")) #! recorded on success, even when no macros are needed
@test !isfile(joinpath(path_to_custom_code, "physicell_commit_hash.txt"))
@test !isfile(joinpath(path_to_custom_code, PhysiCellModelManager.baseToExecutable("project")))

#! Regression: a failed compilation must not leave behind a state that reads as a finished
#! build. PCMM v0.3.3 and earlier named every executable `project` and recorded the PhysiCell
#! version separately, so a compile error that updated physicell_commit_hash.txt while leaving
#! the old executable in place convinced the next run it had a current build.
path_to_executable = PhysiCellModelManager.pathToExecutable(custom_code_folder)
path_to_saved_executable = "$(path_to_executable).saved"
path_to_makefile = joinpath(path_to_custom_code, "Makefile")
original_makefile = read(path_to_makefile, String)
path_to_stale_executable = joinpath(path_to_custom_code, PhysiCellModelManager.baseToExecutable("project"))
try
    mv(path_to_executable, path_to_saved_executable) #! stand in for "no build for the PhysiCell version in use"
    touch(path_to_stale_executable) #! a build left behind by an older PCMM, from some other PhysiCell version
    write(joinpath(path_to_custom_code, "physicell_commit_hash.txt"), "$(physicell_commit_hash)\n")
    write(path_to_makefile, "all:\n\t@exit 1\n\nclean:\n\t@exit 0\n")

    #! deliberately no force_recompile: the missing executable for this PhysiCell version is
    #! what has to trigger the rebuild. PCMM v0.3.3 and earlier would have returned true here
    #! without compiling anything, and run the stale `project`.
    @test !PhysiCellModelManager.loadCustomCode(simulation)
    @test !PhysiCellModelManager.executableExists(custom_code_folder)
finally
    write(path_to_makefile, original_makefile)
    rm(path_to_stale_executable; force=true)
    rm(joinpath(path_to_custom_code, "physicell_commit_hash.txt"); force=true)
    if isfile(path_to_saved_executable)
        mv(path_to_saved_executable, path_to_executable; force=true)
    end
end

@test PhysiCellModelManager.executableExists(custom_code_folder)
