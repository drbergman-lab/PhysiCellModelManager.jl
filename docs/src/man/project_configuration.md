# [Project configuration](@id project_configuration_man)

The `inputs.toml` file, in the project's `data/inputs/` directory, declares the project's inputs.

## TOML-defined structure

!!! tiergloss
    Each section defines one input "location" — one of the terminal subdirectories described in
    [Data directory structure](@ref data_directory_man).

```toml
[config]
required = true
varied = true
basename = "PhysiCell_settings.xml"
```

!!! tiergloss
    On initialization (`using PhysiCellModelManager`, or
    [`initializeModelManager`](@ref PhysiCellModelManager.initializeModelManager)), each entry —
    `config` above — is parsed into four features: `required`, `basename`, `varied`, and
    `path_from_inputs`.

### [`required`](@id required_section)

!!! tiergloss
    Necessary; must be `true` or `false`. If `true`, an [`InputFolders`](@ref) object cannot be
    created without this location.

### [`basename`](@id basename_section)

!!! tiergloss
    Enforces the name of the file used for the location. A vector may be supplied, in the order the
    files are looked for, when several names are acceptable. Necessary if `varied` is `true`; may be
    omitted if `varied` is `false`.

### [`varied`](@id varied_section)

!!! tiergloss
    Necessary; must be `true`, `false`, or a vector of Booleans matching the length of the
    `basename` vector. If `true`, the location can be varied, and the databases and folders that
    support that are created.

### [`path_from_inputs`](@id path_from_inputs_section)

!!! tiergloss
    Optional; sets the path to the location relative to the `inputs` directory, as a vector of
    strings — `["ics", "cells"]` puts the `[ic_cell]` location at `inputs/ics/cells`. If omitted,
    the path is `inputs/<section name>s`, so the `config` section above lives at `inputs/configs`
    (note the pluralization).
