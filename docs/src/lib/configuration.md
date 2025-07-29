```@meta
CollapsedDocStrings = true
```

# Configuration

Interface with the configuration file necessary for PhysiCell simulations.

Provide functionality for accessing and modifying elements in any XML, including the PhysiCell configuration file, XML rules file, combined intracellular XML file, XML IC cell file, and XML IC ECM file.

## Config XML paths
The [`configPath`](@ref) is the most user-friendly way to create the XML path to (most) any parameter in the configuration file.
The following functions are called by `configPath` and are more foolproof but less robust:

|                                      |                                  |                                                  |                                   |
|--------------------------------------|----------------------------------|--------------------------------------------------|-----------------------------------|
| [`pcvct.domainPath`](@ref)           | [`pcvct.timePath`](@ref)         | [`pcvct.fullSavePath`](@ref)                     | [`pcvct.svgSavePath`](@ref)       |
| [`pcvct.domainPath`](@ref)           | [`pcvct.timePath`](@ref)         | [`pcvct.fullSavePath`](@ref)                     | [`pcvct.svgSavePath`](@ref)       |
| [`pcvct.substratePath`](@ref)        | [`pcvct.cyclePath`](@ref)        | [`pcvct.apoptosisPath`](@ref)                    | [`pcvct.necrosisPath`](@ref)      |
| [`pcvct.volumePath`](@ref)           | [`pcvct.mechanicsPath`](@ref)    | [`pcvct.motilityPath`](@ref)                     | [`pcvct.secretionPath`](@ref)     |
| [`pcvct.cellInteractionsPath`](@ref) | [`pcvct.phagocytosisPath`](@ref) | [`pcvct.attackRatePath`](@ref)                   | [`pcvct.fusionPath`](@ref)        |
| [`pcvct.integrityPath`](@ref)        | [`pcvct.customDataPath`](@ref)   | [`pcvct.initialParameterDistributionPath`](@ref) | [`pcvct.userParameterPath`](@ref) |

Here is a near-exhaustive list of the available tokens (the flexibiilty of `configPath` allows for some of these XML paths to be created in multiple ways):

### Single tokens
The following can be passed in alone to `configPath`:
```julia
- "x_min", "x_max", "y_min", "y_max", "z_min", "z_max", "dx", "dy", "dz", "use_2D" (`domainPath`)
- "max_time", "dt_intracellular", "dt_diffusion", "dt_mechanics", "dt_phenotype" (`timePath`)
- "full_data_interval" (`fullSavePath`)
- "SVG_save_interval" (`svgSavePath`)
```

### Double tokens
The following can be passed in as the second argument to `configPath(<substrate_name>, <token>)` where `<substrate_name>` is the name of the substrate in your model:
```julia
- "diffusion_coefficient", "decay_rate"
- "initial_condition", "Dirichlet_boundary_condition"
- "xmin", "xmax", "ymin", "ymax", "zmin", "zmax"
```

The following can be passed in as the second argument to `configPath(<cell_type>, <token>)` where `<cell_type>` is the name of the cell type in your model:
```julia
- "total", "fluid_fraction", "nuclear", "fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcified_fraction", "calcification_rate", "relative_rupture_volume" (`volumePath`)
- "cell_cell_adhesion_strength", "cell_cell_repulsion_strength", "relative_maximum_adhesion_distance", "attachment_elastic_constant", "attachment_rate", "detachment_rate", "maximum_number_of_attachments" (`mechanicsPath`)
- "set_relative_equilibrium_distance", "set_absolute_equilibrium_distance" (`mechanicsPath`)
- "speed", "persistence_time", "migration_bias" (`motilityPath`)
- "apoptotic_phagocytosis_rate", "necrotic_phagocytosis_rate", "other_dead_phagocytosis_rate", "attack_damage_rate", "attack_duration" (`cellInteractionsPath`)
- "damage_rate", "damage_repair_rate" (`integrityPath`)
- "custom:<tag>" (`customDataPath`)
```

Finally, for a user parameter you can use the following:
```julia
configPath("user_parameters", <tag>)
```
where `<tag>` is the name of the user parameter in your model.

### Triple tokens
The following can be passed in as the third argument to `configPath(<substrate_name>, "Dirichlet_options", <token>)` where `<substrate_name>` is the name of the substrate in your model:
```julia
- "xmin", "xmax", "ymin", "ymax", "zmin", "zmax" (`substratePath`)
```

The following tokens work with a `cell_type` from your model:
```julia
- `configPath(<cell_type>, "cycle_rate", <start_index>)` (`cyclePath`)
- `configPath(<cell_type>, "cycle_duration", <index>)` (`cyclePath`)
- `configPath(<cell_type>, "apoptosis", <parameter>)` (`apoptosisPath`)
- `configPath(<cell_type>, "necrosis", <parameter>)` (`necrosisPath`)
- `configPath(<cell_type>, "adhesion", <cell_type>)` (`mechanicsPath`)
- `configPath(<cell_type>, "motility", <parameter>)` (`motilityPath`)
- `configPath(<cell_type>, "chemotaxis", <parameter>)` (`motilityPath`)
- `configPath(<cell_type>, "advanced_chemotaxis", <parameter>)` (`motilityPath`)
- `configPath(<cell_type>, "advanced_chemotaxis", <substrate_name>)` (`motilityPath`)
- `configPath(<cell_type>, <substrate_name>, <parameter>)` (`secretionPath`)
- `configPath(<cell_type>, <interaction>, <cell_type>)` (`<interaction>` is one of "phagocytosis", "fusion", "transformation", "attack_rate") (`cellInteractionsPath`)
- `configPath(<cell_type>, "custom", <tag>)` (`customDataPath`)
```

### Four tokens
The following tokens work with a `cell_type` from your model:
```julia
- `configPath(<cell_type>, "cycle", "duration", <index>)` (`cyclePath`)
- `configPath(<cell_type>, "cycle", "rate", <start_index>)` (`cyclePath`)
- `configPath(<cell_type>, "necrosis", "duration", <index>)` (`necrosisPath`)
- `configPath(<cell_type>, "necrosis", "transition_rate", <start_index>)` (`necrosisPath`)
- `configPath(<cell_type>, "initial_parameter_distribution", <behavior>, <parameter>)` (`initialParameterDistributionPath`)
```

## Main XML path functions
```@docs; canonical=false
configPath
rulePath
icCellsPath
icECMPath
```

## Config file specific functions
```@docs; canonical=false
pcvct.domainPath
pcvct.timePath
pcvct.fullSavePath
pcvct.svgSavePath
pcvct.substratePath
pcvct.cyclePath
pcvct.apoptosisPath
pcvct.necrosisPath
pcvct.volumePath
pcvct.mechanicsPath
pcvct.motilityPath
pcvct.secretionPath
pcvct.cellInteractionsPath
pcvct.phagocytosisPath
pcvct.attackRatePath
pcvct.fusionPath
pcvct.integrityPath
pcvct.customDataPath
pcvct.initialParameterDistributionPath
pcvct.userParameterPath
```

## Public API
```@autodocs
Modules = [pcvct]
Pages = ["configuration.jl"]
Private = false
```

## Private API
```@autodocs
Modules = [pcvct]
Pages = ["configuration.jl"]
Public = false
```