#! This file will likely end up being part of PhysiCellModelManager.jl

using LightXML

"""
    loadCustomCode(S::AbstractSampling[; force_recompile::Bool=false])

Load and compile custom code for a simulation, monad, or sampling.

Determines if recompilation is necessary based on the previously used macros.
If compilation is required, copy the PhysiCell directory to a temporary directory to avoid conflicts.
Then, compile the project, recording the output and error in the `custom_codes` folder used.
Move the compiled executable into the `custom_codes` folder and the temporary PhysiCell folder deleted.
"""
function loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)
    cflags, recompile, clean = compilerFlags(S)
    recompile = writePhysiCellCommitHash(S) || recompile #! no matter what, write the PhysiCell version; if it is different, make sure to set recompile to true

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
        cd(()->run(pipeline(`make clean`; stdout=devnull)), temp_physicell_dir)
    end

    executable_name = baseToExecutable("project_ccid_$(S.inputs[:custom_code].id)")
    cmd = Cmd(`make -j 8 CC=$(pcmm_globals.physicell_compiler) PROGRAM_NAME=$(executable_name) CFLAGS=$(cflags)`; env=ENV, dir=temp_physicell_dir) #! compile the custom code in the PhysiCell directory and return to the original directory

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

    mv(joinpath(temp_physicell_dir, executable_name), joinpath(path_to_input_custom_codes, baseToExecutable("project")), force=true)

    rm(temp_physicell_dir; force=true, recursive=true)
    return true
end

"""
    compilerFlags(S::AbstractSampling)

Generate the compiler flags for the given sampling object `S`.

Generate the necessary compiler flags based on the system and the macros defined in the sampling object `S`.
If the required macros differ from a previous compilation (as stored in macros.txt), then recompile.

# Returns
- `cflags::String`: The compiler flags as a string.
- `recompile::Bool`: A boolean indicating whether recompilation is needed.
- `clean::Bool`: A boolean indicating whether cleaning is needed.
"""
function compilerFlags(S::AbstractSampling)
    recompile = false #! only recompile if need is found
    clean = false #! only clean if need is found
    cflags = "-march=$(pcmm_globals.march_flag) -O3 -fomit-frame-pointer -fopenmp -m64 -std=c++11"
    if Sys.isapple()
        if strip(read(`uname -s`, String)) == "Darwin"
            cc_path = strip(read(`which $(pcmm_globals.physicell_compiler)`, String))
            var = strip(read(`file $cc_path`, String))
            add_mfpmath = split(var)[end] != "arm64"
        end
    else
        add_mfpmath = true
    end
    if add_mfpmath
        cflags *= " -mfpmath=both"
    end

    macros_updated = addMacrosIfNeeded(S)
    updated_macros = readMacrosFile(S) #! this will get all macros already in the macros file

    if macros_updated
        recompile = true
        clean = true
    end

    for macro_flag in updated_macros
        cflags *= " -D $(macro_flag)"
    end

    if "ADDON_ROADRUNNER" in updated_macros
        librr_dir = joinpath(physicellDir(), "addons", "libRoadrunner", "roadrunner")
        cflags *= " -I $(joinpath(librr_dir, "include", "rr", "C"))"
        cflags *= " -L $(joinpath(librr_dir, "lib"))"
        cflags *= " -l roadrunner_c_api"

        prepareLibRoadRunner()
    end

    recompile = recompile || !executableExists(S.inputs[:custom_code].folder) #! last chance to recompile: do so if the executable does not exist

    return cflags, recompile, clean
end

"""
    writePhysiCellCommitHash(S::AbstractSampling)

Write the commit hash of the PhysiCell repository to a file associated with the custom code folder of the sampling object `S`.

If the commit hash has changed since the last write, if the repository is in a dirty state, or if PhysiCell is downloaded (not cloned), recompile the custom code.
"""
function writePhysiCellCommitHash(S::AbstractSampling)
    path_to_commit_hash = joinpath(locationPath(:custom_code, S), "physicell_commit_hash.txt")
    physicell_commit_hash = physiCellCommitHash()
    current_commit_hash = ""
    if isfile(path_to_commit_hash)
        current_commit_hash = readchomp(path_to_commit_hash)
    end
    recompile = true
    if current_commit_hash != physicell_commit_hash
        open(path_to_commit_hash, "w") do f
            println(f, physicell_commit_hash)
        end
    elseif endswith(physicell_commit_hash, "-dirty")
        println("PhysiCell repo is dirty. Recompiling to be safe...")
    elseif endswith(physicell_commit_hash, "-download")
        println("PhysiCell repo is downloaded. Recompiling to be safe...")
    else
        recompile = false
    end
    return recompile
end

"""
    executableExists(custom_code_folder::String)

Check if the executable for the custom code folder exists.
"""
executableExists(custom_code_folder::String) = isfile(joinpath(locationPath(:custom_code, custom_code_folder), baseToExecutable("project")))

"""
    addMacrosIfNeeded(S::AbstractSampling)

Check if the macros needed for the sampling object `S` are already present in the macros file.
"""
function addMacrosIfNeeded(S::AbstractSampling)
    #! else get the macros neeeded
    macros_updated = false

    #! julia's |= operator seems to evaluate the RHS even if the LHS is already true, but I don't trust that will always be the case
    macros_updated = macros_updated || addPhysiECMIfNeeded(S)
    macros_updated = macros_updated || addRoadRunnerIfNeeded(S)

    #! check others...

    return macros_updated
end

"""
    addMacro(S::AbstractSampling, macro_name::String)

Add a macro to the macros file for the sampling object `S`.
"""
function addMacro(S::AbstractSampling, macro_name::String)
    path_to_macros = joinpath(locationPath(:custom_code, S), "macros.txt")
    open(path_to_macros, "a") do f
        println(f, macro_name)
    end
end

"""
    addPhysiECMIfNeeded(S::AbstractSampling)

Check if the PhysiECM macro needs to be added for the sampling object `S`.

The macro will need to be added if it is not present AND either 1) the `inputs` includes `ic_ecm` or 2) the configuration file has `ecm_setup` enabled.
"""
function addPhysiECMIfNeeded(S::AbstractSampling)
    if "ADDON_PHYSIECM" in readMacrosFile(S)
        #! if the custom codes folder for the sampling already has the macro, then we don't need to do anything
        return false
    end
    if S.inputs[:ic_ecm].id != -1
        #! if this sampling is providing an ic file for ecm, then we need to add the macro
        addMacro(S, "ADDON_PHYSIECM")
        return true
    end
    #! check if ecm_setup element has enabled="true" in config files
    prepareVariedInputFolder(:config, S)
    if isPhysiECMInConfig(S)
        #! if the base config file says that the ecm is enabled, then we need to add the macro
        addMacro(M, "ADDON_PHYSIECM")
        return true
    end
    return false
end

"""
    isPhysiECMInConfig(S::AbstractSampling)

Check if any of the simulations in `S` have a configuration file with `ecm_setup` enabled.
"""
function isPhysiECMInConfig(M::AbstractMonad)
    path_to_xml = joinpath(locationPath(:config, M), "config_variations", "config_variation_$(M.variation_id[:config]).xml")
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
    for monad in Monad.(readConstituentIDs(sampling))
        if isPhysiECMInConfig(monad)
            return true
        end
    end
    return false
end

"""
    addRoadRunnerIfNeeded(S::AbstractSampling)

Check if the RoadRunner macro needs to be added for the sampling object `S`.

The macro will need to be added if it is not present AND either 1) the `inputs` defines an `intracellular` file with `roadrunner` intracellulars or 2) the configuration file has `roadrunner` intracellulars defined.
"""
function addRoadRunnerIfNeeded(S::AbstractSampling)
    if "ADDON_ROADRUNNER" in readMacrosFile(S)
        #! if the custom codes folder for the sampling already has the macro, then we don't need to do anything
        return false
    end

    macros_updated = false
    prepareVariedInputFolder(:config, S)
    macros_updated = isRoadRunnerInInputs(S) || isRoadRunnerInConfig(S)
    if macros_updated
        addMacro(S, "ADDON_ROADRUNNER")
    end
    return macros_updated
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
        cd(() -> run(pipeline(`$(python) $(joinpath(".", "beta", "setup_libroadrunner.py"))`;
                stdout=devnull,
                stderr=devnull)),
            physicellDir())
        @assert isfile(librr_file) "libRoadrunner was not downloaded properly."

        #! remove the downloaded binary (I would think the script would handle this, but it does not)
        files = readdir(librr_base_dir; join=true, sort=false)
        for path_to_file in files
            if isfile(path_to_file) &&
                (
                    endswith(path_to_file, "roadrunner_macos_arm64.tar.gz") ||
                    endswith(path_to_file, "roadrunner-osx-10.9-cp36m.tar.gz") ||
                    endswith(path_to_file, "roadrunner-win64-vs14-cp35m.zip") ||
                    endswith(path_to_file, "cpplibroadrunner-1.3.0-linux_x86_64.tar.gz")
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
    path_to_add = joinpath(librr_dir, "lib")

    if !haskey(ENV, env_var) || !contains(ENV[env_var], path_to_add)
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
    readMacrosFile(S::AbstractSampling)

Read the macros file for the sampling object `S` into a vector of strings, one macro per entry.
"""
function readMacrosFile(S::AbstractSampling)
    path_to_macros = joinpath(locationPath(:custom_code, S), "macros.txt")
    if !isfile(path_to_macros)
        return []
    end
    return readlines(path_to_macros)
end