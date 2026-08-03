# [Movies](@id movies_man)

[`makeMovie`](@ref) uses the PhysiCell Makefile to turn a simulation's SVG snapshots into
`output/out.mp4`, deleting the intermediate JPEGs afterward. It requires ImageMagick and FFmpeg
to be discoverable — on `PATH`, via `PCMM_IMAGEMAGICK_PATH`/`PCMM_FFMPEG_PATH`, or passed
directly as `magick_path`/`ffmpeg_path`.

```julia
makeMovie(1)                # simulation 1 -> output/out.mp4
makeMovie(sampling)         # every simulation in a trial
makeMovie(out)              # every simulation in a `run` result
makeMovie(4:7)              # a range/vector of simulation IDs
makeMovie(Simulation.(4:7)) # a vector of trials
```

The Makefile's own animation variables are exposed as keyword arguments. Omit any of them to
keep that Makefile's default:

| Keyword | Makefile variable | Typical default |
|---|---|---|
| `framerate` | `FRAMERATE` | 24 |
| `magick_density` | `MAGICK_DENSITY` | 96 |
| `magick_resize_x` | `MAGICK_RESIZE_X` | 1024 |
| `magick_resize_y` | `MAGICK_RESIZE_Y` | 1024 |

```julia
makeMovie(1; framerate=10, magick_density=48, magick_resize_x=512, magick_resize_y=512)
```
