filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

if Sys.isapple()
    makeMovie(Simulation(1))
    @test isfile(joinpath(PhysiCellModelManager.dataDir(), "outputs", "simulations", "1", "output", "out.mp4"))
    @test makeMovie(1) === false
    @test makeMovie(run(Simulation(1))) |> isnothing #! makeMovie on the PCMMOutput object
else
    @test_throws ErrorException makeMovie(Simulation(1))
end