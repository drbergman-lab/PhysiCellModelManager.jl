using Pkg

"""
    pcmmVersion()

Returns the version of the PhysiCellModelManager.jl package.
"""
function pcmmVersion()
    proj = Pkg.project()
    version = if proj.name == "PhysiCellModelManager"
        proj.version
    else
        deps = Pkg.dependencies()
        deps[proj.dependencies["PhysiCellModelManager"]].version
    end
    return version
end

"""
    pcmmDBVersion()

Returns the version of the PhysiCellModelManager.jl database. If the database does not exist, it creates a new one with the current PhysiCellModelManager.jl version.
"""
function pcmmDBVersion()
    #! check if versions table exists
    pcmm_version = versionFromTable("pcmm_version")
    if !isnothing(pcmm_version)
        return pcmm_version
    end
    #! if not, try looking for the old version table
    pcvct_version = versionFromTable("pcvct_version")
    if !isnothing(pcvct_version)
        return pcvct_version
    end
    #! if neither exists, create a new version table with the current pcmm version
    pcmm_version = pcmmVersion()
    DBInterface.execute(centralDB(), "CREATE TABLE IF NOT EXISTS pcmm_version (version TEXT PRIMARY KEY);")
    DBInterface.execute(centralDB(), "INSERT INTO pcmm_version (version) VALUES ('$(pcmm_version)');")

    return pcmm_version
end

"""
    versionFromTable(table_name::String)

Returns the version from the specified table if it exists, otherwise returns nothing.
"""
function versionFromTable(table_name::String)
    if !(DBInterface.execute(centralDB(), "SELECT name FROM sqlite_master WHERE type='table' AND name='$(table_name)';") |> DataFrame |> x -> (length(x.name) == 1))
        return nothing
    end

    return queryToDataFrame("SELECT * FROM $(table_name);") |> x -> x.version[1] |> VersionNumber
end

"""
    resolvePCMMVersion(auto_upgrade::Bool)

Resolve differences between the PhysiCellModelManager.jl version and the database version.
If the PhysiCellModelManager.jl version is lower than the database version, it returns false (upgrade your version of PhysiCellModelManager.jl to match what was already used for the database).
If the PhysiCellModelManager.jl version is equal to the database version, it returns true.
If the PhysiCellModelManager.jl version is higher than the database version, it upgrades the database to the current PhysiCellModelManager.jl version and returns true.
"""
function resolvePCMMVersion(auto_upgrade::Bool)
    pcmm_version = pcmmVersion()
    pcmm_db_version = pcmmDBVersion()

    if pcmm_version < pcmm_db_version
        msg = """
        The PhysiCellModelManager.jl version is $(pcmm_version) but the database version is $(pcmm_db_version). \
        Upgrade your PhysiCellModelManager.jl version to $(pcmm_db_version) or higher:
            pkg> registry add https://github.com/drbergman-lab/BergmanLabRegistry
            pkg> registry up BergmanLabRegistry
        """
        println(msg)
        success = false
        return success
    end

    if pcmm_version == pcmm_db_version
        success = true
        return success
    end

    success = upgradePCMM(pcmm_db_version, pcmm_version, auto_upgrade)
    return success
end
