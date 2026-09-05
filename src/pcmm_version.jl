"""
    pcmmVersion()

Return the version of PhysiCellModelManager.jl installed in the active environment.

This is what `Pkg.status` prints and what `Pkg.update` changes — not necessarily the version
running in this session. The two differ when the environment is changed with `Pkg` while a
session is open; ModelManager distinguishes them because database migrations target the *loaded*
version, matching the code that is actually executing.
"""
pcmmVersion() = getInstalledVersion(simulator())

"""
    pcmmDBVersion()

Return the version of the PhysiCellModelManager.jl database schema. If no version
table exists yet, one is created and stamped with the current package version.
"""
pcmmDBVersion() = getDBPackageVersion(simulator(), centralDB())

