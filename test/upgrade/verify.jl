# Upgrade-path CI — upgrade + verify stage.
#
# Opens the project produced by `generate.jl` with the *dev checkout* and
# `auto_upgrade=true`, which runs every `src/up.jl` milestone between the source
# version and dev HEAD. Then asserts data integrity directly against the SQLite
# database (independent of either package's API).
#
# Launched with `julia --project=. test/upgrade/verify.jl` so that the dev
# checkout is what performs the upgrade. NOTE: `Test` is only a test-target
# dependency, so this script uses its own assertion helper rather than `using
# Test` (which is unavailable under `--project=.`).

using PhysiCellModelManager
using SQLite, DataFrames
import Pkg

const SOURCE_VERSION = VersionNumber(get(ENV, "PCMM_UPGRADE_SOURCE_VERSION", "0.2.2"))
const DEV_VERSION = Pkg.project().version

const UPGRADE_DIR = @__DIR__
const PROJECT_DIR = joinpath(UPGRADE_DIR, "tmp", "project")
const DATA_DIR = joinpath(PROJECT_DIR, "data")
const PHYSICELL_DIR = joinpath(PROJECT_DIR, "PhysiCell")

# --- tiny assertion harness (nonzero exit on any failure) ---------------------
const FAILURES = String[]
function check(cond::Bool, msg::AbstractString)
    if cond
        println("  ✓ $(msg)")
    else
        println("  ✗ $(msg)")
        push!(FAILURES, msg)
    end
    return cond
end

# Database file and version-table names changed across milestones:
#   vct.db  -> pcmm.db            at v0.1.3
#   pcvct_version -> pcmm_version at v0.0.30
dbFile() = isfile(joinpath(DATA_DIR, "pcmm.db")) ? joinpath(DATA_DIR, "pcmm.db") :
                                                   joinpath(DATA_DIR, "vct.db")

tableExists(db, t) = !isempty(DBInterface.execute(db,
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='$(t)';") |> DataFrame)

rowCount(db, t) = tableExists(db, t) ?
    (DBInterface.execute(db, "SELECT COUNT(*) AS n FROM $(t);") |> DataFrame).n[1] : 0

function versionTable(db)
    for t in ("pcmm_version", "pcvct_version")
        tableExists(db, t) && return t
    end
    return nothing
end

dbVersion(db) = (t = versionTable(db); isnothing(t) ? nothing :
    VersionNumber((DBInterface.execute(db, "SELECT version FROM $(t);") |> DataFrame).version[1]))

# --- snapshot the project state BEFORE the upgrade ----------------------------
@assert isdir(PROJECT_DIR) "Generated project not found at $(PROJECT_DIR). Did generate.jl run?"

pre_db = SQLite.DB(dbFile())
pre_counts = Dict(t => rowCount(pre_db, t) for t in ("simulations", "monads", "samplings"))
pre_version = dbVersion(pre_db)
sim_ids = (DBInterface.execute(pre_db, "SELECT simulation_id FROM simulations;") |> DataFrame).simulation_id
close(pre_db)

println("== Pre-upgrade snapshot ==")
println("  db version: $(pre_version)")
println("  counts:     $(pre_counts)")

# --- run the upgrade with the dev checkout ------------------------------------
println("== Upgrading $(pre_version) -> $(DEV_VERSION) with dev checkout ==")
upgrade_ok = initializeModelManager(PHYSICELL_DIR, DATA_DIR; auto_upgrade=true)

# --- assertions ---------------------------------------------------------------
println("== Assertions ==")
post_db = SQLite.DB(dbFile())

check(upgrade_ok, "initializeModelManager with auto_upgrade succeeded")
check(pre_version == SOURCE_VERSION, "generation stamped the source version ($(SOURCE_VERSION))")
check(dbVersion(post_db) == DEV_VERSION, "version bumped to dev HEAD ($(DEV_VERSION))")

for t in ("simulations", "monads", "samplings")
    check(rowCount(post_db, t) == pre_counts[t],
        "no data loss in $(t) ($(pre_counts[t]) rows preserved)")
end

for id in sim_ids
    check(isdir(joinpath(DATA_DIR, "outputs", "simulations", string(id))),
        "output folder for simulation $(id) intact")
end

# Milestone-specific check: crossing v0.3.0 must leave the calibrations table.
# (Weak on its own — initializeDatabase also creates it — but harmless.)
if pre_version < v"0.3.0" <= DEV_VERSION
    check(tableExists(post_db, "calibrations"), "calibrations table present (crossed v0.3.0)")
end

# Milestone-specific check: crossing v0.2.0 rewrites every varied-location
# variations table to carry a binary `par_key` column. This genuinely proves
# `upgradeToV0_2_0` ran (it is not produced by normal init).
function columnExists(db, table, col)
    info = DBInterface.execute(db, "PRAGMA table_info($(table));") |> DataFrame
    return col in info.name
end

if pre_version < v"0.2.0" <= DEV_VERSION
    variation_dbs = String[]
    for (root, _, files) in walkdir(joinpath(DATA_DIR, "inputs"))
        for f in files
            endswith(f, "variations.db") && push!(variation_dbs, joinpath(root, f))
        end
    end
    check(!isempty(variation_dbs), "found at least one variations database to check par_key")
    for path in variation_dbs
        vdb = SQLite.DB(path)
        tables = (DBInterface.execute(vdb,
            "SELECT name FROM sqlite_master WHERE type='table';") |> DataFrame).name
        for t in filter(t -> endswith(t, "_variations"), tables)
            check(columnExists(vdb, t, "par_key"),
                "par_key column present in $(t) of $(relpath(path, DATA_DIR)) (crossed v0.2.0)")
        end
        close(vdb)
    end
end

close(post_db)

if isempty(FAILURES)
    println("\n== All upgrade checks passed ($(SOURCE_VERSION) -> $(DEV_VERSION)) ==")
else
    println("\n== $(length(FAILURES)) upgrade check(s) FAILED ==")
    foreach(m -> println("  - $(m)"), FAILURES)
    exit(1)
end
