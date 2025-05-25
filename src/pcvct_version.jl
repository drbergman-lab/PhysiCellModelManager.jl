using Pkg

"""
    pcvctVersion()

Returns the version of the pcvct package.
"""
function pcvctVersion()
    proj = Pkg.project()
    version = if proj.name == "pcvct"
        proj.version
    else
        deps = Pkg.dependencies()
        deps[proj.dependencies["pcvct"]].version
    end
    return version
end

"""
    pcvctDBVersion(is_new_db::Bool)

Returns the version of the pcvct database. If the database does not exist, it creates a new one with the current pcvct version.
"""
function pcvctDBVersion(is_new_db::Bool)
    #! check if versions table exists
    table_name = "pcvct_version"
    versions_exists = DBInterface.execute(centralDB(), "SELECT name FROM sqlite_master WHERE type='table' AND name='$(table_name)';") |> DataFrame |> x -> (length(x.name)==1)
    if !versions_exists
        createPCVCTVersionTable(is_new_db)
    end
    return queryToDataFrame("SELECT * FROM $(table_name);") |> x -> x.version[1] |> VersionNumber
end

"""
    createPCVCTVersionTable(is_new_db::Bool)

Creates the pcvct_version table in the database if it does not exist.
If is_new_db is true, it inserts the current pcvct version into the table.
"""
function createPCVCTVersionTable(is_new_db::Bool)
    table_name = "pcvct_version"
    DBInterface.execute(centralDB(), "CREATE TABLE IF NOT EXISTS $(table_name) (version TEXT PRIMARY KEY);")
    version = is_new_db ? pcvctVersion() : v"0.0.0"
    DBInterface.execute(centralDB(), "INSERT INTO $(table_name) (version) VALUES ('$version');")
end

"""
    resolvePCVCTVersion(is_new_db::Bool, auto_upgrade::Bool)

Resolve differences between the pcvct version and the database version.
If the pcvct version is lower than the database version, it returns false (upgrade your version of pcvct to match what was already used for the database).
If the pcvct version is equal to the database version, it returns true.
If the pcvct version is higher than the database version, it upgrades the database to the current pcvct version and returns true.
"""
function resolvePCVCTVersion(is_new_db::Bool, auto_upgrade::Bool)
    pcvct_version = pcvctVersion()
    pcvct_db_version = pcvctDBVersion(is_new_db)

    if pcvct_version < pcvct_db_version
        msg = """
        The pcvct version is $(pcvct_version) but the database version is $(pcvct_db_version). \
        Upgrade your pcvct version to $(pcvct_db_version) or higher:
            pkg> registry add https://github.com/drbergman/PCVCTRegistry
            pkg> registry up PCVCTRegistry
        """
        println(msg)
        success = false
        return success
    end

    if pcvct_version == pcvct_db_version
        success = true
        return success
    end

    success = upgradePCVCT(pcvct_db_version, pcvct_version, auto_upgrade)
    return success
end