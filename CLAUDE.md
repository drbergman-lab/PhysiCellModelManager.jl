# CLAUDE.md — PCMM (PhysiCell Model Manager)

## About the User
Assistant professor working on computational modeling of cancer-immune interactions, mechanistic modeling, and agent-based modeling frameworks.

## Key Documents — Read These First

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Project overview + **Implementation Status** (what is built, what remains) |
| [PRD.md](PRD.md) | Behavioral specification for every feature — acceptance criteria and edge cases |
| [progress.md](progress.md) | Session journal: decisions made, approaches rejected, open questions |

Start any feature session by reading the relevant PRD entry and the Implementation Status section of `README.md`.

## Project Overview
PCMM is a Julia package that manages model configuration, versioning, and simulation organization for PhysiCell (a C++ agent-based modeling framework). It provides:
- Model specification & validation
- Version control for simulation configs
- Interface code between Julia and PhysiCell
- Database schema management

**Key directories:**
- `src/` — Core logic and adapters
- `ext/` — Julia 1.9+ package extensions (e.g., `PCMMCalibrationExt.jl`)
- `test/` — Test suite
- `docs/` — Documentation

## Scope
All work must remain strictly inside this repository folder.
Do **not** access or edit files outside this repo.
Treat this directory as the entire project universe.

## Branching Rules
- Never modify `main` directly.
- Default base branch is `main` unless the user specifies another base.
- For any task, create a feature branch:
```
git checkout -b feature/<desc> <base-branch>
```

## Local Julia Environment
Always use the project environment:
- `julia --project=.`
Preferred test command:
- `julia --project=. -e 'using Pkg; Pkg.test()'`

## Allowed / Cautioned Commands
Allowed:
- `ls`, `cat`, `rg`/`grep`, build commands, test commands
- `git` commands committing to the feature branch you are developing on

Cautioned:
- `rm`
  - you may create your own folders named `claude-temp` or use existing `temp/`
  - clean these up after the work is done
- `mv`
  - can use within the repo so the files remain tracked
- `sudo`, global package installs
  - ask for user input before running these
- Any command writing outside this repo's root

## Naming Conventions

- **Functions:** `camelCase` (e.g., `createProject`, `finalPopulationCount`, `runABC`)
- **Types / Structs:** `PascalCase` (e.g., `CalibrationProblem`, `InputFolders`, `DiscreteVariation`)
- **Constants / globals:** `snake_case` for internal module globals (e.g., `pcmm_globals`); `SCREAMING_SNAKE_CASE` for environment variables (e.g., `PCMM_PYTHON_PATH`)
- **Files:** `snake_case.jl` for source files; `PascalCaseTests.jl` for test files
- **Test sets:** match the test file name (e.g., `@testset "CalibrationTests.jl"`)
- **XML path helpers:** `configPath`, `behaviorPath` — return strings used as variation keys
- **Exported vs internal:** public API is exported from the relevant `src/*.jl` file; internal helpers are prefixed with `_` (e.g., `_importPyABC`, `_buildPrior`)
- **Extension internals:** accessed in tests via `Base.get_extension(PhysiCellModelManager, :PCMMCalibrationExt)`, not via `PhysiCellModelManager._name`

## Required Workflow for Any Change
1. Generate a **design brief** in the assistant response **before any code changes**.
2. Wait for human approval.
   1. Update the PRD.md to include new feature or changes.
   2. Open a new entry in the progress.md and start logging the design process, decisions, and open questions there.
3. Create a feature branch off the chosen base branch.
4. Implement in the feature branch only.
5. The user will inspect diffs manually before merging.
6. Update [README.md](README.md) Implementation Status when a feature is complete.
7. Trim the PRD.md and progress.md to reflect the final implementation (remove rejected approaches, trim design notes, etc.) before merging.

**Design brief template:**
```
# Design Brief: [Feature/Refactor Name]

## Motivation
[1-2 sentences: Why is this change needed? What problem does it solve?]

## Scope
- **Files affected:** `src/module1.jl`, `src/module2.jl`, `tests/test_module1.jl`
- **New files:** `src/adapters/physicell.jl` (if applicable)
- **Breaking changes:** Yes/No — [describe if yes]

## Proposed Architecture
[2-3 paragraphs or a simple diagram showing the change]
- Current: [brief description]
- Proposed: [brief description]
- Key decisions: [why this approach over alternatives]

## Testing Strategy
- Unit tests for: [list what gets tested]
- Integration tests: [if applicable]
- Example: [small deterministic example showing the feature works]

## Estimated Effort
- Lines of code: ~[estimate]
- Risk level: Low / Medium / High
- Dependencies: [any external changes needed first?]
```

## Definition of Done

A feature is complete when **all** of the following are true:

1. **Tests pass:** `julia --project=. -e 'using Pkg; Pkg.test()'` runs green for the new code. Tests cover:
   - The happy path
   - Relevant edge cases listed in the PRD entry
   - Any error conditions that should throw (use `@test_throws`)
2. **Docstrings written:** Every exported function has a docstring with a description, argument list, return value, and at least one usage example.
3. **Docs page updated:** If the feature has a user-facing page in `docs/src/man/`, it reflects the new behavior. New features need a docs page.
4. **README updated:** The Implementation Status section in [README.md](README.md) marks the feature as complete (move from "In Progress" / "Remaining" to "Completed").
5. **PRD reflects reality:** If implementation deviated from the PRD, update the PRD entry to match what was actually built.
6. **No regressions:** The full test suite has no new failures compared to the base branch.

## PCMM‑Specific Guidance
PCMM manages **model configuration, versioning, simulation organization, and interface code** for PhysiCell.
Therefore:
- Propose architecture changes before implementing them.
- Refactors must preserve existing model specification semantics.
- When reorganizing code, update all associated config, schema, or builder functions.
- If breaking changes are made to the database structure, they must be reflected in `src/up.jl`.

## Documentation & Testing Requirements
- Every new function needs docstrings.
- Every feature needs tests in `test/`.
- Include small, deterministic examples for model configuration tasks.
- Test artifacts are cleaned up at the **start** of `runtests.jl` (not the end), so they remain for inspection after a run. If a test creates new output paths, add them to both `test/.gitignore` and the cleanup list in `test/runtests.jl`.

## Integration Essentials
- Module entrypoint: `src/PhysiCellModelManager.jl` (update includes when adding/moving files).
- Public API likely lives in `src/user_api.jl`; prefer using/exposing APIs there.
- Database changes must update both `src/database.jl` and `src/up.jl`.
- Optional heavy dependencies (Python interop, etc.) belong in `ext/` as package extensions, not in `src/`. Use `[weakdeps]` + `[extensions]` in `Project.toml`.

## Julia Environment Rules
- Always run Julia with `--project=.`. (the path to the root `PhysiCellModelManager` folder)
- Do not edit `Manifest.toml` or add dependencies without explicit approval.

## Tests
- Entry point is `test/runtests.jl`.
- Avoid altering test fixtures unless required by the change.

## To-dos
When setting you off on a task, check this list and assess if any of these should be done first.
- Verify CondaPkg auto-installs `pyabc` correctly on a fresh checkout (the `CondaPkg.toml` is present; behavior on a clean machine is untested)
- Fix pre-existing test sequencing issue: `DeletionTests` de-initializes the project, causing `DepsTests` (`assertInitialized`) to fail
