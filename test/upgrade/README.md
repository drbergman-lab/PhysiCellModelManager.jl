# Upgrade-path CI

Tests `src/up.jl` end-to-end by replaying real version history. This cannot run
inside `Pkg.test()` because it needs two different package versions present at
once, so it lives in its own workflow: [`.github/workflows/UpgradeCI.yml`](../../.github/workflows/UpgradeCI.yml).

## How it works

Two stages, run sequentially on the same runner:

1. **Generate** (`generate.jl`, plain `julia`): installs a pinned *older release*
   in an isolated environment (`tmp/gen-env`), creates a project, and runs a
   small sampling — producing `tmp/project/{data,PhysiCell}` with a database
   stamped at the source version.
2. **Upgrade + verify** (`verify.jl`, `julia --project=.`): opens that same
   project with the **dev checkout** and `auto_upgrade=true`. This runs every
   `src/up.jl` milestone between the source version and dev `HEAD`. Assertions
   read the SQLite database directly (API-agnostic): row counts are preserved,
   the version table is stamped to `HEAD`, output folders survive, and any
   milestone-specific schema delta in range is present.

The source release is the single knob `PCMM_UPGRADE_SOURCE_VERSION` (and the
`source-version` matrix entry in the workflow). Because the **dev checkout**
performs the upgrade, this genuinely exercises the repo's `src/up.jl`.

## Why "go backwards"

We generate at the release just below the latest milestone and upgrade with dev
`HEAD`, rather than upgrading old data with an intermediate *released* version
(which would test released code, not the repo). The source version walks back
over time to cover older migrations:

| Source | Milestones crossed to HEAD | Notes |
|--------|----------------------------|-------|
| `0.2.2` | `0.3.0` | Isolated single-hop; mostly a data-preservation smoke test (`upgradeToV0_3_0`'s `calibrations` table is also created by normal init, so it is not distinguishing). |
| `0.1.7` | `0.2.0`, `0.3.0` | **Primary target — a version a real user is currently on.** Exercises the `upgradeToV0_2_0` par_key rewrite (a real data transform; verified via the `par_key` column). |
| `pcvct@0.0.x` (future) | many | Package was named `pcvct` (< `0.1.0`); the harness derives the name from the version. Floor is `pcvct@0.0.3` (`0.0.1`/`0.0.2` were never released). The `pcvct`-era project-creation API may need an older generation script. |

## Notes

- `tmp/` is git-ignored; it is recreated on each generation run.
- Running locally requires a C++ compiler (`PHYSICELL_CPP`) and network access to
  download PhysiCell; set `PCMM_PUBLIC_REPO_AUTH` to avoid GitHub rate limits.
