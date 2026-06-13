# Installation

Installing PhysiCellModelManager.jl takes three steps: install Julia, add the BergmanLabRegistry, then add the package.

## 1. Install Julia

The easiest way to install Julia is from the command line.

On Linux and macOS:
```sh
curl -fsSL https://install.julialang.org | sh
```

On Windows:
```powershell
winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore
```

This also installs [JuliaUp](https://github.com/JuliaLang/juliaup), which keeps Julia up to date.
For other options, see the [Julia install page](https://julialang.org/install) and [downloads](https://julialang.org/downloads/).

## 2. Add the BergmanLabRegistry

Launch Julia by running `julia` in a shell, then enter the Pkg REPL by pressing `]` and run:
```julia-repl
pkg> registry add General
pkg> registry add https://github.com/drbergman-lab/BergmanLabRegistry
```
The first line ensures the General registry is set up; the second adds the registry that hosts PhysiCellModelManager.jl.

## 3. Install PhysiCellModelManager.jl

Still in the Pkg REPL:
```julia-repl
pkg> add PhysiCellModelManager
```

## Next steps

- Set up a dedicated environment for your work — see [Julia environments](@ref).
- Create and run your first project — see [Your first project](@ref).
