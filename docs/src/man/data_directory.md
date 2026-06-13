# Data directory structure

[`createProject`](@ref) builds this structure for you under `project-dir`. This page documents what each folder holds so you can add or edit inputs by hand.

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

Each terminal subdirectory under `data/inputs/` holds input folders whose names you choose. The examples below use `"baseline"`, but any name works.

## Configs

Place your base configuration file at `data/inputs/configs/baseline/PhysiCell_settings.xml`.

## Custom codes

Place the following in `data/inputs/custom_codes/baseline/`, exactly as used in a PhysiCell project:
- `main.cpp`
- `Makefile`
- `custom_modules/`

## Rulesets collections

Place your base ruleset collection at `data/inputs/rulesets_collections/baseline/base_rulesets.csv` (skip this if your project has no rules). You may instead place an XML file here, created from a CSV with [PhysiCellXMLRules.jl](https://github.com/drbergman-lab/PhysiCellXMLRules.jl).

**Important**: variations *must* target the XML version. After [`initializeModelManager`](@ref PhysiCellModelManager.initializeModelManager), any folder with `base_rulesets.csv` is populated with a `base_rulesets.xml` to reference for XML paths.

## Intracellulars

Place a single `intracellular.xml` at `data/inputs/intracellulars/baseline/`, with root children `cell_definitions` and `intracellulars`. Only libRoadRunner (ODEs) is currently supported; see `sample_projects_intracellular/combined/template-combined` for an example and [Intracellular inputs](@ref) for details.

## ICs

These folders are optional. For each initial condition, add a subfolder. For example, with two initial cell-position conditions `random_cells.csv` and `structured_cells.csv`, `data/inputs/ics/cells/` looks like:
```
cells/
├── random_cells/
│   └── cells.csv
└── structured_cells/
    └── cells.csv
```
**Note:** place each file in its folder and rename it to `cells.csv`.

Proceed similarly for `dcs/`, `ecms/`, and `substrates/`, renaming the files to `dcs.csv`, `ecm.csv`, and `substrates.csv`.

### IC cells

To generate `cells.csv` from geometries, place a `cells.xml` (see [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl)) in place of the `cells.csv`. You can vary it just as for `config` and `rulesets_collection`.

### IC ecm

To generate `ecm.csv` from a defined structure, place an `ecm.xml` (see [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl)) in place of the `ecm.csv`. You can vary it just as for `config` and `rulesets_collection`.