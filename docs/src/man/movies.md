# [Movies](@id movies_man)

Turn a simulation's SVG snapshots into `output/out.mp4`.

!!! tiergloss
    [`makeMovie`](@ref) drives the PhysiCell Makefile to do the rendering, deleting the intermediate
    JPEGs afterward. It accepts a simulation ID, a trial object, a `run` result, or a vector or
    range of either, and makes one movie per simulation. ImageMagick and FFmpeg must be discoverable
    — on `PATH`, via `PCMM_IMAGEMAGICK_PATH`/`PCMM_FFMPEG_PATH`, or passed directly as
    `magick_path`/`ffmpeg_path`.

```julia
makeMovie(1)                # simulation 1 -> output/out.mp4
makeMovie(sampling)         # every simulation in a trial
makeMovie(out)              # every simulation in a `run` result
makeMovie(4:7)              # a range/vector of simulation IDs
makeMovie(Simulation.(4:7)) # a vector of trials
```

!!! tiergloss
    The Makefile's own animation variables are exposed as keyword arguments. Omit any of them to
    keep that Makefile's default.

| Keyword | Makefile variable | Typical default |
|---|---|---|
| `framerate` | `FRAMERATE` | 24 |
| `magick_density` | `MAGICK_DENSITY` | 96 |
| `magick_resize_x` | `MAGICK_RESIZE_X` | 1024 |
| `magick_resize_y` | `MAGICK_RESIZE_Y` | 1024 |

```julia
makeMovie(1; framerate=10, magick_density=48, magick_resize_x=512, magick_resize_y=512)
```

!!! tierwhy
    An omitted keyword is not passed to the Makefile at all, rather than being sent as a value
    PhysiCellModelManager.jl picked. A project that customized `FRAMERATE` or the `MAGICK_*`
    variables in its own Makefile therefore keeps those settings.

!!! tierjournal "2026-07-08 — Four keywords, each with a do-nothing default"
    **Decided.** `makeMovie` forwarded only the output folder to the Makefile, which also reads
    `FRAMERATE`, `MAGICK_DENSITY` and `MAGICK_RESIZE_X`/`_Y`; the four keywords expose them, each
    defaulting to a sentinel that is dropped instead of overriding the project's Makefile.
    **Decided.** `framerate` goes to the `movie` target and the three `magick_*` keywords to `jpeg`,
    matching which target reads which variable.
