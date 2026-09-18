# [Data directory structure](@id data_directory_man)

What each folder under a project's `data/` holds, so you can add or edit inputs by hand.

!!! tiergloss
    [`createProject`](@ref) builds this structure for you under `project-dir`. Each terminal
    subdirectory under `data/inputs/` holds input folders whose names you choose; the examples below
    use `"baseline"`, but any name works, and that name is what you pass to
    [`InputFolders`](@ref).

```
project-dir/
├── data/
│   └── inputs/
│       ├── configs/
│       ├── custom_codes/
│       ├── ics/
│       │   ├── cells/
│       │   ├── dcs/
│       │   ├── ecms/
│       │   └── substrates/
│       ├── intracellulars/
│       ├── rulesets_collections/
...
```

## Configs

!!! tiergloss
    Place your base configuration file at
    `data/inputs/configs/baseline/PhysiCell_settings.xml`.

## Custom codes

!!! tiergloss
    Place `main.cpp`, `Makefile`, and `custom_modules/` in `data/inputs/custom_codes/baseline/`,
    exactly as they are used in a PhysiCell project.

!!! tierdev
    PCMM compiles into this folder as well, adding the compilation logs, `macros.txt`, and a
    `pcmm_build/` subfolder holding one executable per PhysiCell version it has built for
    (`pcmm_build/project_<version>`). These are generated files, ignored by the `.gitignore`
    [`createProject`](@ref) writes; delete `pcmm_build/` to force a fresh build.

## Rulesets collections

!!! tiergloss
    Place your base ruleset collection at
    `data/inputs/rulesets_collections/baseline/base_rulesets.csv`, or skip this if your project has
    no rules. You may instead place an XML file here, created from a CSV with
    [PhysiCellXMLRules.jl](https://github.com/drbergman-lab/PhysiCellXMLRules.jl).

!!! tierwhy
    **Variations must target the XML version.** After
    [`initializeModelManager`](@ref PhysiCellModelManager.initializeModelManager), any folder
    holding a `base_rulesets.csv` is populated with a `base_rulesets.xml`, and that is the file
    whose XML paths a variation addresses.

## Intracellulars

!!! tiergloss
    Place a single `intracellular.xml` at `data/inputs/intracellulars/baseline/`, with root children
    `cell_definitions` and `intracellulars`. Only libRoadRunner (ODEs) is currently supported; see
    `sample_projects_intracellular/combined/template-combined` for an example, and
    [Intracellular inputs](@ref intracellular_inputs_man) for how to assemble one.

## ICs

!!! tiergloss
    These folders are optional. Add a subfolder per initial condition, and rename the file inside it
    to the name the location expects — below, two initial cell-position conditions both become
    `cells.csv`. Proceed the same way for `dcs/`, `ecms/`, and `substrates/`, renaming the files to
    `dcs.csv`, `ecm.csv`, and `substrates.csv`.

```
cells/
├── random_cells/
│   └── cells.csv
└── structured_cells/
    └── cells.csv
```

### IC cells

!!! tiergloss
    To generate `cells.csv` from geometries instead, place a `cells.xml` (see
    [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl)) in place of
    the `cells.csv`. You can vary it just as you vary a config or a rulesets collection.

### IC ecm

!!! tiergloss
    To generate `ecm.csv` from a defined structure instead, place an `ecm.xml` (see
    [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl)) in place of
    the `ecm.csv`. You can vary it just as you vary a config or a rulesets collection.
