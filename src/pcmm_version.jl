"""
    pcmmVersion()

Return the runtime version of PhysiCellModelManager.jl.
"""
pcmmVersion() = getPackageVersion(simulator())

"""
    pcmmDBVersion()

Return the version of the PhysiCellModelManager.jl database schema. If no version
table exists yet, one is created and stamped with the current package version.
"""
pcmmDBVersion() = getDBPackageVersion(simulator(), centralDB())

"""
    resolvePCMMVersion(auto_upgrade::Bool)

Compare the package version against the database version and upgrade if needed.
Returns `true` when the database is at the current package version, `false` otherwise.
"""
resolvePCMMVersion(auto_upgrade::Bool) = resolvePackageVersion(simulator(), centralDB(); auto_upgrade=auto_upgrade)
