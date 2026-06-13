# Using PhysiCell Studio
See [PhysiCell-Studio](https://github.com/PhysiCell-Tools/PhysiCell-Studio). Within PhysiCellModelManager.jl, PhysiCell Studio is for visualizing output (the `Plot` tab) and inspecting model parameters (the other tabs).

**Do not use the `Run` tab in PhysiCell Studio — it may delete simulation data.**

See [Editing in PhysiCell Studio](#editing-in-physicell-studio) for editing the configuration and rules files.

## Setting paths
### Environment variables
First tell PhysiCellModelManager.jl where your `python` executable and PhysiCell Studio folder are. On macOS/Linux, add two lines to your shell environment file (e.g. `~/.bashrc` or `~/.zshenv`):
```
export PCMM_PYTHON_PATH=/usr/bin/python3
export PCMM_STUDIO_PATH=/home/user/PhysiCell-Studio
```
If your python executable is on your PATH, you can set `PCMM_PYTHON_PATH=python3`, for example.

After making these changes, make sure to source the file to apply the changes:
```sh
source ~/.bashrc
```
Or open a new terminal window.

On Windows, the simplest way to set these is to use the GUI for setting environment variables.

Troubleshooting: If you are having trouble launching PhysiCell Studio...
- `PCMM_PYTHON_PATH` must point to a valid python executable
- `PCMM_STUDIO_PATH` must point to the PhysiCell Studio folder, **not the `studio.py` file**
- the `~` character is not expanded when in quotes, so `export PCMM_STUDIO_PATH="~/PhysiCell-Studio"` will not work

### Using keyword arguments
Alternatively, pass the paths as keyword arguments to `runStudio` (see below). It remembers them for the session, so you only pass them once.

## Launching PhysiCell Studio
First, launch julia in a new shell session and initialize the project:
```julia
using PhysiCellModelManager
```
!!! note
    If you have already loaded the package in this session, run [`initializeModelManager`](@ref PhysiCellModelManager.initializeModelManager) if you need to initialize the project.

As soon as the simulation has begun (so that its PhysiCell-generated `output` folder is created and populated), you can launch PhysiCell Studio.
If you set the environment variables, you can run the following command for a simulation with id `sim_id::Integer`:
```julia-repl
julia> runStudio(sim_id)
```
If you did not set the environment variables, you can run the following command:
```julia-repl
julia> runStudio(sim_id; python_path=path_to_python, studio_path=path_to_studio)
```

## Editing in PhysiCell Studio
`runStudio` opens Studio on the specified simulation using temporary configuration and rules files, so edits are lost when Studio closes — remember, this is the output of a simulation that __already__ ran. Save the configuration with `File > Save as` and the rules from the `Rules` tab. The PhysiCell 1.14.1 behavior of copying over initial-conditions files is not yet supported; see [Known limitations](@ref).

