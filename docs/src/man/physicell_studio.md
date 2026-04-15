# Using PhysiCell Studio
See [PhysiCell-Studio](https://github.com/PhysiCell-Tools/PhysiCell-Studio).
Using PhysiCell Studio within PhysiCellModelManager.jl is designed for visualizing output in the `Plot` tab and observing model parameters in the remaining tabs.

**Do not use the `Run` tab in PhysiCell Studio as this may delete simulation data.**

See [below](#editing-in-physicell-studio) for how to edit the configuration and rules files in studio.

## Setting paths
### Environment variables
You must first inform PhysiCellModelManager.jl where your desired `python` executable is and the PhysiCell Studio folder.
The recommended way to do this on macOS/Linux is to add the following two lines to your shell environment file (e.g. `~/.bashrc` or `~/.zshenv`):
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
If you prefer not to set these environment variables, you can pass the paths as keyword arguments to the `runStudio` function.
It will remember these settings during the session, so you only need to pass them once.
See below for the function signature.

## Launching PhysiCell Studio
First, launch julia in a new shell session and make sure the project is initialized by running:
```julia
using PhysiCellModelManager
```
> Note: If you have already loaded the package in this session, run [`initializeModelManager`](@ref) if you need to initialize the project.

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
When you run the `runStudio` function, PhysiCell Studio will open with the simulation you specified using temporary files for the configuration and rules.
Any edits to these in studio will be lost when the studio is closed.
Remember: this is the output of a simulation that __already__ ran.
Use the `File > Save as` dropdown to save the configuration file.
Use the `Rules` tab to save the rules file.
Note: the recent changes in PhysiCell 1.14.1 copying over the initial conditions files are not yet supported by this.
See [Known limitations](#known-limitations) for more information.

