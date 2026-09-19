# [Using PhysiCell Studio](@id physicell_studio_man)

Open a finished simulation in [PhysiCell Studio](https://github.com/PhysiCell-Tools/PhysiCell-Studio)
to view its output (the `Plot` tab) and inspect its parameters (the other tabs).

!!! warning
    Do not use the `Run` tab in PhysiCell Studio — it may delete simulation data.

## Setting paths

### Environment variables

!!! tiergloss
    Tell PhysiCellModelManager.jl where your `python` executable and your PhysiCell Studio folder
    are. On macOS/Linux, add both to your shell environment file (e.g. `~/.bashrc` or `~/.zshenv`);
    on Windows, use the GUI for setting environment variables. `PCMM_PYTHON_PATH` can be a bare
    `python3` if it is on your `PATH`.

```sh
export PCMM_PYTHON_PATH=/usr/bin/python3
export PCMM_STUDIO_PATH=/home/user/PhysiCell-Studio

source ~/.bashrc   # apply the changes, or just open a new terminal window
```

!!! tierwhy
    If Studio will not launch, check these three things: `PCMM_PYTHON_PATH` must point to a valid
    python executable; `PCMM_STUDIO_PATH` must point to the PhysiCell Studio folder, **not to the
    `studio.py` file**; and `~` is not expanded inside quotes, so
    `export PCMM_STUDIO_PATH="~/PhysiCell-Studio"` will not work.

### Using keyword arguments

!!! tiergloss
    Alternatively, pass the two paths to [`runStudio`](@ref) as keyword arguments. It remembers them
    for the session, so you pass them only once.

## Launching PhysiCell Studio

!!! tiergloss
    Launch Julia in a new shell session and load the package, which initializes the project — call
    [`initializeModelManager`](@ref PhysiCellModelManager.initializeModelManager) instead if the
    package is already loaded. Then call [`runStudio`](@ref) with a simulation ID. Studio can be
    opened as soon as the simulation has begun, since it needs only the PhysiCell-generated `output`
    folder to exist and be populated.

```julia
using PhysiCellModelManager

runStudio(sim_id)
runStudio(sim_id; python_path=path_to_python, studio_path=path_to_studio) #! without the env vars
```

## Editing in PhysiCell Studio

!!! tiergloss
    [`runStudio`](@ref) opens Studio on temporary configuration and rules files, so edits are lost
    when Studio closes — remember, this is the output of a simulation that __already__ ran. Save the
    configuration with `File > Save as` and the rules from the `Rules` tab. The PhysiCell 1.14.1
    behavior of copying over initial-conditions files is not yet supported; see
    [Known limitations](@ref known_limitations_man).
