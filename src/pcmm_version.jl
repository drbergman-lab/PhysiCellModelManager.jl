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

