"""
    ModelManager.centralDBFileName(::PhysiCellSimulator)

Return the database filename for a PhysiCell project.  Checks for the legacy `vct.db`
name first (pre-PCMM projects), then falls back to `pcmm.db`.
"""
function ModelManager.centralDBFileName(::PhysiCellSimulator)
    old_db = joinpath(mm_globals().data_dir, "vct.db")
    return isfile(old_db) ? "vct.db" : "pcmm.db"
end

"""
    physicellDir()

Return the PhysiCell source directory for the current project.
"""
physicellDir() = simulator().dir
