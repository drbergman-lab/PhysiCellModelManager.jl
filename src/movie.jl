export makeMovie

"""
    makeMovie(simulation_id::Int; magick_path::Union{Missing,String}=pcmm_globals.path_to_magick, ffmpeg_path::Union{Missing,String}=pcmm_globals.path_to_ffmpeg)
    makeMovie(T::AbstractTrial; kwargs...)
    makeMovie(out::PCMMOutput; kwargs...)

Batch make movies for each simulation identified by the input.

Use the PhysiCell Makefile to generate the movie.
This process requires first generating JPEG files, which are then used to create the movie.
Deletes the JPEG files after the movie is generated.

This relies on ImageMagick and FFmpeg being installed on the system.
There are three ways to allow this function to find these dependencies:
  1. Pass the path to the dependencies using the `magick_path` and `ffmpeg_path` keyword arguments.
  2. Set the `PATH` environment variable to include the directories containing the dependencies.
  3. Set environment variables `PCMM_IMAGEMAGICK_PATH` and `PCMM_FFMPEG_PATH` before `using PhysiCellModelManager`.

# Arguments
- `simulation_id::Int`: The ID of the simulation for which to make the movie.
- `T::AbstractTrial`: Make movies for all simulations in the [`AbstractTrial`](@ref).
- `out::PCMMOutput`: Make movies for all simulations in the output, i.e., all simulations in the completed trial.

# Keyword Arguments
- `magick_path::Union{Missing,String}`: The path to the ImageMagick executable. If not provided, uses the global variable `pcmm_globals.path_to_magick`.
- `ffmpeg_path::Union{Missing,String}`: The path to the FFmpeg executable. If not provided, uses the global variable `pcmm_globals.path_to_ffmpeg`.

# Example
```julia
makeMovie(123) # make a movie for simulation 123
```
```julia
makeMovie(sampling) # make movies for all simulations in the sampling
```
```julia
out = run(sampling) # run the sampling
makeMovie(out) # make movies for all simulations in the output
```
"""
function makeMovie(simulation_id::Int; magick_path::Union{Missing,String}=pcmm_globals.path_to_magick, ffmpeg_path::Union{Missing,String}=pcmm_globals.path_to_ffmpeg)
    assertInitialized()
    path_to_output_folder = joinpath(trialFolder(Simulation, simulation_id), "output")
    if isfile("$(path_to_output_folder)/out.mp4")
        movie_generated = false
        return movie_generated
    end
    env = copy(ENV)
    os_variable_separator = Sys.iswindows() ? ";" : ":"
    path_components = split(env["PATH"], os_variable_separator)
    resolveMovieGlobals(magick_path, ffmpeg_path)
    if !ismissing(magick_path) && !(magick_path ∈ path_components)
        env["PATH"] = "$(magick_path)$(os_variable_separator)$(env["PATH"])"
    end
    if !ismissing(ffmpeg_path) && !(ffmpeg_path ∈ path_components) && ffmpeg_path != magick_path
        env["PATH"] = "$(ffmpeg_path)$(os_variable_separator)$(env["PATH"])"
    end
    if !shellCommandExists("magick")
        throw(ErrorException("ImageMagick is not installed. Please install it to generate movies."))
    elseif !shellCommandExists("ffmpeg")
        throw(ErrorException("FFmpeg is not installed. Please install it to generate movies."))
    end
    cmd = Cmd(`make jpeg OUTPUT=$(path_to_output_folder)`; env=env, dir=physicellDir())
    quietRun(cmd)
    cmd = Cmd(`make movie OUTPUT=$(path_to_output_folder)`; env=env, dir=physicellDir())
    quietRun(cmd)
    movie_generated = true
    jpgs = readdir(joinpath(trialFolder(Simulation, simulation_id), "output"), sort=false)
    filter!(f -> endswith(f, ".jpg"), jpgs)
    for jpg in jpgs
        rm(joinpath(trialFolder(Simulation, simulation_id), "output", jpg))
    end
    return movie_generated
end

"""
    resolveMovieGlobals(magick_path::Union{Missing,String}, ffmpeg_path::Union{Missing,String})

Set the global variables `path_to_magick` and `path_to_ffmpeg` to the provided paths.
"""
function resolveMovieGlobals(magick_path::Union{Missing,String}, ffmpeg_path::Union{Missing,String})
    if !ismissing(magick_path)
        pcmm_globals.path_to_magick = magick_path
    end
    if !ismissing(ffmpeg_path)
        pcmm_globals.path_to_ffmpeg = ffmpeg_path
    end
end

function makeMovie(T::AbstractTrial; kwargs...)
    simulation_ids = simulationIDs(T)
    println("Making movies for $(typeof(T)) $(T.id) with $(length(simulation_ids)) simulations...")
    for simulation_id in simulation_ids
        print("  Making movie for simulation $simulation_id...")
        makeMovie(simulation_id; kwargs...)
        println("done.")
    end
end

makeMovie(T::PCMMOutput; kwargs...) = makeMovie(T.trial; kwargs...)