# AGENTS.md

Operational notes for anyone — person or agent — working in this repository. Process and style are
in [CONTRIBUTING.md](CONTRIBUTING.md); the design workflow, PRD and session journal that Claude Code
sessions follow are in [CLAUDE.md](CLAUDE.md). Where a change goes is answered by the Architecture
page of the docs (`docs/src/dev/architecture.md`; choose the **Dev** tier on the site).

## What this is

PhysiCellModelManager.jl (PCMM) is the PhysiCell backend for ModelManager.jl. ModelManager owns the
generic parts — the Simulation/Monad/Sampling/Trial hierarchy, the SQLite databases, the runner,
parameter variations, tags, sensitivity analysis and ABC-SMC calibration — and PCMM re-exports it
wholesale (`@reexport using ModelManager` in `src/PhysiCellModelManager.jl`). PCMM adds what is
PhysiCell-specific: compiling PhysiCell, XML path helpers (`configPath`, `rulePath`), initial-condition
files, output loading (`src/loader.jl`), and population/substrate/graph analysis (`src/analysis/`).

Entry points: `src/PhysiCellModelManager.jl` (module, include order), `src/physicell_simulator.jl`
and `src/simulator_interface.jl` (the hooks PCMM implements for ModelManager), `src/database.jl` +
`src/up.jl` (schema and migrations), `docs/make.jl` (site), `test/runtests.jl` (suite).

## Commands

Always run Julia with the project environment. From the repo root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'          # once per checkout
julia --project=. -e 'using Pkg; Pkg.test()'                  # full suite
```

One suite, against the `test/data` project an earlier full run left behind (`test/runtests.jl`
has no argument parsing; most suites depend on the project `CreateProjectTests.jl` creates):

```bash
julia --project=. -e 'cd("test"); using PhysiCellModelManager, Test; include("test-scripts/PrintHelpers.jl"); include("test-scripts/DatabaseTests.jl")'
```

Docs (the docs environment must `develop` this checkout first):

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Doctests only:

```bash
julia --project=docs -e 'using Documenter, PhysiCellModelManager, ModelManager; DocMeta.setdocmeta!(PhysiCellModelManager, :DocTestSetup, :(using PhysiCellModelManager); recursive=true); doctest(PhysiCellModelManager)'
```

`docs/make.jl` runs `docs/journal.jl` first, which regenerates `docs/src/dev/journal.md` from every
`!!! tierjournal "YYYY-MM-DD — Title"` block under `docs/src/`. Commit the regenerated file.

## Invariants

- Never modify `main` directly. Never read or write inside `.git/`; use git commands only.
- A database schema change updates both `src/database.jl` and `src/up.jl` (a versioned migration).
- One backend per Julia process: PCMM registers `PhysiCellSimulator` with ModelManager's globals
  and must not run against a foreign simulator.
- Executables live in `pcmm_build/` inside the custom-code folder, named for the PhysiCell version
  they were built against; the file's existence is the only record of a finished build.
- A docstring may `[`x`](@ref)` only a public binding of PCMM or ModelManager. Internals are named
  in plain backticks. `test/test-scripts/DocstringRefTests.jl` enforces this without a docs build.
- Never add a Documenter `@docs` block for an internal; `docs/src/lib/*.md` renders public API only.
- On a manual page, a `public` but unexported name must be `@ref`ed with its module:
  `[`simulatorDir`](@ref ModelManager.simulatorDir)`. A bare `[`x`](@ref)` resolves in `Main`, where
  only exported names exist, and fails the build.
- Every public name appears on a page under `docs/src/man/` or `docs/src/dev/`;
  `test/test-scripts/ManualCoverageTests.jl` enforces it.
- Never put a code block inside a `!!! tiergloss` / `tierwhy` / `tierdev` / `tierjournal` block.
- Test artifacts are cleaned at the **start** of `test/runtests.jl`, not the end. A test that
  writes a new path adds it to `test/.gitignore` and to that cleanup list.
- Do not edit `Manifest.toml` or add dependencies without approval. Heavy optional dependencies go
  in `ext/` as package extensions.

## Conventions

- Functions `camelCase` (`createProject`, `runStudio`); types `PascalCase` (`PruneOptions`);
  internal helpers start with `_`; module globals `snake_case`; environment variables
  `SCREAMING_SNAKE_CASE` (`PCMM_PYTHON_PATH`).
- Source files `snake_case.jl`; tests `PascalCaseTests.jl` with a matching top-level `@testset`.
- Public API is exported from the `src/*.jl` file that defines it; `@compat public` marks a name
  public without exporting it.
- Comments that are meant to stay are written `#!`. A plain `# ` marks commented-out code.
- Docs pages start with `# [Title](@id slug_man)` (or `slug_dev`, `slug_lib`); a backticked
  heading always gets an explicit `@id`.

## Sharp edges

- `using PhysiCellModelManager` auto-initialises a project found in the working directory, except
  while Julia is writing a precompilation cache or system image. That is deliberate.
- Some test suites need a downloaded PhysiCell binary and fail locally without it; they pass on
  the GitHub runners.
- The compile flag defaults to `-march=x86-64` on SLURM clusters and `-march=native` elsewhere;
  non-SLURM clusters are a known gap (see `progress.md`, 2026-08-05).
- The tier selector is client-side CSS. The Markdown and the built HTML contain every tier, so
  reading the source shows the deepest one.
