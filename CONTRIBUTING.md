# Contributing

Process and conventions for changes to PhysiCellModelManager.jl. Where to make a change, and how
the code fits together, is on the [Architecture](https://drbergman-lab.github.io/PhysiCellModelManager.jl/dev/dev/architecture/)
page of the docs (pick the **Dev** tier in the sidebar). Exact commands for tests and the docs build
are in [AGENTS.md](AGENTS.md).

## Branching

- Never commit to `main` directly. Branch from `main` unless a task names another base.
- One pull request per feature. The docs site is built as a preview for every pull request, so a
  reviewer can read the finished pages rather than the diff.

## Style

- Functions are `camelCase`, types `PascalCase`, internal helpers start with `_`. Source files are
  `snake_case.jl`; test files are `PascalCaseTests.jl` with a matching top-level `@testset`.
- Use `#!` for comments that are informative. A plain `# ` then marks a line of code commented out
  in development, so the regular expression `^(\s+)?# .+\n` finds leftovers before a commit.
- Every exported or `public` name has a docstring with a signature, a one-line summary, and a
  runnable example. A docstring may `[`x`](@ref)` only a public binding; an internal is named in
  plain backticks.

## Documentation

- Every public name has a home in the manual: a user-facing page under `docs/src/man/` or a
  Dev-tier page under `docs/src/dev/`. `test/test-scripts/ManualCoverageTests.jl` fails when one
  does not.
- Prose that only a developer needs goes in a `!!! tierdev` block next to the code it concerns;
  a dated decision goes in a `!!! tierjournal "YYYY-MM-DD — Title"` block. `docs/journal.jl`
  collects the latter into `docs/src/dev/journal.md` at build time; commit the regenerated file.
- Never put a code block inside a tier block.
- A `public` but unexported name is linked as `[`x`](@ref ModelManager.x)` (or
  `PhysiCellModelManager.x`); a bare `[`x`](@ref)` on a page only resolves exported names.

## Tests

- Test artifacts are cleaned up at the **start** of `test/runtests.jl`, so they remain for
  inspection after a run. A test that creates a new output path adds it to both `test/.gitignore`
  and the cleanup list in `runtests.jl`.
- Some suites need a PhysiCell binary and fail locally without one. They pass on the GitHub
  runners, where it is downloaded.
