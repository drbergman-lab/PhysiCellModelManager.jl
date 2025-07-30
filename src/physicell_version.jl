using SQLite

"""
    resolvePhysiCellVersionID()

Get the PhysiCell version ID from the database, adding it to the database if it doesn't exist.
"""
function resolvePhysiCellVersionID()
    if !physicellIsGit()

        tag = readlines(joinpath(physicellDir(), "VERSION.txt"))[1]
        full_tag = "$tag-download"

        stmt = SQLite.Stmt(centralDB(),
            "INSERT OR IGNORE INTO physicell_versions (commit_hash) VALUES (:full_tag) RETURNING physicell_version_id;"
        )
        params = (; :full_tag => full_tag)
        df = stmtToDataFrame(stmt, params)
        if isempty(df)
            where_str = "WHERE commit_hash=(:full_tag)"
            stmt_str = constructSelectQuery("physicell_versions", where_str; selection="physicell_version_id")
            stmt = SQLite.Stmt(centralDB(), stmt_str)
            df = stmtToDataFrame(stmt, params; is_row=true)
        end
        return df.physicell_version_id[1]
    end

    repo_is_dirty = false
    if !gitDirectoryIsClean(physicellDir())
        println("""
        \nWARNING: PhysiCell repo is dirty. The latest commit hash will be marked with the "-dirty" suffix in the database.
        These results may not be reproducible.
        To regain reproducibility, make a new commit or stash changes to clean the repository.
        To see the changed files, run the following command from your terminal:\n
        \tgit -C $(physicellDir()) status
        """
        )
        repo_is_dirty = true
    end

    #! then, get the current commit hash
    commit_hash = readchomp(`git -C $(physicellDir()) rev-parse HEAD`)
    commit_hash *= repo_is_dirty ? "-dirty" : ""

    #! then, compare that hash with hashes in the database
    query = constructSelectQuery("physicell_versions", "WHERE commit_hash = '$commit_hash'")
    current_entry_df = queryToDataFrame(query)
    @assert size(current_entry_df, 1) <= 1 "The database should have unique 'commit_hash' entries."
    is_hash_in_db = !isempty(current_entry_df)
    no_entries_missing = is_hash_in_db && all(.!ismissing.([x[1] for x in eachcol(current_entry_df)]))
    if no_entries_missing
        #! if the commit hash is already in the database, and it has a tag, then we are done
        return current_entry_df.physicell_version_id[1]
    end
    entry_dict = Dict{String,String}()

    #! then, compare that hash with remote hashes to identify the tag, repo owner, and date
    hash_to_tag_dict = commitHashToTagDict(physicellDir())
    if !repo_is_dirty && haskey(hash_to_tag_dict, commit_hash)
        entry_dict["tag"] = hash_to_tag_dict[commit_hash]
    else
        entry_dict["tag"] = "NULL"
    end

    entry_dict["repo_owner"] = repo_is_dirty ? "NULL" : repoOwner(commit_hash, entry_dict["tag"])
    entry_dict["date"] = repo_is_dirty ? "NULL" : readchomp(`git -C $(physicellDir()) show -s --format=%ci $commit_hash`)

    db_entry_dict = [k => v=="NULL" ? v : "'$v'" for (k,v) in entry_dict] |> Dict #! surround non-NULL values with single quotes, so NULL really go in as NULL
    if is_hash_in_db
        for (name, col) in pairs(eachcol(current_entry_df))
            if !ismissing(col[1])
                continue
            end
            name_str = string(name)
            DBInterface.execute(centralDB(), "UPDATE physicell_versions SET $(name_str) = $(db_entry_dict[name_str]) WHERE commit_hash = '$commit_hash';")
        end
        query = constructSelectQuery("physicell_versions", "WHERE commit_hash = '$commit_hash'"; selection="physicell_version_id")
        df = queryToDataFrame(query; is_row=true)
    else
        df = DBInterface.execute(centralDB(), "INSERT INTO physicell_versions (commit_hash, tag, repo_owner, date) VALUES ('$commit_hash', $(db_entry_dict["tag"]), $(db_entry_dict["repo_owner"]), $(db_entry_dict["date"])) RETURNING physicell_version_id;") |> DataFrame
    end
    return df.physicell_version_id[1]
end

"""
    physicellIsGit()

Check if the PhysiCell directory is a git repository.
"""
function physicellIsGit()
    is_git = isdir(joinpath(physicellDir(), ".git"))
    if !is_git #! possible it is a submodule
        path_to_file = joinpath(physicellDir(), ".git")
        if isfile(path_to_file)
            lines = readlines(path_to_file)
            if length(lines) > 0
                line_1 = lines[1]
                is_git = startswith(line_1, "gitdir: ") &&
                         contains(line_1, "modules") &&
                         endswith(line_1, "PhysiCell")
            end
        end
    end
    return is_git
end

"""
    gitDirectoryIsClean(dir::String)

Check if the git directory is clean (i.e., no uncommitted changes).
"""
function gitDirectoryIsClean(dir::String)
    cmd = `git -C $dir status --porcelain` #! -C flag is for changing directory, --porcelain flag is for machine-readable output (much easier to tell if clean this way)
    output = read(cmd, String)
    is_clean = length(output) == 0
    if is_clean
        return true
    end
    folders_to_ignore = ["beta", "config", "documentation-deprecated", "examples",
        "licenses", "matlab", "output", "povray", "protocols", "sample_projects",
        "sample_projects_intracellular", "sample_projects_physipkpd", "tests", "unit_tests",
        "user_projects"]
    files_to_ignore = ["ALL_CITATIONS.txt"]
    lines = split(output, "\n")
    filter!(x -> x != "", lines)
    for folder in folders_to_ignore
        filter!(x -> !contains(x, " $folder/"), lines)
    end
    for file in files_to_ignore
        filter!(x -> !contains(x, " $file"), lines)
    end
    is_clean = isempty(lines)
    if !is_clean
        println("PhysiCell repository is dirty. The following files are modified in the PhysiCell repository:")
        println(output)
        println("\nOf those, the following files are not in the folders to ignore for cleanliness:")
        println.(lines);
    end
    return is_clean
end

"""
    commitHashToTagDict(dir::String)

Get a dictionary mapping commit hashes to tags in the git repository at `dir`.
"""
function commitHashToTagDict(dir::String)
    hash_to_tag_dict = Dict{String, String}()
    has_tags = !isempty(readchomp(`git -C $dir tag`))
    if !has_tags
        return hash_to_tag_dict
    end
    tags_output = readchomp(`git -C $dir show-ref --tags`)
    tags = split(tags_output, "\n")
    for tag in tags
        parts = split(tag)
        if length(parts) == 2
            commit_hash, tag_ref = parts
            tag_name = split(tag_ref, '/')[end]
            hash_to_tag_dict[commit_hash] = tag_name
        else
            println("Error: tag is not in the expected format (<commit_hash> <tag_ref>):\n\t$tag")
        end
    end
    return hash_to_tag_dict
end

"""
    repoOwner(commit_hash::String, tag::String)

Get the owner of the repository for a given commit hash and tag.
"""
function repoOwner(commit_hash, tag::String)
    if tag == "NULL"
        return "NULL"
    end
    remotes = gitRemotes(physicellDir())
    for remote in remotes
        remote_hash_tags = readchomp(`git -C $(physicellDir()) ls-remote --tags $remote`)
        remote_hash_tags = split(remote_hash_tags, "\n")
        for remote_hash_tag in remote_hash_tags
            remote_commit_hash, remote_tag_name = split(remote_hash_tag, "\t")
            if remote_commit_hash != commit_hash
                continue
            end
            remote_tag_name = split(remote_tag_name, "/")[end]
            if remote_tag_name == tag
                remote_url = readchomp(`git -C $(physicellDir()) remote get-url $remote`)
                repo_owner = split(remote_url, "/")[end-1]
                return repo_owner
            end
        end
    end
    return "NULL"
end

"""
    gitRemotes(dir::String)

Get the remotes for the git repository at `dir`.
"""
function gitRemotes(dir::String)
    remotes_output = readchomp(`git -C $dir remote`)
    remotes = split(remotes_output, "\n")
    return remotes
end

"""
    physicellVersion()
    physiCellVersion(physicell_version_id::Int)
    physiCellVersion(simulation::Simulation)

Get the PhysiCell version from the database or, if not in the database, from the VERSION.txt file.
"""
function physicellVersion(physicell_version_id::Int)
    query = constructSelectQuery("physicell_versions", "WHERE physicell_version_id = $(physicell_version_id)")
    df = queryToDataFrame(query; is_row=true)
    if !ismissing(df.tag[1])
        return df.tag[1]
    end
    #! untagged commit, so use the VERSION.txt file
    path_to_version_file = joinpath(physicellDir(), "VERSION.txt")
    @assert isfile(path_to_version_file) "PhysiCell version undefined. Not at a tagged commit AND file not found at $path_to_version_file"
    lines = readlines(path_to_version_file)
    return lines[1]
end

physicellVersion() = physicellVersion(pcmm_globals.current_physicell_version_id)

function physicellVersion(simulation::Simulation)
    query = constructSelectQuery("simulations", "WHERE simulation_id = $(simulation.id)"; selection="physicell_version_id")
    df = queryToDataFrame(query; is_row=true)
    return physicellVersion(df.physicell_version_id[1])
end

"""
    physicellInfo()

Return a string representing the PhysiCell version information to display on initializing the model manager.
"""
function physicellInfo()
    query = constructSelectQuery("physicell_versions", "WHERE physicell_version_id = $(pcmm_globals.current_physicell_version_id)")
    df = queryToDataFrame(query; is_row=true)
    str_begin = ismissing(df.repo_owner[1]) ? "" : "($(df.repo_owner[1])) "
    str_middle = ismissing(df.tag[1]) ? df.commit_hash[1] : df.tag[1]
    str_end = ismissing(df.date[1]) ? "" : " COMMITTED ON $(df.date[1])"
    return "$str_begin$str_middle$str_end"
end

"""
    physicellCommitHash()

Get the commit hash for the current PhysiCell version.
"""
function physiCellCommitHash()
    query = constructSelectQuery("physicell_versions", "WHERE physicell_version_id = $(pcmm_globals.current_physicell_version_id)"; selection="commit_hash")
    df = queryToDataFrame(query; is_row=true)
    return df.commit_hash[1]
end

"""
    currentPhysiCellVersionID()

Get the current PhysiCell version ID.
"""
currentPhysiCellVersionID() = pcmm_globals.current_physicell_version_id