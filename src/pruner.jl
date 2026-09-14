using Glob, Parameters

export PruneOptions

"""
    PruneOptions

Automatically prune some of the generated output files from a simulation.

# Fields
- `prune_svg::Bool=false`: Prune SVG files
- `prune_txt::Bool=false`: Prune TXT files
- `prune_mat::Bool=false`: Prune MAT files
- `prune_xml::Bool=false`: Prune XML files
- `prune_initial::Bool=false`: If any of the above are true, also prune the initial files for that type
- `prune_final::Bool=false`: If any of the above are true, also prune the final files for that type

# Examples
```jldoctest
julia> PruneOptions(prune_svg=true, prune_txt=true, prune_mat=true)
PruneOptions
  prune_mat: Bool true
  prune_svg: Bool true
  prune_txt: Bool true
  prune_xml: Bool false
  prune_initial: Bool false
  prune_final: Bool false
```
"""
@with_kw struct PruneOptions
    prune_mat::Bool = false
    prune_svg::Bool = false
    prune_txt::Bool = false
    prune_xml::Bool = false

    prune_initial::Bool = false
    prune_final::Bool = false
end

"""
    pruneSimulationOutput(simulation_id::Integer, prune_options::PruneOptions=PruneOptions())

Prune the output files from a simulation.

# Arguments
- `simulation_id::Integer`: The ID of the PhysiCell simulation. A [`Simulation`](@ref) object can also be passed in.
- `prune_options::PruneOptions=PruneOptions()`: The options for pruning the output files. See [`PruneOptions`](@ref) for more information.
```
"""
function pruneSimulationOutput(simulation_id::Integer, prune_options::PruneOptions=PruneOptions())
    path_to_output_folder = pathToOutputFolder(simulation_id)
    if prune_options.prune_svg
        glob("snapshot*.svg", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.svg", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.svg", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
    if prune_options.prune_txt
        glob("output*.txt", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.txt", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.txt", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
    if prune_options.prune_mat
        glob("output*.mat", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.mat", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.mat", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
    if prune_options.prune_xml
        glob("output*.xml", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.xml", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.xml", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
end

pruneSimulationOutput(simulation::Simulation, args...; kwargs...) = pruneSimulationOutput(simulation.id, args...; kwargs...)
