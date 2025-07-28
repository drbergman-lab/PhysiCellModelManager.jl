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
    pcmmDBVersion(is_new_db::Bool)

Returns the version of the PhysiCellModelManager.jl database. If the database does not exist, it creates a new one with the current PhysiCellModelManager.jl version.
"""
function pcmmDBVersion(is_new_db::Bool)
    #! check if versions table exists
    table_name = "pcmm_version"
    versions_exists = DBInterface.execute(centralDB(), "SELECT name FROM sqlite_master WHERE type='table' AND name='$(table_name)';") |> DataFrame |> x -> (length(x.name)==1)
    if !versions_exists
        createPCMMVersionTable(is_new_db)
    end
    return queryToDataFrame("SELECT * FROM $(table_name);") |> x -> x.version[1] |> VersionNumber
end

"""
    createPCMMVersionTable(is_new_db::Bool)

Creates the pcmm_version table in the database if it does not exist.
If is_new_db is true, it inserts the current PhysiCellModelManager.jl version into the table.
"""
function createPCMMVersionTable(is_new_db::Bool)
    table_name = "pcmm_version"
    DBInterface.execute(centralDB(), "CREATE TABLE IF NOT EXISTS $(table_name) (version TEXT PRIMARY KEY);")
    version = is_new_db ? pcmmVersion() : v"0.0.0"
    DBInterface.execute(centralDB(), "INSERT INTO $(table_name) (version) VALUES ('$version');")
end

"""
    resolvePCMMVersion(is_new_db::Bool, auto_upgrade::Bool)

Resolve differences between the PhysiCellModelManager.jl version and the database version.
If the PhysiCellModelManager.jl version is lower than the database version, it returns false (upgrade your version of PhysiCellModelManager.jl to match what was already used for the database).
If the PhysiCellModelManager.jl version is equal to the database version, it returns true.
If the PhysiCellModelManager.jl version is higher than the database version, it upgrades the database to the current PhysiCellModelManager.jl version and returns true.
"""
function resolvePCMMVersion(is_new_db::Bool, auto_upgrade::Bool)
    pcmm_version = pcmmVersion()
    pcmm_db_version = pcmmDBVersion(is_new_db)

    if pcmm_version < pcmm_db_version
        msg = """
        The PhysiCellModelManager.jl version is $(pcmm_version) but the database version is $(pcmm_db_version). \
        Upgrade your PhysiCellModelManager.jl version to $(pcmm_db_version) or higher:
            pkg> registry add https://github.com/drbergman/PCVCTRegistry
            pkg> registry up PCVCTRegistry
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