export makeMovie

"""
    makeMovie(simulation_id::Integer; magick_path::Union{Missing,String}=simulator().path_to_magick, ffmpeg_path::Union{Missing,String}=simulator().path_to_ffmpeg)
    makeMovie(T::AbstractTrial; kwargs...)
    makeMovie(out::PCMMOutput; kwargs...)
    makeMovie(simulation_ids::AbstractVector{<:Integer}; kwargs...)
    makeMovie(Ts::AbstractVector{<:AbstractTrial}; kwargs...)

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
- `simulation_id::Integer`: The ID of the simulation for which to make the movie.
- `T::AbstractTrial`: Make movies for all simulations in the [`AbstractTrial`](@ref).
- `out::PCMMOutput`: Make movies for all simulations in the output, i.e., all simulations in the completed trial.
- `simulation_ids::AbstractVector{<:Integer}`: Make movies for each simulation ID in the collection (e.g. a range such as `4:7`).
- `Ts::AbstractVector{<:AbstractTrial}`: Make movies for every simulation across the collection of trials (e.g. `Simulation.(4:7)`).

# Keyword Arguments
- `magick_path::Union{Missing,String}`: The path to the ImageMagick executable. If not provided, uses `simulator().path_to_magick`.
- `ffmpeg_path::Union{Missing,String}`: The path to the FFmpeg executable. If not provided, uses `simulator().path_to_ffmpeg`.
- `verbose::Bool`: If `true`, prints the output of the commands used to generate the movie. Default is `false`.
- `framerate::Union{Missing,Int}`: Frames per second, forwarded to the Makefile's `FRAMERATE` variable. If not provided, uses the Makefile's own default.
- `magick_density::Union{Missing,Int}`: JPEG rendering density (dpi), forwarded to the Makefile's `MAGICK_DENSITY` variable. If not provided, uses the Makefile's own default.
- `magick_resize_x::Union{Missing,Int}`: JPEG resize width, forwarded to the Makefile's `MAGICK_RESIZE_X` variable. If not provided, uses the Makefile's own default.
- `magick_resize_y::Union{Missing,Int}`: JPEG resize height, forwarded to the Makefile's `MAGICK_RESIZE_Y` variable. If not provided, uses the Makefile's own default.

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
```julia
makeMovie(123; framerate=10, magick_density=48, magick_resize_x=512, magick_resize_y=512)
```
```julia
makeMovie(4:7) # make movies for simulations 4, 5, 6, and 7
makeMovie(Simulation.(4:7)) # equivalent, passing Simulation objects
```
"""
function makeMovie(simulation_id::Integer; magick_path::Union{Missing,String}=simulator().path_to_magick, ffmpeg_path::Union{Missing,String}=simulator().path_to_ffmpeg, verbose::Bool=false,
    framerate::Union{Missing,Int}=missing, magick_density::Union{Missing,Int}=missing, magick_resize_x::Union{Missing,Int}=missing, magick_resize_y::Union{Missing,Int}=missing)
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
    if !ModelManager.shellCommandExists("magick")
        throw(ErrorException("ImageMagick is not installed. Please install it to generate movies."))
    elseif !ModelManager.shellCommandExists("ffmpeg")
        throw(ErrorException("FFmpeg is not installed. Please install it to generate movies."))
    end
    svgs = filter(f -> startswith(basename(f), "s") && endswith(f, ".svg"), readdir(path_to_output_folder))
    if isempty(svgs)
        @warn "No SVG files found in $(path_to_output_folder), skipping movie generation."
        movie_generated = false
        return movie_generated
    end
    jpeg_args = ["make", "jpeg", "OUTPUT=$(path_to_output_folder)"]
    ismissing(magick_density) || push!(jpeg_args, "MAGICK_DENSITY=$(magick_density)")
    ismissing(magick_resize_x) || push!(jpeg_args, "MAGICK_RESIZE_X=$(magick_resize_x)")
    ismissing(magick_resize_y) || push!(jpeg_args, "MAGICK_RESIZE_Y=$(magick_resize_y)")
    cmd = Cmd(Cmd(jpeg_args); env=env, dir=physicellDir())
    verbose ? run(cmd) : quietRun(cmd)

    movie_args = ["make", "movie", "OUTPUT=$(path_to_output_folder)"]
    ismissing(framerate) || push!(movie_args, "FRAMERATE=$(framerate)")
    cmd = Cmd(Cmd(movie_args); env=env, dir=physicellDir())
    verbose ? run(cmd) : quietRun(cmd)
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
        simulator().path_to_magick = magick_path
    end
    if !ismissing(ffmpeg_path)
        simulator().path_to_ffmpeg = ffmpeg_path
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

function makeMovie(simulation_ids::AbstractVector{<:Integer}; kwargs...)
    println("Making movies for $(length(simulation_ids)) simulations...")
    for simulation_id in simulation_ids
        print("  Making movie for simulation $simulation_id...")
        makeMovie(simulation_id; kwargs...)
        println("done.")
    end
end

makeMovie(Ts::AbstractVector{<:AbstractTrial}; kwargs...) = makeMovie(simulationIDs(Ts); kwargs...)