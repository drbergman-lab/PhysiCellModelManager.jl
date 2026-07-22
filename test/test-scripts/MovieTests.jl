filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

if Sys.isapple()
    makeMovie(Simulation(1); verbose=true)
    @test isfile(joinpath(PhysiCellModelManager.dataDir(), "outputs", "simulations", "1", "output", "out.mp4"))
    @test makeMovie(1; verbose=true) === false
    @test makeMovie(run(Simulation(1)); verbose=true) |> isnothing #! makeMovie on the PCMMOutput object

    sim = Simulation(1)
    inputs = sim.inputs
    variation_id = sim.variation_id

    #! Test that the framerate/magick_density/magick_resize_x/magick_resize_y kwargs still produce a movie
    custom_params_sim = Simulation(inputs, variation_id)
    run(custom_params_sim)
    @test makeMovie(custom_params_sim.id; framerate=10, magick_density=48, magick_resize_x=256, magick_resize_y=256)
    @test isfile(joinpath(PhysiCellModelManager.dataDir(), "outputs", "simulations", string(custom_params_sim.id), "output", "out.mp4"))

    #! Batch over a range of IDs and a vector of Simulations (out.mp4 already exists for these, so each is a no-op)
    @test makeMovie(1:1) |> isnothing
    @test makeMovie(Simulation.(1:1)) |> isnothing

    #! Test that makeMovie returns false if no SVGs are found
    new_sim = Simulation(inputs, variation_id)
    out = run(new_sim)

    path_to_output_folder = joinpath(PhysiCellModelManager.dataDir(), "outputs", "simulations", string(new_sim.id), "output")
    svgs = filter(f -> startswith(basename(f), "s") && endswith(f, ".svg"), readdir(path_to_output_folder; join=true))
    for svg in svgs
        rm(svg)
    end
    @test !makeMovie(new_sim.id)
    @test_warn "No SVG files found in $(path_to_output_folder), skipping movie generation." makeMovie(new_sim)
else
    @test_throws ErrorException makeMovie(Simulation(1); verbose=true)
end