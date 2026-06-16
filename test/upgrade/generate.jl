# Upgrade-path CI — generation stage.
#
# Installs a *pinned older release* of the package in an isolated environment and
# produces a real project (`data/` + `PhysiCell/`) stamped at that older version,
# with at least one sampling's worth of simulations on disk. A later stage opens
# this same project with the dev checkout and runs `src/up.jl` to upgrade it.
#
# Driven by env var `PCMM_UPGRADE_SOURCE_VERSION` (e.g. "0.2.2"). The package name
# is derived from the version: releases < 0.1.0 were published as `pcvct`, and
# >= 0.1.0 as `PhysiCellModelManager`.
#
# This script manages its own temporary project environment, so it is launched
# with a plain `julia generate.jl` (no `--project`).

import Pkg

const SOURCE_VERSION = VersionNumber(get(ENV, "PCMM_UPGRADE_SOURCE_VERSION", "0.2.2"))
const PKG_NAME = SOURCE_VERSION < v"0.1.0" ? "pcvct" : "PhysiCellModelManager"

const UPGRADE_DIR = @__DIR__
const TMP_DIR = joinpath(UPGRADE_DIR, "tmp")
const GEN_ENV_DIR = joinpath(TMP_DIR, "gen-env")
const PROJECT_DIR = joinpath(TMP_DIR, "project")

# Start from a clean slate so reruns are deterministic.
isdir(TMP_DIR) && rm(TMP_DIR; recursive=true, force=true)
mkpath(GEN_ENV_DIR)
mkpath(TMP_DIR)

println("== Upgrade CI generation ==")
println("  source version: $(SOURCE_VERSION)")
println("  package name:   $(PKG_NAME)")
println("  project dir:    $(PROJECT_DIR)")

# Install the pinned old release into its own environment.
Pkg.activate(GEN_ENV_DIR)
Pkg.add(Pkg.PackageSpec(name=PKG_NAME, version=SOURCE_VERSION))
Pkg.instantiate()

@eval using $(Symbol(PKG_NAME))

# Create the project (clones PhysiCell, sets up the template inputs, initializes
# the database at the source version) and run a small sampling so that the
# simulations / monads / samplings tables all have rows for the upgrade to act on.
createProject(PROJECT_DIR; template_as_default=true)

inputs = InputFolders("0_template", "0_template"; rulesets_collection="0_template")

# Keep the simulations tiny and deterministic: short max_time and coarse output
# intervals so PhysiCell finishes quickly in CI. The two-valued max_time yields
# two monads; n_replicates=2 yields four simulations under one sampling.
const N_REPLICATES = 2
const MAX_TIMES = [12.0, 18.0]
const N_EXPECTED_SIMS = length(MAX_TIMES) * N_REPLICATES

discrete_variations = DiscreteVariation[]
push!(discrete_variations, DiscreteVariation(configPath("max_time"), MAX_TIMES))
push!(discrete_variations, DiscreteVariation(configPath("full_data"), 6.0))
push!(discrete_variations, DiscreteVariation(configPath("svg_save"), 6.0))

sampling = createTrial(inputs, discrete_variations; n_replicates=N_REPLICATES)
out = run(sampling)
println("  ran sampling: scheduled=$(out.n_scheduled) success=$(out.n_success)")

# Require the full, exact set of simulations so a partial failure here surfaces
# as a clear generation error rather than a confusing row-count mismatch in the
# later verify stage.
@assert out.n_scheduled == N_EXPECTED_SIMS "Expected $(N_EXPECTED_SIMS) simulations scheduled, got $(out.n_scheduled)."
@assert out.n_success == N_EXPECTED_SIMS "Expected $(N_EXPECTED_SIMS) simulations to succeed, got $(out.n_success)."

println("== Generation complete ==")
