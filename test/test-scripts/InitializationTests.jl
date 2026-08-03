filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

#! A foreign ModelManager backend, to stand in for another simulator package owning the globals.
struct ForeignSimulator <: PhysiCellModelManager.ModelManager.AbstractSimulator end

#! By this point in the suite a project is initialized and PhysiCellModelManager.jl owns the globals.
@test PhysiCellModelManager.isInitialized()
@test PhysiCellModelManager._pcmmGlobalsRegistered()

#! The test suite is not writing a cache file or system image, so auto-initialization is not skipped.
@test PhysiCellModelManager._generatingOutput() == false

#! A redundant `__init__` is a no-op: the globals object and database handle are kept, not rebuilt.
globals_before = PhysiCellModelManager.ModelManager.mm_globals_ref[]
db_before = PhysiCellModelManager.centralDB()
data_dir_before = PhysiCellModelManager.dataDir()
physicell_dir_before = PhysiCellModelManager.physicellDir()

PhysiCellModelManager.__init__()

@test PhysiCellModelManager.ModelManager.mm_globals_ref[] === globals_before
@test PhysiCellModelManager.centralDB() === db_before
@test PhysiCellModelManager.dataDir() == data_dir_before
@test PhysiCellModelManager.physicellDir() == physicell_dir_before
@test PhysiCellModelManager.isInitialized()

#! The guard must fall through in every state except "ours, and initialized", so that `__init__`
#! claims the globals rather than running against a simulator it does not own.
let ref = PhysiCellModelManager.ModelManager.mm_globals_ref
    try
        ref[] = nothing
        @test PhysiCellModelManager._pcmmGlobalsRegistered() == false

        #! Another backend, fully initialized: still must not short-circuit.
        ref[] = ModelManagerGlobals(; simulator=ForeignSimulator(), initialized=true)
        @test PhysiCellModelManager._pcmmGlobalsRegistered() == false

        #! Ours, but initialization has not succeeded yet.
        ours = ModelManagerGlobals(; simulator=PhysiCellSimulator())
        ref[] = ours
        @test ours.initialized == false
        @test PhysiCellModelManager._pcmmGlobalsRegistered() == false

        #! Ours and initialized: the only state that short-circuits.
        ours.initialized = true
        @test PhysiCellModelManager._pcmmGlobalsRegistered()
    finally
        ref[] = globals_before
    end
end

#! The real project survived the swapping above.
@test PhysiCellModelManager.isInitialized()
@test PhysiCellModelManager.centralDB() === db_before
@test PhysiCellModelManager.dataDir() == data_dir_before
