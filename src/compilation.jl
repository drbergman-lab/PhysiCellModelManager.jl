#! This file will likely end up being part of PhysiCellModelManager.jl

using LightXML

"""
    loadCustomCode(S::AbstractSampling[; force_recompile::Bool=false])

Load and compile custom code for a simulation, monad, or sampling.

The executable is named for the PhysiCell version it is built against (see
`executableName`), so its presence in the `custom_codes` folder is itself the record that a
build for that version finished. Nothing else is written before `make` succeeds, which is
what keeps a failed compilation from looking like a finished one on the next run.

The PhysiCell version is re-resolved first (see `refreshPhysiCellVersion`), so a PhysiCell
that changed mid-session is compiled for and recorded as what it now is.

Recompilation is necessary when the macros required by `S` differ from those recorded by the
last successful compilation, when no executable exists for the PhysiCell version in use, or
when that version cannot be pinned down at all (see `unreproduciblePhysiCellVersion`).
If compilation is required, copy the PhysiCell directory to a temporary directory to avoid conflicts.
Then, compile the project, recording the output and error in the `custom_codes` folder used.
On success, move the compiled executable into the `custom_codes` folder, record the macros
used, and delete the temporary PhysiCell folder.
"""
function loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)
    refreshPhysiCellVersion() #! PhysiCell may have been pulled, checked out, or edited since initialization; every decision below must be made against what is on disk now
    cflags, macros, recompile, clean = compilerFlags(S)
    recompile |= unreproduciblePhysiCellVersion() #! a dirty or downloaded PhysiCell can change without its recorded version changing, so the executable name is not a trustworthy cache key

    recompile |= force_recompile #! if force_recompile is true, then recompile no matter what

    if !recompile
        return true
    end

    rand_suffix = randstring(10) #! just to ensure that no two nodes try to compile at the same place at the same time
    temp_physicell_dir = joinpath(trialFolder(S), "temp_physicell_$(rand_suffix)")
    #! copy the entire PhysiCell directory to a temporary directory to avoid conflicts with concurrent compilation
    cp(physicellDir(), temp_physicell_dir; force=true)

    temp_custom_modules_dir = joinpath(temp_physicell_dir, "custom_modules")
    if isdir(temp_custom_modules_dir)
        rm(temp_custom_modules_dir; force=true, recursive=true)
    end
    path_to_input_custom_codes = locationPath(:custom_code, S)
    cp(joinpath(path_to_input_custom_codes, "custom_modules"), temp_custom_modules_dir; force=true)

    cp(joinpath(path_to_input_custom_codes, "main.cpp"), joinpath(temp_physicell_dir, "main.cpp"), force=true)
    cp(joinpath(path_to_input_custom_codes, "Makefile"), joinpath(temp_physicell_dir, "Makefile"), force=true)

    if clean
        cd(()->quietRun(`make clean`), temp_physicell_dir)
    end

    executable_name = executableName()
    cmd = Cmd(`make -j 8 CC=$(simulator().compiler) PROGRAM_NAME=$(executable_name) CFLAGS=$(cflags)`; env=ENV, dir=temp_physicell_dir) #! compile the custom code in the PhysiCell directory and return to the original directory

    println("Compiling custom code for $(S.inputs[:custom_code].folder). See $(joinpath(path_to_input_custom_codes, "compilation.log")) for more information.")

    try
        run(pipeline(cmd; stdout=joinpath(path_to_input_custom_codes, "compilation.log"), stderr=joinpath(path_to_input_custom_codes, "compilation.err")))
    catch e
        println("""
        Compilation failed.
        Error: $e
        Check $(joinpath(path_to_input_custom_codes, "compilation.err")) for more information.
        Here is the compilation.log:
        $(read(joinpath(path_to_input_custom_codes, "compilation.log"), String))
        Here is the compilation.err:
        $(read(joinpath(path_to_input_custom_codes, "compilation.err"), String))
        """
        )
        rm(temp_physicell_dir; force=true, recursive=true)
        return false
    end

    #! check if the error file is empty, if it is, delete it
    if filesize(joinpath(path_to_input_custom_codes, "compilation.err")) == 0
        rm(joinpath(path_to_input_custom_codes, "compilation.err"); force=true)
    else
        println("Compilation exited without error, but check $(joinpath(path_to_input_custom_codes, "compilation.err")) for warnings.")
    end

    path_to_compiled_executable = joinpath(temp_physicell_dir, executable_name)
    if !isfile(path_to_compiled_executable)
        println("""
        Compilation exited without error, but produced no executable at $(path_to_compiled_executable).
        Check $(joinpath(path_to_input_custom_codes, "compilation.log")) for more information.
        """
        )
        rm(temp_physicell_dir; force=true, recursive=true)
        return false
    end

    mv(path_to_compiled_executable, joinpath(path_to_input_custom_codes, executable_name), force=true)
    writeMacrosFile(S, macros) #! only now that an executable exists is it true that this is what was compiled
    removeLegacyBuildArtifacts(path_to_input_custom_codes)

    rm(temp_physicell_dir; force=true, recursive=true)
    return true
end

"""
    compilerFlags(S::AbstractSampling)

Generate the compiler flags for the given sampling object `S`.

Generate the necessary compiler flags based on the system and the macros required by the sampling object `S`.
If the required macros differ from those recorded by the last successful compilation (as stored in macros.txt), then recompile and clean.
If no executable exists for the PhysiCell version in use, then recompile.

# Returns
- `cflags::String`: The compiler flags as a string.
- `macros::Vector{String}`: The macros the compilation must define, to be recorded only once it succeeds.
- `recompile::Bool`: A boolean indicating whether recompilation is needed.
- `clean::Bool`: A boolean indicating whether cleaning is needed.
"""
function compilerFlags(S::AbstractSampling)
    recompile = false #! only recompile if need is found
    clean = false #! only clean if need is found
    cflags = "-march=$(simulator().march_flag) -O3 -fomit-frame-pointer -fopenmp -m64 -std=c++11"
    if Sys.isapple()
        if strip(read(`uname -s`, String)) == "Darwin"
            cc_path = strip(read(`which $(simulator().compiler)`, String))
            var = strip(read(`file $cc_path`, String))
            add_mfpmath = split(var)[end] != "arm64"
        end
    else
        add_mfpmath = true
    end
    if add_mfpmath
        cflags *= " -mfpmath=both"
    end

    macros = neededMacros(S)

    if macros != readMacrosFile(S)
        #! the macros are part of every translation unit, so a build that used different ones must be discarded entirely
        recompile = true
        clean = true
    end

    for macro_flag in macros
        cflags *= " -D $(macro_flag)"
    end

    if "ADDON_ROADRUNNER" in macros
        librr_dir = joinpath(physicellDir(), "addons", "libRoadrunner", "roadrunner")
        cflags *= " -I $(joinpath(librr_dir, "include", "rr", "C"))"
        cflags *= " -L $(joinpath(librr_dir, "lib"))"
        cflags *= " -l roadrunner_c_api"

        prepareLibRoadRunner()
    end

    recompile = recompile || !executableExists(S.inputs[:custom_code].folder) #! last chance to recompile: do so if no executable exists for the PhysiCell version in use

    return cflags, macros, recompile, clean
end

"""
    unreproduciblePhysiCellVersion()

Whether the PhysiCell version in use cannot be pinned down by the version PCMM records for it.

`true` when the PhysiCell repository has uncommitted changes (`-dirty`) or when PhysiCell was
downloaded rather than cloned (`-download`). In both cases the source can change without the
recorded version changing, so the name of an existing executable proves nothing and the
custom code is recompiled on every run.
"""
function unreproduciblePhysiCellVersion()
    physicell_commit_hash = physiCellCommitHash()
    if endswith(physicell_commit_hash, "-dirty")
        println("PhysiCell repo is dirty. Recompiling to be safe...")
        return true
    end
    if endswith(physicell_commit_hash, "-download")
        println("PhysiCell repo is downloaded. Recompiling to be safe...")
        return true
    end
    return false
end

"""
    executableName([physicell_commit_hash::AbstractString])

Name of the compiled PhysiCell executable for a given PhysiCell version, defaulting to the version in use.

The version is part of the file name so that the file's existence is proof that a build for
that version completed; there is no separate bookkeeping file to fall out of step with it.
Windows names carry a `.exe` extension.

# Examples
```julia-repl
julia> PhysiCellModelManager.executableName("4a9ba0c1e0b4c1a8d9f70e0f6d4e6b8c1a2b3c4d")
"project_4a9ba0c1e0b4c1a8d9f70e0f6d4e6b8c1a2b3c4d"
```
"""
executableName(physicell_commit_hash::AbstractString=physiCellCommitHash()) = baseToExecutable("project_$(sanitizedForFilename(physicell_commit_hash))")

"""
    sanitizedForFilename(s::AbstractString)

Replace each character of `s` outside `[A-Za-z0-9._-]` with `_` so that `s` is safe to use in a file name.

A PhysiCell version is either a git commit hash or the first line of the `VERSION.txt`
shipped by whichever PhysiCell the user downloaded, so it is not guaranteed to be tame.
"""
sanitizedForFilename(s::AbstractString) = replace(s, r"[^A-Za-z0-9._-]" => "_")

"""
    pathToExecutable(custom_code_folder::String)
    pathToExecutable(S::AbstractSampling)

Path to the executable in a custom code folder for the PhysiCell version in use.
"""
pathToExecutable(custom_code_folder::String) = joinpath(locationPath(:custom_code, custom_code_folder), executableName())
pathToExecutable(S::AbstractSampling) = joinpath(locationPath(:custom_code, S), executableName())

"""
    executableExists(custom_code_folder::String)

Check if the custom code folder holds an executable built against the PhysiCell version in use.
"""
executableExists(custom_code_folder::String) = isfile(pathToExecutable(custom_code_folder))

"""
    isCompilationArtifact(filename::AbstractString)

Whether `filename`, a bare file name in a custom code folder, is a file PCMM writes while compiling and may therefore delete.

Covers the executables (`project_<physicell-version>`, plus `.exe` on Windows), the
compilation logs, `macros.txt`, and what PCMM v0.3.3 and earlier left behind: an executable
named `project` and a `physicell_commit_hash.txt`. The legacy names are matched on either
platform so that a data folder built elsewhere is still cleaned.

Matched on the `project_` prefix rather than `project`, so an unrelated `projectile.cpp` is
left alone. A file the user happened to name `project_notes.md` is not distinguishable from
an executable and would be deleted; nothing but generated files belongs here.
"""
isCompilationArtifact(filename::AbstractString) = startswith(filename, "project_") || filename in ("project", "project.exe", "compilation.log", "compilation.err", "macros.txt", "physicell_commit_hash.txt")

"""
    removeLegacyBuildArtifacts(path_to_custom_codes_folder::String)

Delete the build bookkeeping of PCMM v0.3.3 and earlier from a custom code folder.

Those versions named every executable `project` and tracked the PhysiCell version in
`physicell_commit_hash.txt`. Neither is read anymore, and leaving the pair in place is how a
project keeps looking like it has a build it does not have, so both go once a build under the
current naming has succeeded.
"""
function removeLegacyBuildArtifacts(path_to_custom_codes_folder::String)
    for filename in ("project", "project.exe", "physicell_commit_hash.txt") #! both executable names, so a data folder built on another platform is cleaned too
        path_to_file = joinpath(path_to_custom_codes_folder, filename)
        if isfile(path_to_file)
            rm_hpc_safe(path_to_file; force=true)
        end
    end
    return nothing
end

"""
    neededMacros(S::AbstractSampling)

The macros the custom code for the sampling object `S` must be compiled with.

Starts from the macros recorded by the last successful compilation (macros.txt) and appends
any that `S` newly requires, preserving the recorded order so the result can be compared
against the file to decide whether a recompilation is needed. Every check runs, so a
sampling needing more than one new macro gets all of them in one compilation.
"""
function neededMacros(S::AbstractSampling)
    macros = readMacrosFile(S)
    if !("ADDON_PHYSIECM" in macros) && isPhysiECMNeeded(S)
        push!(macros, "ADDON_PHYSIECM")
    end
    if !("ADDON_ROADRUNNER" in macros) && isRoadRunnerNeeded(S)
        push!(macros, "ADDON_ROADRUNNER")
    end

    #! check others...

    return macros
end

"""
    isPhysiECMNeeded(S::AbstractSampling)

Check if the PhysiECM macro is needed for the sampling object `S`.

The macro is needed if either 1) the `inputs` includes `ic_ecm` or 2) the configuration file has `ecm_setup` enabled.
"""
function isPhysiECMNeeded(S::AbstractSampling)
    if S.inputs[:ic_ecm].id != -1
        #! if this sampling is providing an ic file for ecm, then we need the macro
        return true
    end
    #! check if ecm_setup element has enabled="true" in config files
    prepareVariedInputFolder(:config, S)
    return isPhysiECMInConfig(S)
end

"""
    isPhysiECMInConfig(S::AbstractSampling)

Check if any of the simulations in `S` have a configuration file with `ecm_setup` enabled.
"""
function isPhysiECMInConfig(M::AbstractMonad)
    path_to_xml = joinpath(locationPath(:config, M), locationVariationsFolder(:config), "config_variation_$(M.variation_id[:config]).xml")
    xml_doc = parse_file(path_to_xml)
    xml_path = ["microenvironment_setup", "ecm_setup"]
    ecm_setup_element = retrieveElement(xml_doc, xml_path; required=false)
    physi_ecm_in_config = !isnothing(ecm_setup_element) && attribute(ecm_setup_element, "enabled") == "true" #! note: attribute returns nothing if the attribute does not exist
    free(xml_doc)
    return physi_ecm_in_config
end

function isPhysiECMInConfig(sampling::Sampling)
    #! otherwise, no previous sampling saying to use the macro, no ic file for ecm, and the base config file does not have ecm enabled,
    #! now just check that the variation is not enabling the ecm
    for monad in Monad.(constituentIDs(sampling))
        if isPhysiECMInConfig(monad)
            return true
        end
    end
    return false
end

"""
    isRoadRunnerNeeded(S::AbstractSampling)

Check if the RoadRunner macro is needed for the sampling object `S`.

The macro is needed if either 1) the `inputs` defines an `intracellular` file with `roadrunner` intracellulars or 2) the configuration file has `roadrunner` intracellulars defined.
"""
function isRoadRunnerNeeded(S::AbstractSampling)
    prepareVariedInputFolder(:config, S)
    return isRoadRunnerInInputs(S) || isRoadRunnerInConfig(S)
end

"""
    isRoadRunnerInInputs(S::AbstractSampling)

Check if the `inputs` for the sampling object `S` defines an `intracellular` file with `roadrunner` intracellulars.
"""
function isRoadRunnerInInputs(S::AbstractSampling)
    if S.inputs[:intracellular].id == -1
        return false
    end
    path_to_xml = joinpath(locationPath(:intracellular, S), S.inputs[:intracellular].basename)
    xml_doc = parse_file(path_to_xml)
    is_nothing = retrieveElement(xml_doc, ["intracellulars"; "intracellular:type:roadrunner"]) |> isnothing
    free(xml_doc)
    return !is_nothing
end

"""
    isRoadRunnerInConfig(S::AbstractSampling)

Check if any of the simulations in `S` have a configuration file with `roadrunner` intracellulars defined.
"""
function isRoadRunnerInConfig(S::AbstractSampling)
    path_to_xml = joinpath(locationPath(:config, S), "PhysiCell_settings.xml")
    xml_doc = parse_file(path_to_xml)
    cell_definitions_element = retrieveElement(xml_doc, ["cell_definitions"])
    ret_val = false
    for child in child_elements(cell_definitions_element)
        phenotype_element = find_element(child, "phenotype")
        intracellular_element = find_element(phenotype_element, "intracellular")
        if isnothing(intracellular_element)
            continue
        end
        if attribute(intracellular_element, "type") == "roadrunner"
            ret_val = true
            break
        end
    end
    free(xml_doc)
    return ret_val
end

"""
    prepareLibRoadRunner()

Prepare the libRoadRunner library for use with PhysiCell.
"""
function prepareLibRoadRunner()
    #! this is how PhysiCell handles downloading libRoadrunner
    println("preparing libRoadrunner library for use with PhysiCell...")
    librr_base_dir = joinpath(physicellDir(), "addons", "libRoadrunner")
    librr_dir = joinpath(librr_base_dir, "roadrunner")
    librr_file = joinpath(librr_dir, "include", "rr", "C", "rrc_api.h")
    if !isfile(librr_file)
        python = Sys.iswindows() ? "python" : "python3"
        cmd = `$(python) $(joinpath(".", "beta", "setup_libroadrunner.py"))`
        cd(() -> quietRun(cmd), physicellDir())
        @assert isfile(librr_file) "libRoadrunner was not downloaded properly."

        #! remove the downloaded binary (I would think the script would handle this, but it does not)
        files = readdir(librr_base_dir; join=true, sort=false)
        for path_to_file in files
            if isfile(path_to_file) &&
                (
                    endswith(path_to_file, "roadrunner_macos_arm64.tar.gz") ||
                    endswith(path_to_file, "roadrunner-osx-10.9-cp36m.tar.gz") ||
                    endswith(path_to_file, "roadrunner-win64-vs14-cp35m.zip") ||
                    endswith(path_to_file, "cpplibroadrunner-1.3.0-linux_x86_64.tar.gz") ||
                    endswith(path_to_file, "roadrunner_manylinux.zip") ||
                    endswith(path_to_file, "roadrunner_macos_arm64.zip")
                )
                #! remove the downloaded binary
                rm(path_to_file; force=true)
            end
        end
    end

    if Sys.iswindows()
        return
    end

    env_var = Sys.isapple() ? "DYLD_LIBRARY_PATH" : "LD_LIBRARY_PATH"
    env_file = (haskey(ENV, "SHELL") && contains(ENV["SHELL"], "zsh")) ? ".zshenv" : ".bashrc"
    path_to_env_file = "~/$(env_file)"
    librr_lib_path = joinpath(librr_dir, "lib")

    if !haskey(ENV, env_var) || !libRoadRunnerOnPath(ENV[env_var], librr_lib_path)
        println("""
        Warning: Shell environment variable $(env_var) either not found or does not include the path to an installation of libRoadrunner.
        For now, we will add this path to your ENV variable in this Julia session.
        Run this command in your terminal to add it to your $(env_file) as a relative path and this should be resolved permanently:

            echo "export $env_var=$env_var:./addons/libRoadrunner/roadrunner/lib" > $(path_to_env_file)

        """)
        ENV[env_var] = ":./addons/libRoadrunner/roadrunner/lib" #! at this point, we know this is not a Windows system
    end
end

"""
    libRoadRunnerOnPath(env_var::String, librr_lib_path::String; working_dir::String=physicellDir())

Check if the libRoadRunner library path is included in the environment variable.

The `librr_lib_path` must be an absolute path, and the function will resolve relative paths based on the `working_dir`.
Returns `true` if the path is found, otherwise `false`.
"""
function libRoadRunnerOnPath(env_var::String, librr_lib_path::String; working_dir::String=physicellDir())
    normalized_librr_lib_path = normpath(librr_lib_path)
    @assert isabspath(normalized_librr_lib_path) "The path to the libRoadRunner library must be absolute. Provided: $(normalized_librr_lib_path)"
    os_variable_separator = Sys.iswindows() ? ";" : ":"
    paths = split(env_var, os_variable_separator)
    for path in paths
        resolved_path = isabspath(path) ? path : joinpath(working_dir, path)
        if normpath(resolved_path) == normalized_librr_lib_path
            return true
        end
    end

    return false
end

"""
    readMacrosFile(S::AbstractSampling)

Read the macros recorded by the last successful compilation for the sampling object `S` into a vector of strings, one macro per entry.
"""
function readMacrosFile(S::AbstractSampling)
    path_to_macros = joinpath(locationPath(:custom_code, S), "macros.txt")
    if !isfile(path_to_macros)
        return String[]
    end
    return readlines(path_to_macros)
end

"""
    writeMacrosFile(S::AbstractSampling, macros::Vector{String})

Record `macros` as the macros the custom code for the sampling object `S` was compiled with.

Called only after a compilation succeeds. Written any earlier, a failed compilation would
leave the file claiming macros no executable was ever built with, and the next run would skip
the `make clean` that a macro change requires.
"""
function writeMacrosFile(S::AbstractSampling, macros::Vector{String})
    path_to_macros = joinpath(locationPath(:custom_code, S), "macros.txt")
    open(path_to_macros, "w") do f
        for macro_name in macros
            println(f, macro_name)
        end
    end
    return nothing
end

"""
    setMarchFlag(flag::String)

Set the march flag to `flag`. Used for compiling the PhysiCell code.
"""
function setMarchFlag(flag::String)
    simulator().march_flag = flag
end

"""
    baseToExecutable(s::String)

Convert a string to an executable name based on the operating system.
If the operating system is Windows, append ".exe" to the string.
"""
function baseToExecutable end
if Sys.iswindows()
    baseToExecutable(s::String) = "$(s).exe"
else
    baseToExecutable(s::String) = s
end
