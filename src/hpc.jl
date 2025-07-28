"""
    shellCommandExists(cmd::Union{String,Cmd})

Check if a shell command exists in the current environment.
"""
function shellCommandExists(cmd::Union{String,Cmd})
    cmd_ = Sys.iswindows() ? `where $cmd` : `which $cmd`
    p = run(pipeline(ignorestatus(cmd_); stdout=devnull, stderr=devnull))
    return p.exitcode == 0
end

"""
    isRunningOnHPC()

Return `true` if the current environment is an HPC environment, `false` otherwise.

Currently, this function checks if the `sbatch` command is available, indicating a SLURM environment.
"""
isRunningOnHPC() = shellCommandExists(`sbatch`)

"""
    useHPC([use::Bool=true])

Set the global variable `run_on_hpc` to `use`.

# Examples
```
useHPC() # Set to true so `sbatch` is used for running simulations
useHPC(true) # set to true so `sbatch` is used for running simulations
useHPC(false) # Set to false so simulations are run locally
```
"""
function useHPC(use::Bool=true)
    pcmm_globals.run_on_hpc = use
end

"""
    defaultJobOptions()

Return a dictionary with default options for a job script for use with SLURM. See [`setJobOptions`](@ref) for setting these options and others.

Current defaults are:
- `job-name`: `simulation_id -> \"S\$(simulation_id)\"` (use the simulation ID for the job name)
- `mem`: `"1G"` (1 GB of memory)
"""
function defaultJobOptions()
    return Dict(
        "job-name" => simulation_id -> "S$(simulation_id)",
        "mem" => "1G"
    )
end

"""
    setJobOptions(options::Dict)

Set the default job options for use with SLURM.

For any key-value pair in `options`, the corresponding key in the global `sbatch_options` dictionary is set to the value.
A flag is then added to the sbatch command for each key-value pair in `options`: `--key=value`.
When running simulations, any values in this dictionary that are `Function`'s will be assumed to be functions of the simulation id.
"""
function setJobOptions(options::Dict)
    for (key, value) in options
        pcmm_globals.sbatch_options[key] = value
    end
end