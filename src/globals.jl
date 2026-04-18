using SQLite

"""
    findCentralDB()

Locate the central SQLite database file and connect to it, updating the global state.
Checks for a legacy `vct.db` file first, then falls back to `pcmm.db`.
"""
function findCentralDB()
    path_to_db(f) = joinpath(dataDir(), f)
    old_db_path = path_to_db("vct.db")
    path_to_central_db = isfile(old_db_path) ? old_db_path : path_to_db("pcmm.db")
    mm_globals().db = SQLite.DB(path_to_central_db)
end

"""
    physicellDir()

Return the PhysiCell source directory for the current project.
"""
physicellDir() = simulator().dir
