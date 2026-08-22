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

#! top-level files PCMM writes while compiling, matched exactly. The legacy `project` names
#! match on either platform, so a data folder built elsewhere is still cleaned.
for artifact in ["compilation.log", "compilation.err", "macros.txt",
    "project", "project.exe", "physicell_commit_hash.txt"]
    @test PhysiCellModelManager.isCompilationArtifact(artifact)
end
#! nothing a user keeps beside their main.cpp is matched, including names that a `project`
#! prefix would have swept up
for keeper in ["main.cpp", "Makefile", "custom_modules", "metadata.xml",
    "projectile.cpp", "projects", "project_notes.md", PhysiCellModelManager.executableName()]
    @test !PhysiCellModelManager.isCompilationArtifact(keeper)
end

#! executables live in a folder PCMM owns, so clearing them never needs a name match
@test basename(dirname(PhysiCellModelManager.pathToExecutable("some_folder"))) == PhysiCellModelManager.build_folder_name
@test PhysiCellModelManager.buildFolder("some_folder") == dirname(PhysiCellModelManager.pathToExecutable("some_folder"))

#! a build that does not finish takes the executable it was replacing with it
let path_to_scratch = mktempdir()
    path_to_build = joinpath(path_to_scratch, PhysiCellModelManager.build_folder_name)
    path_to_stale = joinpath(path_to_build, "project_stale")
    path_to_temp_physicell = joinpath(path_to_scratch, "temp_physicell_abc")
    mkpath(path_to_build)
    mkpath(path_to_temp_physicell)
    touch(path_to_stale)
    touch(joinpath(path_to_temp_physicell, "Makefile"))
    @test !PhysiCellModelManager.abandonBuild(path_to_stale, path_to_temp_physicell)
    @test !isfile(path_to_stale)
    @test !isdir(path_to_temp_physicell)
    rm(path_to_scratch; force=true, recursive=true)
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
#! the old executable in place convinced the next run it had a current build. The executable
#! being replaced here is a real, working one, so the failure has something to lose.
path_to_executable = PhysiCellModelManager.pathToExecutable(custom_code_folder)
path_to_makefile = joinpath(path_to_custom_code, "Makefile")
original_makefile = read(path_to_makefile, String)
path_to_stale_executable = joinpath(path_to_custom_code, PhysiCellModelManager.baseToExecutable("project"))
try
    @test isfile(path_to_executable)
    touch(path_to_stale_executable) #! the pre-v0.3.4 pair that used to convince the next run
    write(joinpath(path_to_custom_code, "physicell_commit_hash.txt"), "$(physicell_commit_hash)\n")
    write(path_to_makefile, "all:\n\t@exit 1\n\nclean:\n\t@exit 0\n")

    @test !PhysiCellModelManager.loadCustomCode(simulation; force_recompile=true)
    @test !isfile(path_to_executable) #! the build being replaced is gone, not left to be trusted
    @test !PhysiCellModelManager.executableExists(custom_code_folder)
finally
    write(path_to_makefile, original_makefile)
    rm(path_to_stale_executable; force=true)
    rm(joinpath(path_to_custom_code, "physicell_commit_hash.txt"); force=true)
end

#! and the next run rebuilds rather than trusting the leftovers. No force_recompile: the
#! missing executable for this PhysiCell version is what has to trigger it, and under
#! v0.3.3 the leftover `project` plus its hash file would have returned true without
#! compiling. The executable can only be back if a compilation actually ran.
@test PhysiCellModelManager.loadCustomCode(simulation)
@test PhysiCellModelManager.executableExists(custom_code_folder)

#! Guard: PhysiCell can be pulled, checked out, or edited mid-session. Until this was wired,
#! the version was resolved once at initialization and never revisited, so a changed PhysiCell
#! was reused silently -- and any recompile forced for another reason built the new source while
#! recording the old version.
version_id_before = PhysiCellModelManager.currentPhysiCellVersionID()

#! loadCustomCode must refresh before anything reads the version. With the id invalidated, a
#! missing refresh cannot resolve an executable name at all, so this fails loudly.
PhysiCellModelManager.simulator().current_version_id = -1
@test PhysiCellModelManager.loadCustomCode(simulation)
@test PhysiCellModelManager.currentPhysiCellVersionID() == version_id_before

path_to_physicell_makefile = joinpath(PhysiCellModelManager.physicellDir(), "Makefile")
original_physicell_makefile = read(path_to_physicell_makefile, String)
try
    write(path_to_physicell_makefile, original_physicell_makefile * "\n# edited mid-session\n")
    @test !PhysiCellModelManager.gitDirectoryIsClean(PhysiCellModelManager.physicellDir(); verbose=false)

    #! nothing has looked yet, so the session still believes the version it started with
    @test PhysiCellModelManager.currentPhysiCellVersionID() == version_id_before
    @test !endswith(PhysiCellModelManager.physiCellCommitHash(), "-dirty")

    PhysiCellModelManager.refreshPhysiCellVersion()
    @test PhysiCellModelManager.currentPhysiCellVersionID() != version_id_before
    @test endswith(PhysiCellModelManager.physiCellCommitHash(), "-dirty")
    @test PhysiCellModelManager.unreproduciblePhysiCellVersion()
    @test !PhysiCellModelManager.executableExists(custom_code_folder) #! no build exists for the dirty version, so a compile is unavoidable
finally
    write(path_to_physicell_makefile, original_physicell_makefile)
    PhysiCellModelManager.refreshPhysiCellVersion()
end

@test PhysiCellModelManager.currentPhysiCellVersionID() == version_id_before
@test !PhysiCellModelManager.unreproduciblePhysiCellVersion()
@test PhysiCellModelManager.executableExists(custom_code_folder)
