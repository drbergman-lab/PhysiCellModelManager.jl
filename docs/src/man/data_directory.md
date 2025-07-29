# Data directory structure

To set up your PhysiCellModelManager.jl-enabled repository within `project-dir` (the name of your project directory), create the following directory structure:

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

Within each of the terminal subdirectories above within `data/inputs/`, add a subdirectory with a user-defined name with content described below.
We will use the name `"default"` for all as an example.

## Configs

Add a single file within `data/inputs/configs/default/` called `PhysiCell_settings.xml` with the base configuration file for your PhysiCell project.

## Custom codes

Add within `data/inputs/custom_codes/default/` the following, each exactly as is used in a PhysiCell project:
- `main.cpp`
- `Makefile`
- `custom_modules/`

## Rulesets collections

Add a single file within `data/inputs/rulesets_collections/default/` called `base_rulesets.csv` with the base ruleset collection for your PhysiCell project.
If your project does not use rules, you can skip this step.

You may also place an XML file here. Use [PhysiCellXMLRules.jl](https://github.com/drbergman-lab/PhysiCellXMLRules.jl) to create one from a standard CSV version of the rules.

**Important**: In either case, the variations you define *must* be on the XML version.
After calling `initializeModelManager()`, any folder with `base_rulesets.csv` will now be populated with a `base_rulesets.xml` file that can be reference to set the XML paths.

## Intracellulars

Add a single XML file within `data/inputs/intracellulars/default/` called `intracellular.xml` in which the root has two child elements: `cell_definitions` and `intracellulars`.
This currently only supports libRoadRunner, i.e., ODEs.
See the `sample_projects_intracellular/combined/template-combined` for an example.
See [Intracellular inputs](@ref) for much more information.

## ICs

These folders are optional as not every model includes initial conditions as separate files.
If your model does, for each initial condition add a subfolder.
For example, if you have two initial cell position conditions, `random_cells.csv` and `structured_cells.csv`, the `data/inputs/ics/cells/` directory would look like this:
```
cells/
├── random_cells/
│   └── cells.csv
└── structured_cells/
    └── cells.csv
```
**Note:** Place the files in their corresponding folders and rename to `cells.csv`.

Proceed similarly for `dcs/`, `ecms/`, and `substrates/`, renaming those files to `dcs.csv`, `ecm.csv`, and `substrates.csv`, respectively.

### IC cells

PhysiCellModelManager.jl uses [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) to allow for creation of `cells.csv` files based on geometries defined in a `cells.xml` file.
To use this, first create such an XML document (see [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) for details) and place this in place of the `cells.csv` file.
You may make variations on this in the same way as for `config` and `rulesets_collection`.

### IC ecm

PhysiCellModelManager.jl uses [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl) to allow for creation of `ecm.csv` files based on the structure defined in a `ecm.xml` file.
To use this, first create such an XML document (see [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl) for details) and place this in place of the `ecm.csv` file.
You may make variations on this in the same way as for `config` and `rulesets_collection`.