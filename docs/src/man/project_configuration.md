# Project configuration

The `inputs.toml` file is used to configure the inputs for the project.
It is located in the `inputs` directory within the project data directory.

## TOML-defined structure
Each section of the `inputs.toml` file defines one of the input "locations" in the project.
An example of the structure is as follows:

```toml
[config]
required = true
varied = true
basename = "PhysiCell_settings.xml"
```

Upon initialization of the model manager, i.e., calling `using PhysiCellModelManager` (or [`initializeModelManager`](@ref)), the `inputs.toml` file is parsed and each entry (`config` is shown above) has four features stored:
- `required`: A boolean indicating if the location is required for the model to run.
- `basename`: The base name of the file to be used for the location.
- `varied`: A boolean indicating if the location can vary between different model runs.
- `path_from_inputs`: The path to the location relative to the `inputs` directory.

### `required`
This field is necessary and must either be `true` or `false`.
If `true`, an `InputsFolder` object cannot be created without this location.

### `basename`
This field enforces the name of the file to be used for the location.
A vector can be supplied of names in the order to look for the files in cases when multiple files are acceptable.
This field is necessary if `varied` is `true`, but can be omitted if `varied` is `false`.

### `varied`
This field is necessary and must either be `true`, `false`, or a vector of Booleans matching the length of the `basename` vector.
If `true`, the location can be varied and the necessary databases and folders are created to support this.

### `path_from_inputs`
This optional field sets the path to the location relative to the `inputs` directory.
If not provided, the path is assumed to be `inputs/<dict_name>s`.
For example, the `config` section above would be located at `inputs/configs` (note the pluralization of the section name).
To provide this path, use a vector of strings, e.g., `["ics", "cells"]` to define the path to the `[ic_cell]` location as `inputs/ics/cells`.