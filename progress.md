# progress.md — PCMM Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

---

## 2026-08-19 — Name the executable for the PhysiCell version; drop `physicell_commit_hash.txt`; check that version at every compile

### The bug
`loadCustomCode` decided whether to recompile from two records that could disagree with each
other. `physicell_commit_hash.txt` held the PhysiCell version, and `writePhysiCellCommitHash`
**wrote it before `make` ran**; the executable was always named `project`, so a compile error
left the old binary in place next to a file now claiming the new version. The next run read a
matching hash, found `project`, concluded nothing had changed, and silently ran a binary built
from different PhysiCell source.

### The fix — one record instead of two
The executable is named `project_<physicell-version>`, so its existence *is* the record that a
build for that version finished. `physicell_commit_hash.txt` is gone. There is nothing left to
fall out of step with: a failed compilation writes no executable, so the next run recompiles.

`unreproduciblePhysiCellVersion()` replaces the old function's dirty/download branches. Those
suffixes mean the source can change without the recorded version changing, so the name proves
nothing and the code recompiles every run — the previous behaviour, now stated as its own
predicate rather than a fall-through of the hash comparison.

### `macros.txt` had the same defect
Found while restructuring, and the same failure mode, so it is fixed in the same commit.
`addMacrosIfNeeded` appended to `macros.txt` *before* compiling. A macro change sets both
`recompile` and `clean` — the macros are part of every translation unit, so object files
compiled without them must be discarded. If that compilation failed, `macros.txt` already
listed the new macro, so the retry saw no macro change and skipped the `make clean` it needed.

Now `neededMacros(S)` computes the list in memory, `compilerFlags` compares it against the file
to decide `recompile`/`clean`, and `writeMacrosFile` runs only after `make` succeeds. Two bugs
fell out of the restructure rather than being hunted:
- `addMacrosIfNeeded` chained the checks with `||`, so PhysiECM being newly needed
  short-circuited the RoadRunner check entirely. A project needing both got one macro, failed
  to compile, and only picked up the second on the next attempt. The comment above the line
  ("julia's `|=` operator seems to evaluate the RHS even if the LHS is already true, but I don't
  trust that will always be the case") shows the `||` rewrite defeated its own intent.
- `addPhysiECMIfNeeded` called `addMacro(M, ...)` with an undefined `M` — an `UndefVarError`
  waiting on any project that enables `ecm_setup` in config without supplying an `ic_ecm` file.

### Decisions — the naming change
- **Old executables are kept, not pruned.** A custom code folder can accumulate one binary per
  PhysiCell version used there. That is deliberate: the name is now a cache key, so switching
  PhysiCell versions back and forth no longer forces a rebuild. `clearSimulatorArtifacts`
  (reached by `resetDatabase`) deletes all of them, which is the documented way to reclaim the
  space. Pruning on each successful compile was considered and rejected — it would delete a
  binary another session on a shared filesystem may be about to launch.
- **Legacy artifacts are cleaned up in place, not via an `up.jl` milestone.** `project` and
  `physicell_commit_hash.txt` are removed by `removeLegacyBuildArtifacts` after the first
  successful compile under the new naming. A milestone would drag the whole
  `continueMilestoneUpgrade` prompt in to delete two files, and the upgrade is self-healing
  anyway: no hash-named executable exists, so the first run recompiles regardless.
- **Executables live in a `pcmm_build/` subfolder, so clearing them needs no name match at all.**
  Two earlier rounds tried to make a prefix safe — first `project*`, then `project_` — and review
  rejected both: a glob that deletes can always swallow a file the user keeps for their own
  records, and `project_notes.md` is genuinely indistinguishable from `project_<hash>`. A folder
  PCMM owns ends the argument. `clearSimulatorArtifacts` removes that directory outright and
  matches every remaining name exactly (`isCompilationArtifact`), so `projectile.cpp` and
  `project_notes.md` are both safe. `project`, `project.exe`, and `physicell_commit_hash.txt` stay
  in the exact list, matched on either platform, so a data folder built elsewhere is still cleaned.
  `createDefaultGitIgnore` ignores `pcmm_build/` rather than `project*`.
- **A build that does not finish takes the executable it was replacing with it** (`abandonBuild`).
  Raised in review: is it possible to reach the failure paths with an executable for the current
  version still present? Yes — the recompile may have been triggered by changed macros, a
  `force_recompile`, or a dirty PhysiCell working tree, none of which imply the file is absent.
  In the `force_recompile` case the hole was live: the next run without the flag would find that
  executable, unchanged macros, and a clean repository, and reuse a binary the user had explicitly
  asked to replace. Deleting it on failure makes "an executable exists" mean "a build for this
  version finished" in the failure paths too.
  Rejected: deleting it up front, before `make`. That would also cover an abnormal termination
  mid-compile, which `abandonBuild` does not, but it removes the binary for the whole duration of
  every rebuild, where the `mv` at the end is an atomic swap. On a shared filesystem a concurrent
  session would fail to launch simulations for minutes rather than for an instant. Losing the
  binary to a `kill -9` is the residual, and it fails loudly on the next launch rather than
  silently returning wrong results.
- **The version string is sanitized before it becomes a file name.** It is either a git hash or
  the first line of `VERSION.txt` from whatever PhysiCell the user downloaded; the latter is not
  guaranteed tame. `sanitizedForFilename` replaces anything outside `[A-Za-z0-9._-]` with `_`.
- **`make` is invoked with `PROGRAM_NAME` set to the final name.** It used to build
  `project_ccid_<id>` and rename on the way out; the temp directory already carries a
  `randstring(10)` suffix, so the intermediate name bought nothing.
- **`make` exiting 0 without producing the executable is now a failure return**, not an
  unhandled `mv` error.

### Testing the naming change
`test/test-scripts/CompilationTests.jl`, run right after `RunnerTests.jl` so a real build
exists to inspect. It asserts the naming and sanitizing, the `isCompilationArtifact`
classification, that `removeLegacyBuildArtifacts` deletes the old pair and leaves `main.cpp`
alone, and that a real build leaves a hash-named executable, a `macros.txt`, and no legacy
files. The regression itself is driven end to end: swap in a `Makefile` whose only recipe is
`@exit 1`, plant the exact state the old code was fooled by (a stale `project` plus a
`physicell_commit_hash.txt` naming the current version), and check that `loadCustomCode` returns
`false` and `executableExists` stays `false`. The real executable is moved aside and restored
rather than deleted, so the failure path costs no rebuild.

### What this does not fix
The name carries no OS, architecture, or compiler-flag component, so copying a `data/` folder
to a different platform still reuses an unrunnable binary. Called out in
`docs/src/man/known_limitations.md` with the `force_recompile=true` workaround. This was the
known limitation going in, not a regression.

### Bearing on the deferred `-march` work (see 2026-08-05)
That entry's analysis stands, but two of its statements are now out of date: the executable is
no longer "a single `project`" that gets overwritten, and the cache key is no longer empty — it
is the PhysiCell version. It still contains no ISA or march component, which is the part that
matters there. The mechanism that entry called for now exists: making `native` safe is a matter
of adding a march/ISA component to `executableName`, not of inventing artifact keying.

### Second half: the PhysiCell version was only ever checked at initialization
Flagged separately by the user as "guard against upgrading to new PhysiCell version mid-session.
This might already be done?" It was not.

`simulator().current_version_id` is assigned in exactly one place — `src/up.jl`, during database
initialization — and never revisited. `physiCellCommitHash()` reads the database row for that
cached id, so it cannot see the working tree. Measured directly: edit `PhysiCell/Makefile`
mid-session and `gitDirectoryIsClean()` returns `false` while `physiCellCommitHash()` still
returns the clean hash, `unreproduciblePhysiCellVersion()` returns `false`, and
`loadCustomCode` returns `true` without compiling.

Reusing a stale binary is the mild half. The damaging half: any recompile forced for another
reason (macro change, `force_recompile=true`) builds the *new* source while naming the
executable and writing `physicell_version_id` for the *old* version. The database then asserts a
clean commit for a binary that is not that commit — precisely what the `-dirty` suffix exists to
prevent, defeated by checking only at startup.

`refreshPhysiCellVersion()` now runs as the first statement of `loadCustomCode`. Everything else
follows from the naming change above, which is why the two belong in one PR:
- HEAD moved → a different `commit_hash` row → a different `executableName()` → `executableExists`
  is false → recompile.
- Went dirty → the hash gains `-dirty` → `unreproduciblePhysiCellVersion()` → recompile.
- ModelManager records each simulation from `currentSimulatorVersionID()`, which reads the same
  field, and setup always precedes recording, so the recorded version is corrected too.

Under the old naming this would have needed its own comparison against the hash file. With the
hash in the executable name, re-resolving the version *is* the guard.

### Decisions — the guard
- **`loadCustomCode`, not per simulation.** It is the single funnel for compilation, runs once per
  sampling, and precedes recording. Refreshing per simulation would let one sampling straddle two
  PhysiCell versions. The cost is one `git status --porcelain` per sampling: measured 30 ms for
  `resolvePhysiCellVersionID()` on the steady-state path, 20 ms of it the `git status`.
- **Resolve quietly, report in one line.** `resolvePhysiCellVersionID` and `gitDirectoryIsClean`
  gained `verbose::Bool=true` kwargs; the refresh passes `verbose=false` and prints
  `PhysiCell version changed. Now using <info>.` only when the id actually moved. Without this, a
  user with a permanently dirty PhysiCell would get the multi-line dirty warning plus a
  modified-file listing once per sampling instead of once per session. The `-dirty` suffix in the
  one-line message plus `unreproduciblePhysiCellVersion`'s own notice carries the actionable part;
  the full listing still appears at initialization.
- **A failed compile after a version change is safe.** The refreshed id is in place but
  `setupSampling` returns false and the run aborts, so no simulation is recorded against it.
- **No opt-out.** Recording the wrong commit hash is corruption, not a preference, so the
  version-changed path is unconditional. See the `strict_check` note below for the dirty case.

### `strict_check` deleted — it was dead and always had been
`PhysiCellSimulator.strict_check` was documented on an **exported** type as "If `true`, require a
clean git directory to skip recompile", was set to `true` by the constructor, and was read nowhere.
`git log -S` shows it entered at the 2026-04-08 modularization as a rename of
`strict_physicell_check` from the old globals struct ("...requires a clean git folder (in
particular, not downloaded) to skip recompile"), which was itself never read either. Not a
refactor casualty — declared and never wired, under both names, while its docstring rendered on
the site as a promise the code did not keep.

The behaviour it described already exists unconditionally in `unreproduciblePhysiCellVersion()`,
covering both the dirty and the downloaded case, so the field was never missing behaviour — it was
a missing *off-switch*, for someone carrying a permanent local patch on PhysiCell who does not want
a full rebuild every run.

Deleted rather than wired up. Setting it to `false` would mean recording a clean commit hash for a
tree that is not that commit, in the package whose job is reproducible bookkeeping, and PCMM
already prints the better answer when it sees a dirty repository ("make a new commit or stash
changes") — which yields a real hash that caches like any other version. The rejected alternative
was to keep the hatch under a name stating its consequence (`recompile_if_unreproducible`, with a
`@compat public` setter, since a knob with no API is the incoherence the 2026-08-05 entry flagged
about `setMarchFlag`).

Technically breaking for anyone constructing `PhysiCellSimulator` with nine positional arguments.
Nothing in either repo does — every construction site is the no-argument constructor — and the
package is pre-1.0.

### Testing the guard
Added to `CompilationTests.jl`. The wiring is pinned by setting `current_version_id` to the `-1`
sentinel and calling `loadCustomCode`: with the refresh in place the id is corrected and the call
returns `true`; without it, the first read of the version cannot resolve an executable name at
all, so the test fails loudly. The semantics are pinned by editing a tracked PhysiCell file
without re-initializing and asserting that the id is unchanged until `refreshPhysiCellVersion()`
runs, then that the hash gains `-dirty`, `unreproduciblePhysiCellVersion()` flips, and no
executable exists for the dirty version. Restored in `finally`.

`PhysiCellVersionTests.jl` already dirties the repository exactly this way — it just
re-initializes afterwards, which is why the gap was never caught.

Not covered: the checked-out-a-different-commit case, which needs a second commit available in
`test/PhysiCell`. It drives the identical code path as the dirty case.

---

## 2026-08-05 — `-march` selection: investigation only, implementation deferred

### Motivation
`PhysiCellSimulator()` picks `march_flag` as `isRunningOnHPC() ? "x86-64" : "native"`
(`src/physicell_simulator.jl:46`). `isRunningOnHPC()` is `which sbatch` (ModelManager
`src/hpc.jl:19`), so the question was whether a better check exists. Investigated; a design brief
was written and then deliberately shelved. Nothing implemented.

### The predicate is about scheduler presence, not architecture
`-march` is not about "am I on an HPC" and not about a login/compute split at compile time. The
compiled executable is persisted to `inputs/custom_codes/<folder>/` and reused on any later session
unless the macros or the PhysiCell commit hash changed. **The cache key contains no ISA or march
component.** (Updated 2026-08-19: the executable is now named `project_<physicell-version>` rather
than a single overwritten `project`, so the PhysiCell version *is* the cache key — still with no ISA
or march component. Line references in this entry predate that change.) So the
real question is "will this on-disk binary ever be executed by a machine that did not build it,"
which cannot be answered from the current session:

- Compile on a login node with `useHPC(false)` for a local test → `native` bakes in that node's ISA
  → a later session flips `useHPC(true)` and `sbatch` ships the *same cached binary* to compute nodes.
- Compile inside an allocation on compute node A → `native` is node A's ISA → the next array job
  lands on older node B.

Presence of a batch scheduler is a good proxy for that, because a scheduler is precisely the thing
that hands a binary to a different machine. On a laptop the binary only ever runs on that laptop.

Compilation is a plain `run(...)` from the Julia process (`src/compilation.jl:52`) and is never
submitted through a scheduler — it always happens on whatever node Julia occupies. That does not make
`native` safe on a cluster; it makes the binary arbitrarily tied to whichever node happened to run
Julia.

### Three distinct failure classes — only two are `-march`-addressable
| Case | build → run | fails at | fixable by `-march`? |
|---|---|---|---|
| mixed µarch, one ISA | Haswell → Ivy Bridge | run (SIGILL) | yes — already fixed by the `x86-64` default |
| uniform non-x86 cluster | aarch64 → aarch64 | compile (`unknown value 'x86-64' for -march`) | yes — needs an arch-aware fallback |
| mixed-ISA cluster | x86 login → aarch64 nodes | run (`ENOEXEC`, "Exec format error") | **no** |

The third row is real hardware (Ookami pairs x86 login nodes with A64FX compute nodes; Grace-Hopper
partitions bolted onto x86 clusters are appearing). No `-march` value helps — an x86-64 ELF cannot
exec on aarch64 regardless of ISA baseline. It is a cross-compilation problem, and PCMM's
compile-then-submit structure cannot support it without an `sbatch`'d compile step on the target
partition plus an ISA-keyed executable cache. **Recommendation: document as unsupported** ("run Julia
on a node with the same architecture as your compute partition"). The failure is immediate and
legible at job launch, not silent. Slurm does expose `Arch=` per node in `scontrol show nodes` if a
warning is ever wanted, but it is not worth the parsing.

### Findings that constrain any future design
- **There is no public API for this.** `setMarchFlag` (`src/compilation.jl:415`) is not exported and
  has no `@compat public`; the test suite reaches for it as
  `PhysiCellModelManager.setMarchFlag` (`test/test-scripts/ClassesTests.jl:63`). A user whose
  auto-detection guesses wrong has no supported recourse. This, not ergonomics, is the gap a
  `PCMM_MARCH` env var closes.
- **`run_on_hpc` and the march flag are already decoupled.** `isRunningOnHPC()` has exactly one
  caller in either repo — the march default. `mm_globals().run_on_hpc` defaults to `false`
  (ModelManager `globals.jl:52`) and is mutated only by `useHPC`, so `useHPC(false)` cannot affect
  compilation. Using the global *would* be wrong, but for a subtler reason than "the user might turn
  it off": its value at compile time does not constrain its value at run time, and the cached binary
  spans both.
- ModelManager's `globals.jl:24` still documents `run_on_hpc` as "`true` when `sbatch` is available
  (auto-detected)". Stale — nothing wires the probe to it. ModelManager fix, different repo.
- **`x86-64-v3` is exactly the Haswell feature level** (AVX2/FMA/BMI2). It is therefore the *risky*
  choice on the cluster whose pre-Haswell nodes originally broke `native`. Never make it a default;
  opt-in only after checking the oldest node in the target partition.
- **`-m64` is hardcoded** in `cflags` (`src/compilation.jl:95`) and is x86-only. Fixing `-march` alone
  will not make an ARM Linux cluster compile — the two must move together.
- An env var override does not solve the arch problem (a dotfile follows you onto any machine). The
  mitigation is to **validate the resolved flag against the actual compiler** before `make` runs —
  `g++ -march=<flag> -fsyntax-only -x c++ /dev/null`, nonzero exit means unusable here. One cheap
  subprocess that catches a stale dotfile, a typo, *and* an auto-detected `x86-64` on an ARM cluster,
  turning an error buried in `compilation.err` into an actionable message.

### Deferred design (PCMM side, ~70 lines src / ~50 test / ~15 docs, risk low–medium)
1. `_defaultMarchFlag()` — `get(ENV, "PCMM_MARCH")` then fall back to the probe.
2. `_mayRunOnOtherHosts()` — ``isRunningOnHPC() || shellCommandExists(`qsub`) || shellCommandExists(`bsub`)``
   (Slurm / PBS-Torque-SGE / LSF). Keep it internal and ~6 lines: it is **deliberately disposable
   scaffolding**, to be replaced by `scheduler() !== :none` once ModelManager grows a real scheduler
   abstraction. Say so in a source comment so it is not preserved out of misplaced respect.
3. `_marchFlagSupported(compiler, flag)` — validate at first compile (not `__init__`, where the
   compiler may not be configured), memoized per `(compiler, flag)`; skip entirely when
   `shellCommandExists(compiler)` is false so `make` keeps producing the error it always has.
4. Promote `setMarchFlag` with `@compat public` — an env var for a knob whose function form is
   internal is incoherent, and public status is what lets new docstrings `@ref` it.
5. Docs: short section in `docs/src/man/installation.md` (there is no central env-var page —
   `PCMM_PYTHON_PATH` is documented only in `physicell_studio.md` and `PHYSICELL_CPP` nowhere), plus
   two lines in `known_limitations.md` for the mixed-ISA case.

Behavioral break to call out in a release note: PBS/LSF/SGE users move from `native` to `x86-64` —
correct, but slower for anyone on a homogeneous non-Slurm cluster who was getting away with `native`.
`PCMM_MARCH=native` restores it.

### Rejected
- **Widening `isRunningOnHPC` itself.** That name honestly means "Slurm is available," and
  `useHPC`/`prepareHPCCommand` are Slurm-specific; widening it would be wrong the moment anything
  else consumes it. The march decision wants its own predicate.
- **An Lmod / `MODULESHOME` check.** Proposed early, then dropped: it is a proxy for a proxy (Lmod ⇒
  cluster ⇒ binary may relocate), it adds a false positive for Homebrew-Lmod workstations, and any
  cluster with Lmod has a scheduler the three command probes already catch.
- **Parsing `scontrol show nodes` to detect a genuinely heterogeneous partition.** Fragile, slow at
  load, needs permissions.
- **Compiling inside the job so `native` is safe and optimal.** Compilation already happens wherever
  Julia is; the missing piece is that the cached executable is not keyed on the ISA it was built for.
  Making `native` safe means keying the artifact on the march flag / detected ISA instead of
  overwriting a single `project`. The `rand_suffix` temp dir already anticipates concurrent
  compilation from multiple nodes, so the groundwork is half there — but this is a real feature, and
  `x86-64-v3` gets most of the performance for a fraction of the work.
  *(2026-08-19: the artifact is now keyed, on the PhysiCell version. Adding a march/ISA component to
  `executableName` is the remaining step.)*

### Open questions
- Why deferred: the `x86-64` default is correct for the common case and has held up across all three
  major OSes in the field. The live gap is only the silent `native` on non-Slurm sites.
- **Multi-scheduler submission is a separate repo and a separate brief.** `prepareHPCCommand`
  (ModelManager `src/runner.jl:79`) builds `sbatch --wrap="<command>"`, and **PBS has no `--wrap`** —
  `qsub` requires an actual job script, so a per-simulation script file must be written to disk. That
  is structural, not a flag rename. On top of it: `push!(flags, "--$k=$v")` (`runner.jl:96`) is Slurm
  long-option syntax applied to every user option; `--output`/`--error`/`--chdir`/`--wait` map to
  `-o`/`-e`/`-d`/`-W block=true` (PBS) and `-o`/`-e`/`-cwd`/`-K` (LSF); `defaultJobOptions()`'s
  `"job-name"` and `"mem"` are Slurm key names. Needs a semantic job-options layer (portable keys →
  per-scheduler rendering), a rename of `sbatch_options`, and a deprecation path, since
  `defaultJobOptions` and `prepareHPCCommand` are both `@compat public`.
- Ordering: the PCMM march branch is self-contained (needs only exported `isRunningOnHPC` and
  already-public `ModelManager.shellCommandExists`), so it can land first with no compat bound bump —
  at the cost of ~6 lines of throwaway. Doing ModelManager first yields no throwaway but leaves the
  non-Slurm SIGILL live.

---

## 2026-08-03 — Stop `__init__` from auto-initializing during precompilation

### Motivation
The logo + status banner was being printed repeatedly — apparently once per package in the environment that did `using PhysiCellModelManager`.

### The premise was wrong, and that determined the fix
Julia runs a module's `__init__` **at most once per process per load** (`run_module_init` is reached only from the cache-deserialization path in `loading.jl`; `canstart_loading` short-circuits an already-loaded module). Verified: loading three separate packages that each `using` a banner-printing base package ran `__init__` exactly once.

The repeats came from **separate processes** — specifically the precompilation subprocess of each *dependent* package. Only the package being precompiled has its own `__init__` skipped; its dependencies are loaded normally, so PCMM's `__init__` runs in every such worker. Julia 1.12 hands the worker the same pipe for stdout and stderr and surfaces it, live when a single package was requested and otherwise replayed boxed under `┌ <DependentPkg>` — which is why it looked like the *other* package was printing.

### Rejected: guarding on `mm_globals_ref` being non-`nothing`
The first attempt was `!isnothing(ModelManager.mm_globals_ref[]) && isInitialized() && return`. It cannot work: `mm_globals_ref` is a `const Ref` initialized to `nothing` and PCMM's own `__init__` is its only assignment site, so in a fresh precompile worker it is always `nothing` and the guard falls through. Measured directly — every reproduced duplicate had `ref == nothing` on entry. It was also doubly narrow, since it additionally required `isInitialized()`, which is false in a worker whose working directory holds no project (the common case).

Worse, keying on `mm_globals_ref` alone introduced a regression. `ModelManagerGlobals` holds exactly one `simulator`, and the ref is shared by every ModelManager backend. If another backend had already initialized, PCMM's `__init__` would return **before** registering its own `PhysiCellSimulator`, leaving PCMM running against a foreign one: `simulator().compiler` throws `FieldError`, and `runSimulation`/`setupMonad` dispatch to the other backend. On the base commit PCMM's unconditional assignment always won, so the guard only flipped *which* package silently lost.

### Chosen: gate on `jl_generating_output`, and check the simulator type
Two helpers in `src/PhysiCellModelManager.jl`:
- `_generatingOutput()` — true exactly while a cache file or sysimage is being written. Verified true in the worker, false in a real session. `@static if isdefined(Base, :generating_output)` prefers Base's wrapper, falling back to `ccall(:jl_generating_output, Cint, ()) == 1`. Reviewer (Copilot) suggested that as a stability win over the raw `ccall`; that premise is wrong — `Base.generating_output` is neither exported nor `public` (`ispublic` false on 1.12.6), and called with no argument its body *is* that same `ccall` (`base/runtime_internals.jl`). Adopted anyway, on the weaker but real ground that Base then owns the mapping to the C entry point. Written `@static` rather than as a runtime ternary, matching `DocstringRefTests.jl`'s `@static if isdefined(Base, :ispublic)`. Behaviour re-verified after the swap: a pure `Pkg.precompile()` from inside a project directory stayed silent and left `data/` empty.
- `_pcmmGlobalsRegistered()` — `!isnothing(globals) && globals.simulator isa PhysiCellSimulator && globals.initialized`. The simulator-type conjunct is what closes the multi-backend hole above.

Ordering matters: the globals are registered *before* the `_generatingOutput()` return, because registering them is pure in-memory work and keeps `mm_globals()` usable by any `PrecompileTools` workload in a dependent package. Only `initializeModelManager()` — which resolves `PhysiCell`/`data` from `pwd()`, opens the database, and prints the banner — is skipped.

### Side effect this fixes, beyond the noise
Because the worker inherits the parent's working directory, precompiling an unrelated package *from inside a project folder* had PCMM open the real project. Demonstrated: a worker created `data/pcmm.db` (12 KB) in a directory containing bare `PhysiCell/` and `data/` folders. With a real project it would also run `resolvePackageVersion` (which has an auto-upgrade path) and `initializeDatabase()` schema writes from a throwaway process. Investigated and ruled out: the `@async databaseDiagnostics` task does *not* trigger Julia's `waiting for IO to finish` precompile warning — zero occurrences across three forced recompiles with a faithful stub; it only appears if the async body is slow.

### On "if the globals change, that should print"
Read as an implication, not a biconditional — so no change needed. `postInitDisplay` already prints whenever `initializeModelManager` succeeds, which is exactly when the globals change. In the two paths that now return early, nothing changes, so printing nothing is correct.

### Open questions
- Whether two ModelManager backends should ever coexist in one process. Today they cannot (one `simulator` field); PCMM now reliably claims the globals instead of silently deferring. If coexistence is ever wanted, `ModelManagerGlobals` needs a per-backend registry, which is a ModelManager change.

---

## 2026-08-02 — Absorb ModelManager's docs-findability pass; declare PCMM's public API

### Motivation
`HANDOFF-modelmanager-docs.md` arrived from a ModelManager session after MM's docs-findability pass (MM HEAD `7c91292`), framed as "opportunity, not repair." Audited against PCMM `main` (`10a65877d`), that framing is wrong: one item is a latent **build break**, two findings are false, one transfers only in a different form, and four problems the handoff never mentions turned up.

### The build break (the reason this is not optional)
MM's `src/tags.jl` exports 17 names. `docs/make.jl` sets `modules=[PhysiCellModelManager, ModelManager]` and `checkdocs=:exports` with no `warnonly`, so Documenter's `missingdocs` requires every docstring on an exported name in *either* module to be rendered — and no PCMM `Pages` entry matches `tags.jl` (all 42 enumerated). It passes today only because `tags.jl` is unreleased: `git rev-parse v0.8.2^{tree}` equals the `git-tree-sha1` registered for 0.8.2, and that tree has no `tags.jl`. PCMM's docs CI `Pkg.develop`s PCMM only, so MM comes from the registry. **The day MM cuts 0.8.3, the docs job goes red.** Since `src/PhysiCellModelManager.jl:4` does `@reexport using ModelManager`, users already get all 17 tag names — with no page and no mention anywhere.

### Handoff findings corrected
- (c) "`up.md` does not render `up.jl`" — **false**; `lib/up.md:11-19` renders it for both modules.
- (d) "`project_configuration.jl` is not rendered" — **false**; `lib/globals.md:26-33` renders it.
- (f) self-resolving "See the *X* API reference" links — **does not transfer** in that form (PCMM has no man/lib H1 collisions). The live bug is **backticked sub-headings shadowing docstrings**: the `Header` resolver (order 1.0) precedes `Docs` (3.0), and PCMM has ~17 headings that are bare backticked names. Builds stay green, so this needs a deliberate slug-intersection check.
- (b) the `utilities.md` glob — **real**. `Pages` matching is `endswith(path, p)`; an exhaustive sweep of 42 globs × 65 files found three cross-suffix collisions, but only `utilities.jl` ← MM `xml_utilities.jl` is live (only `utilities.md` lists both modules).

### Newly found
`src/deletion.jl`'s docstring is **orphaned**: Julia stores a docstring in `Docs.meta` of the module whose *source contains it*, keyed by the owner binding — so a PCMM-authored docstring on `ModelManager.clearSimulatorArtifacts` lives in `meta(PhysiCellModelManager)`, while `lib/deletion.md` lists `Modules = [ModelManager]` only. Also: a dead `@autodocs` block at `lib/calibration.md:82-86` (PCMM has no `calibration.jl`; the `AutoDocsBlocks` runner has no emptiness check, so glob typos fail silently), `man/index.md`'s unfiltered `@index` contradicting `index.md:27`, and sidebar labels drifting from their H1s.

### Key decision — do **not** mirror MM on the public-API question
PCMM has 234 documented bindings, 177 non-public, only 3 underscore-prefixed. MM resolved its equivalent by *promoting* 35 names on the rule "none is underscore-prefixed, so by this repo's convention they were never internals." Applied here that promotes ~174 of 177 and makes the index cut pointless.

Chosen instead: **reachability defines the public API** — a name is public if we tell users how to use it, or if it is passed to or returned from a non-internal. Internals do not appear in the docs at all; a developer who wants them reads the source. The first-order closure over public PCMM docstrings is **six names**, not 177: `AgentDict`, `MonadPopulationTimeSeries`, `SimulationPopulationTimeSeries`, `PCMMPCFResult` (all documented return types, constructed in doctests → promote), plus `prepareSimulationCommand` and `resolvePhysiCellVersionID` (named only in prose, and their callers are legitimately public → rewrite the prose instead of promoting plumbing).

Two supporting rules: run the closure to a fixpoint, since a newly-public type's docstring can name further internals; and count types users *receive or pass*, but **not** types that merely appear in a dispatching method's signature.

### Rejected — per-method docstring splitting
Considered splitting a public function's docstring so internal-dispatch methods stay unrendered. Not viable: `@autodocs` computes `APIStatus` and applies `Filter` **per binding, not per signature**, so `Public`/`Private`/`Filter` cannot exclude one method — the only lever is `Pages`, i.e. relocating source files to satisfy Documenter. Worse, `missingbindings` removes one signature at a time, so for an *exported* function, rendering only some method docstrings makes the rest count as missing → `:missing_docs` → build error. Fallback adopted: leave the internal internal, strip the `@ref`, keep plain backticks. The one place the pattern exists (`getMeanCounts`, documented once against `AbstractPopulationTimeSeries`) already does the right thing and is itself internal.

### Sequencing
Registered MM 0.8.2 contains **zero** `@compat public` — all 16 sites postdate the tag. Against it, MM's public set is 134 vs 213 at dev HEAD. So dropping the `Public = false` blocks before 0.8.3 would de-render most of MM's API on PCMM's site. Stages A–C (docs-only) land now; Stage D (public-API declaration + index cut) is **hard-gated on MM 0.8.3**. Nothing merges or releases until 0.8.3 is out.

### Scope notes
Docs-only for Stages A–C. Stage D touches `src/` (`@compat public`, docstring rewrites) and `test/` (guard testset); the promotion list goes up for review before any source edit. Following the 2026-06-12 precedent: progress.md entry, no PRD entry, no README Implementation Status row.

### Open questions
- Whether MM will fold `_resolveVerbosity`'s behaviour into `runCalibration`'s docstring once PCMM drops the explicit `@docs` that currently renders it (handback item).

---

## 2026-07-23 — Migrate `src/loader.jl` onto PhysiCellOutput.jl

### Motivation
`src/loader.jl` (~865 lines) duplicated logic that now lives in the standalone **PhysiCellOutput.jl** (BergmanLabRegistry). PhysiCellOutput owns path-based, stateless loading (types keyed on `folder::String`, no database identity). PCMM should depend on it and delete the ported code, keeping only its database-identity layer.

### Design decision — §5 (preserve API via extension) over §4 (wrapper)
`PCMM_MIGRATION.md` offered two paths: (§4) a piracy-free PCMM-owned wrapper type carrying `simulation_id` and restoring `SimID=…` display, or (§5) `import` the PhysiCellOutput functions and add `::Integer`/`::Simulation` methods routed through `pathToOutputFolder`. The doc *recommends* §4, but that recommendation predates PCMM's actual shape:

- The only internal callers of the loader API are `src/analysis/*.jl`; they are **heavily typed on the concrete `PhysiCellSnapshot`/`PhysiCellSequence`/`AbstractPhysiCellSequence` types** and read their fields directly.
- The public API (`PhysiCellSnapshot(id, index)`, `PhysiCellSequence(id)`, `cellDataSequence(id, …)`) is exercised by tests and docs.
- §4's wrapper must **not** subtype `AbstractPhysiCellSequence` (a documented gotcha — internal `getfield` use bypasses `getproperty` forwarding), so it would not flow through the analysis signatures without re-typing every one; and it renames the public constructors. Net: §4 is the *more* invasive option here.
- §5 preserves the exact public API and keeps all analysis code working unchanged, because id-based constructors return the *real* folder-based PhysiCellOutput objects. Piracy is confined to one file and is tolerable because PCMM is the terminal application in the stack (the doc says as much).

Chosen: **§5**, plus keep `assertInitialized()` at PCMM's id-based entry points (PhysiCellOutput doesn't assert).

### The one real friction: `sequence.simulation_id`
PhysiCellOutput's `PhysiCellSequence` has no `simulation_id` field. Three sequence-typed builders read it to stamp results: `SimulationPopulationTimeSeries` (`population.jl`), `AverageSubstrateTimeSeries` and `ExtracellularSubstrateTimeSeries` (`substrate.jl`). Every public/test path reaches these via an id/`Simulation`/run-output entry point (no bare-sequence call in tests), so the id is threaded explicitly from the entry point into the sequence-typed builder instead of being read off the sequence.

### Consequences
- `show(::PhysiCellSnapshot)` now prints `Folder=…` (PhysiCellOutput's display) instead of `SimID=…`. No test asserts the old text; accepted.
- `getCellDataSequence` deprecation now comes from PhysiCellOutput (re-exported); PCMM's own copy deleted.
- `_safe_matread` zero-cell workaround dropped; relies on `MAT ≥ 0.12.1`.

### Open questions
- None blocking. Optional future: an additive SimID-carrying convenience type if users want `SimID=…` display back.

---

## 2026-07-22 — Vector/range dispatch for `makeMovie`

### Motivation
`makeMovie(4:7)` (a `UnitRange{Int}`) and `makeMovie(Simulation.(4:7))` (a `Vector{Simulation}`) both threw `MethodError` — only the scalar `Int`, single `AbstractTrial`, and `PCMMOutput` forms existed. Batching over an explicit collection of IDs or trials is a natural call and should mirror the existing `AbstractTrial` batching.

### Design
- Added `makeMovie(simulation_ids::AbstractVector{<:Integer}; kwargs...)`, reusing the "announce → loop → delegate" shape of the `AbstractTrial` method.
- Added `makeMovie(Ts::AbstractVector{<:AbstractTrial}; kwargs...) = makeMovie(simulationIDs(Ts); kwargs...)`, flattening to IDs via `simulationIDs` (already accepts a vector of trials) so it reuses the integer-vector path.
- Broadened the worker signature from `simulation_id::Int` to `simulation_id::Integer`: elements of `AbstractVector{<:Integer}` / the output of `simulationIDs` aren't guaranteed to be `Int`, and downstream (`trialFolder`, etc.) already accept `Integer`. Purely additive — no behavior change for existing callers.

### Testing
Extended `test/test-scripts/MovieTests.jl` (Apple branch) with `makeMovie(1:1)` and `makeMovie(Simulation.(1:1))`, each a no-op (`out.mp4` already exists) returning `nothing`.

---

## 2026-07-08 — Expose Makefile animation parameters (`framerate`, `magick_density`, `magick_resize_x/y`) in `makeMovie`

### Motivation
`makeMovie` (`src/movie.jl`) only ever forwarded `OUTPUT=` to the PhysiCell Makefile's `jpeg`/`movie` targets, even though that Makefile also reads `FRAMERATE`, `MAGICK_DENSITY`, `MAGICK_RESIZE_X`, `MAGICK_RESIZE_Y` (defaults 24 fps / 96 dpi / 1024×1024). Users had no way to control frame rate or JPEG resolution/density from Julia.

### Design
- Added four new keyword arguments to `makeMovie(simulation_id::Int; ...)`, each `Union{Missing,Int}=missing`, mirroring the existing `magick_path`/`ffmpeg_path` sentinel pattern already in this function rather than inventing a new convention.
- Each is only appended as a `"VAR=value"` string to the relevant `Cmd` when not `missing` — an unset keyword falls through to whatever the target project's own Makefile defines for that variable, rather than PCMM silently overriding a user's project-level Makefile customization.
- `framerate` targets the `movie` command; `magick_density`, `magick_resize_x`, `magick_resize_y` target the `jpeg` command (matches which Makefile target actually reads which variable).
- `makeMovie(T::AbstractTrial; kwargs...)` / `makeMovie(T::PCMMOutput; kwargs...)` needed no changes — they already forward `kwargs...` untouched.

### Testing
Extended `test/test-scripts/MovieTests.jl` with a case passing non-default values for all four new keywords and confirming `out.mp4` is still produced; existing no-kwargs path is unchanged and still covered.

### Docs
- `docs/src/lib/movie.md` needed no edit — it's an `@autodocs` page over `movie.jl`, so the updated docstring flows through automatically.
- Added a "Movies" section to `docs/src/man/analyzing_output.md` (before "Post-processing during a run") documenting `makeMovie` and a table mapping each new keyword to its Makefile variable and default.
- Added a matching recipe to the `examples.md` cookbook, linking back to that new section, following the existing task → minimal code → link pattern.

---

## 2026-07-08 — Task B: `populationCountQoI`, a ready-made `post_processor` builder

### Motivation
Task A made `post_processor` usable (intact output guaranteed), but a user still had to know
which PCMM loader to call and how to shape its return value. Task B (deferred from the
original post-processing handoff, "optional/nice-to-have") closes that gap: a one-line
`post_processor` for the most common QoI, per-cell-type population counts, at the final
snapshot or any indexed save (the user asked for both explicitly).

### Design
- New file `src/analysis/post_processor_qois.jl` (included from `analysis.jl`), kept
  separate from `src/analysis/standard_qois.jl` on purpose: that file's functions are
  calibration summary statistics keyed by `monad_id` and averaged across replicates (for
  `CalibrationProblem`); `populationCountQoI` returns a closure keyed by `SimulationProcess`
  for ModelManager's post-processing sink (one row per simulation). Different shape, different
  consumer — conflating them in one file would blur that distinction.
- `populationCountQoI(; index=:final, cell_types=nothing, include_dead=false)` mirrors the
  existing `cell_types`/`include_dead` keyword convention from `endpointPopulationCounts`
  (`standard_qois.jl`) for consistency rather than inventing new names.
- Returns `Dict("count_$(name)" => n for ...)` rather than a `NamedTuple`: cell type names
  can contain spaces (e.g. `"fast T cell"`), which aren't valid `NamedTuple` field names: a
  `Dict` sidesteps that identifier-validity problem entirely.
- Missing snapshot (e.g. pruned) → `populationCount`/`PhysiCellSnapshot` already return
  `missing` for that case; the builder checks for it and returns `nothing` (no QoI recorded)
  rather than propagating an error, matching the "prefer `nothing` for the no-data case"
  guidance from the original handoff.

### Testing
New `test/test-scripts/PostProcessorQoITests.jl` (added to `runtests.jl` after
`PopulationTests.jl`, so `finalPopulationCount`/`populationCount`/`pruned_simulation_id`
semantics are already established). Constructs a `SimulationProcess` directly (plain struct,
default positional constructor) to unit-test the returned closure — index default, integer
index, `cell_types` filter, `include_dead`, and the pruned/missing-snapshot path — without
needing a live run for each case, plus one full `run(...; post_processor=populationCountQoI())`
integration test asserting the sink DB (`postProcessingTable`) is populated correctly.

### Docs
- API reference: `docs/src/lib/analysis.md`, new "Ready-made `post_processor` builders"
  subsection with an explicit `@docs populationCountQoI` block (mirrors how
  `calibration.md` documents `standard_qois.jl`'s functions individually rather than via a
  blanket `@autodocs` page, since `checkdocs=:exports` requires every export to be
  documented somewhere).
- User guide: also wrote the "Post-processing during a run" section in
  `analyzing_output.md` that was deferred from the original docs handoff (gated on Task B
  landing) — hook description, the three return patterns with real PhysiCell loaders (not
  ModelManager's stand-ins), the `populationCountQoI` builder, and reading results back.
  Cross-linked from a new `examples.md` cookbook entry.

---

## 2026-07-08 — Docs for batch `run(Vector)` and the calibration evaluation budget (D5/D6)

### Source
Third handoff from the ModelManager session (`handoff-pcmm-batch-and-budget.md`), completing the story started by the post-processing handoffs. Both ModelManager changes are inherited via `@reexport using ModelManager` — no PCMM code change, doc-only.

### D6 — `max_evaluations` enforcement (`docs/src/man/calibration.md`)
Verified against the ModelManager dev checkout (`_capBatchToBudget`, applied before dispatch in both `_runFirstGeneration` and `_runSubsequentGeneration`, `src/calibration/abc_smc.jl`). Rewrote the "Evaluation budget" section to state, as current behavior, that the cap is enforced before each batch (never overshoots) and the final generation may be partial. Added a callout that `max_evaluations` counts particles (monads), not simulations — a calibration launches up to `max_evaluations × n_replicates` PhysiCell simulations, since PCMM's `CalibrationProblem` runs `n_replicates` simulations per particle.
Deliberately wrote this as "how it behaves," not "here's what changed" — a reader who never saw the old overshooting behavior shouldn't have to parse a before/after diff to understand the current contract.

### D5 — batching pre-built trials (`docs/src/man/examples.md`)
PCMM has no page equivalent to ModelManager's `running_simulations.md`, so the cookbook-style `examples.md` (task → minimal code → link) was the right home instead of forcing a new page. Added a "Batch pre-built trials into one run" recipe linking to `Your first project`, since that page already documents the `PCMM_NUM_PARALLEL_SIMS` parallel-pool knob — ties the "one parallel pool across the whole batch" behavior to a concept the reader has already seen.

### Style note (user feedback, applies going forward)
Don't over-explain decisions in docs pages by referencing prior versions or the conversations that produced them — a reader new to PCMM has no context for "used to be X, now Y." State current behavior directly; save the before/after narrative for this file.

---

## 2026-07-07 — Post-processing hook: move pruning to `postSimulationCleanup` (Task A)

### Motivation
ModelManager (0.7.x, dev) added a user `post_processor` callback and split the single per-simulation post hook into `postSimulationProcessing` (non-destructive, before the callback) → `post_processor` → `postSimulationCleanup` (destructive, after). PCMM was pruning inside `postSimulationProcessing`, so under the reordered ModelManager a user callback would be handed an already-gutted output folder. This session moves PCMM's destructive work to `postSimulationCleanup` so a `post_processor` always reads intact output.

### Synthesis source
Planned from two handoff docs from the ModelManager session (`handoff-pcmm-postprocessing.md` = code, `handoff-pcmm-docs.md` = docs). Their inferred PCMM specifics were re-verified against source before coding: `postSimulationProcessing(::PhysiCellSimulator, …)` was at `src/simulator_interface.jl:246` with exactly the described body (err handling + `pruneSimulationOutput(simulation, prune_options)`).

### Decisions
- **Moved the whole body**, not just pruning: the err-file handling (rm `output.err`/`hpc.err` on success; annotate on failure) runs equally well after the callback, and a callback has no reason to read `output.err`. Cleanest split — leaves `postSimulationProcessing` at ModelManager's no-op default, so PCMM no longer defines it at all.
- **Import wiring:** swapped `postSimulationProcessing` → `postSimulationCleanup` in the `import ModelManager:` (extend) list; kept `postSimulationProcessing` in the non-extending `using ModelManager:` line so its docstring `@ref` still resolves (ModelManager doesn't export the hooks and PCMM has no DocumenterInterLinks, so a referenced symbol must be in PCMM's namespace).
- **Testing:** dev-checked-out the local ModelManager worktree (v0.7.5, which already has the reordering + no-op `postSimulationCleanup` default) so the reordered contract is exercised locally. Confirmed method resolution: PCMM owns `postSimulationCleanup(::PhysiCellSimulator, …)`; `postSimulationProcessing` falls through to ModelManager's no-op.
- **No compat change:** PCMM pins `ModelManager = "0.7"`; the feature ships in a `0.7.x` bump, still in range.

### New export the handoffs missed — `monadsTable`
ModelManager also just added `monadsTable`/`printMonadsTable` (monad-level analogue of `simulationsTable`), re-exported by PCMM. Documented this session:
- **API reference:** no change needed — `docs/src/lib/database.md` already autodocs `Modules = [PhysiCellModelManager, ModelManager], Pages = ["database.jl"]`, and `monadsTable` lives in ModelManager's `database.jl`, so it's auto-included once docs rebuild against the updated ModelManager.
- **User prose:** added a "Monad-level: `monadsTable`" subsection to `man/querying_parameters.md` (next to `simulationsTable`), not `analyzing_output.md` — querying_parameters is where `simulationsTable` is already explained, so the analogue belongs there.

### Docs nav rename (same session, user request)
Renamed the docs nav section `"Experiments"` → `"Uncertainty Quantification"` in `docs/make.jl` to match ModelManager's naming (both group Sensitivity analysis + Calibration). Nav-label-only; no prose referenced "Experiments".

### Test strategy
Appended to `PrunerTests.jl`: a run with a `post_processor` that records whether `output*.mat` files exist in `pathToOutputFolder(sp)` during the callback (must be intact), then asserts they're gone after the run (cleanup pruned them). No-regression "pruning without a callback" is already covered by existing `pruned_simulation_id` assertions in Loader/Population/Substrate tests, fed by the existing no-callback run in `PrunerTests.jl`.

### Open questions
- Task B (QoI builders): design `populationCountQoI(; index=:final)` on `PhysiCellSnapshot(sim_id, index)` — the user asked for final counts *and* any indexed save.
- Release lockstep: PCMM Task A must not ship against a ModelManager that still has the old single-hook ordering.

---

## 2026-06-15 — Upgrade-path CI for `src/up.jl`

### Motivation
`src/up.jl` (cross-version DB/file migrations) was untested. It can't live in `Pkg.test()` because exercising a migration needs *two* package versions present: an old one to write legacy data and a new one to upgrade it. Goal: a dedicated workflow that replays real version history.

### Findings that shaped the design
- **`v0.0.1`/`v0.0.2` were never released.** Registry floor is `pcvct@0.0.3` (UUID `3c374bc7…`); the package was renamed to `PhysiCellModelManager` (UUID `7582d1aa…`) at `0.1.0`. So the harness derives the package name from the source version, and "start at v0.0.1" is impossible via `Pkg`.
- The upgrade driver (`ModelManager.upgradePackage`) always upgrades to the runtime `pkg_version`; there is **no "stop at version X" knob**, and ModelManager is out of scope (separate repo). So "one milestone hop" is controlled by *which version performs the upgrade*, not by capping.
- `upgradeToV0_3_0` only adds the `calibrations` table, which `initializeDatabase` also creates on every init — so that migration's effect is shadowed and not independently observable. Early hops therefore assert **data preservation**, not migration-specific deltas.

### Decision: "go backwards"
Rather than start at the oldest release and upgrade with an *intermediate released* version (which would test released code, not the repo), generate with an older release and **upgrade with the dev checkout** — this exercises the repo's actual `src/up.jl`.
- **Concrete goal (this session):** support upgrading a **`0.1.7`** project — the version a real user (the repo owner) is currently on — to `HEAD`. `0.1.7` → `HEAD` crosses `0.2.0` (the `upgradeToV0_2_0` par_key binary rewrite) and `0.3.0`.
- CI matrix source versions: `0.1.7` (primary) and `0.2.2` (isolates the `0.3.0` hop for diagnosis). Verified against the `v0.1.7`/`v0.2.2` tags that the generation API — `createProject`, `InputFolders(...; rulesets_collection)`, `DiscreteVariation`, `configPath` shortcuts, `createTrial(...; n_replicates)`, `run` → `PCMMOutput` — is unchanged, so one `generate.jl` covers both.
- `verify.jl` asserts the distinguishing `par_key` column on every varied-location variations table when the `0.2.0` milestone is crossed (not produced by normal init, unlike `0.3.0`'s `calibrations` table).
- Source version is a single parameter so we can keep walking back into the `pcvct` era, ideally to `0.0.3`.

### Rejected
- *Generate@0.0.3 → upgrade@0.0.10 (released)* — tests the released migration code, not the repo's `up.jl`; also can't reach the pre-0.0.3 functions anyway. Kept as a possible future "released-vs-released" cross-check, not the primary path.
- *Adding a `target_version` cap to `initializeModelManager`* — would let the dev version do a single hop from old data, but requires editing ModelManager (out of scope).

### Design
New workflow `.github/workflows/UpgradeCI.yml` (same triggers as `CI.yml`; ubuntu-latest; Julia `lts` + `1`). Two isolated Julia envs under `test/upgrade/tmp/`: a generation env with the pinned old release, and the dev checkout for the upgrade. Scripts `test/upgrade/generate.jl` and `test/upgrade/verify.jl`, parameterized by `PCMM_UPGRADE_SOURCE_VERSION`. Verification reads the SQLite DB directly so it's independent of either package's API.

### First CI run — caught a real bug (the harness paid off immediately)
The very first `0.1.7` → `HEAD` run failed at the `0.2.0` milestone with `UndefVarError(:validateParsBytes)`. Root cause: `upgradeToV0_2_0` (`src/up.jl`) calls `validateParsBytes` unqualified, but the `bafb5b528` modularization moved that helper into ModelManager (`variations.jl`) and it is **not exported**. The other non-exported MM helpers `up.jl` needs were explicitly imported at the top (`using ModelManager: continueMilestoneUpgrade, populateTableOnFeatureSubset`); `validateParsBytes` was missed.
- **Impact:** this is a real shipping bug — any user on `0.1.7` (incl. the repo owner) could not upgrade to `0.2.0+`; the migration threw and rolled back every time.
- **Fix:** added `validateParsBytes` to that explicit import. Chose the in-repo import over exporting from ModelManager (out of scope) and to match the existing pattern in the file.
- Only this one surfaced because it is the last statement in the migration's `try` block — everything before it resolved, so the rest of the chain is exercised.

### Open questions
- How far back can generation's API be reused? `0.2.x`→`0.3.x` should share the `createProject` / `run(sampling)` API; the `pcvct` era will likely need an older generation script.
- Does `pcvct@0.0.3` stamp a version table the newer code can read? (Resolved only when we walk back that far.)

---

## 2026-06-12 — Documentation restructure for clarity & discoverability

### Motivation
Users repeatedly asked how to use PCMM. The docs were accurate but dense and poorly catalogued: a flat 17-item "Manual" in arbitrary order (led with *Best practices*, not *Getting started*), a 34-page alphabetical API "Documentation" dump, a getting-started page that buried the happy path under the optional `importProject` workflow, and no Julia environment-management guidance.

### What changed
- **Sidebar regrouped by user intent** (`docs/make.jl`): Getting Started → Building & Varying Models → Experiments → Analyzing Results → Examples → Tools & Integrations → Reference → Contributing → API Reference → Miscellaneous.
- **Getting-started split** into focused pages: `installation.md`, `julia_environments.md` (new — per-project envs as a Julia best practice), `getting_started.md` retitled *Your first project* (happy path only), and `importing_projects.md` (the extracted `importProject` workflow).
- **New `examples.md` cookbook hub**: task-oriented catalog ("I want to… → snippet + link"). `index.md` rewritten as a hub with a "Where do I look?" table.
- **API reference grouped by code family** (Core / Project & inputs / Running / Analysis / Management), explicitly *not* mirroring the Manual; alphabetical Index kept for name lookup. List is now hand-maintained (noted in a `make.jl` comment).
- **Editorial concision pass** over every manual page — cut filler/hedging, collapsed restatements, listified dense paragraphs; no facts, examples, `@ref`s, or doctests removed.

### Key decisions
- **Manual vs API reference kept independent.** Considered mirroring their structure (user asked); rejected as redundant and high-maintenance — they serve different purposes (intent-ordered narrative vs. lookup-optimized exhaustive docstring home).
- Renamed the XML-path-helpers page H1 from "Helper functions to define targets" → "XML path helpers" to match its sidebar label; updated the one referrer.
- Disambiguated colliding section refs: `[Examples]` and `[Calibration]` resolved via explicit `@id` (`examples_cookbook`, `calibration_section_man`) because duplicate/`@id`-bearing headers exist.

### Verification
Built docs locally with `julia --project=docs docs/make.jl`. Cross-reference and nav validation pass (no broken `@ref`, no unlisted pages). The pre-existing `src/analysis/pcf.jl` doctests fail locally only because the optional `PairCorrelationFunction` package isn't in the local docs env — unrelated to this change and green on CI. Validated links by building once with `doctest=false` (temporary, reverted).

### Scope notes
Docs-only; no source/PRD/behavior changes. README Implementation Status unaffected (tracks features, not docs structure).

---

## 2026-05-17 — MM 0.7.0 calibration features; CI registration gap

### Status
All calibration infrastructure is now in ModelManager 0.7.0 (branch `feature/latent-inverse-maps`, ready to merge). PCMM's `Project.toml` already pins `ModelManager = "0.7.0"`.

### CI failure
PCMM CI is failing because ModelManager 0.7.0 is not yet registered in BergmanLabRegistry (latest registered is 0.6.0). Fix sequence:
1. Merge MM `feature/latent-inverse-maps` → `main`.
2. Register `ModelManager 0.7.0` in BergmanLabRegistry (add entry to `Versions.toml` with the git-tree-sha1 of the new `main` tip).
3. Re-run PCMM CI — the resolver should pick up 0.7.0 immediately.

### What's in MM 0.7.0
- `LatentVariation.target_names` for user-supplied LV parameters
- `inverse_maps` validation and auto-construction for DV/CVSource; user-supplied + round-trip check for LVSource
- `resumeABC` structural validation extended to LVSource (non-stripped)
- Scan-based `_loadGenerations` (padding-agnostic on resume)
- `generation_cdfs/` stored as subdirectory of `generations/`
- Posterior visualization recipes: `:corner`, `:ridgeline`, `:convergence`, `:transition`
- `short_names=false` kwarg on `simulationsTable`
- Kernel type hierarchy: `GaussianKernel`, `ComponentwiseKernel`, `LocalNNKernel`, `LocalNNCovKernel`

---

## Rollback anchor — last commit with functioning pyabc backend

If the native Julia ABC-SMC implementation proves non-functional or needs a side-by-side comparison, the last commit with the fully-wired PythonCall/pyabc backend is the tip of the `feature-par-naming` branch at the point of the merge into `feature/julia-native-abc`:

- **Commit:** `9d9dda07aa1464db02a9aeb1d0171d3f32db15f0`
- **Subject:** "Merge branch 'main' into feature-par-naming"
- **Last substantive pyabc change:** commit `2d575527` ("Refactor calibration integration from PyCall to PythonCall")

To restore the working pyabc state: `git checkout 9d9dda07aa1464db02a9aeb1d0171d3f32db15f0 -- ext/PCMMCalibrationExt.jl CondaPkg.toml Project.toml src/calibration/` (adjust paths as needed) or branch from that commit directly.

---

## 2026-04-24 — Remove PythonCall / pyabc deprecation residue

Executed the cleanup promised in the 2026-04-22 entry and in [PRD.md](PRD.md). Native ABC-SMC passed the full test suite (107/107 CalibrationTests; overall 581/2/4 matching pre-merge baseline), so the deprecated pyabc surface is now deleted:

- `ext/PCMMCalibrationExt.jl` — deleted. The stub only emitted a `Base.depwarn`; it added no methods. Removal has no runtime effect.
- `CondaPkg.toml` — deleted. No longer needed since no Python deps remain.
- `Project.toml` — removed `PythonCall` from `[weakdeps]`, `[extensions]`, `[compat]`, `[extras]`, and the `test` target list.
- `docs/src/man/calibration.md` — removed the "Deprecated pyabc backend" trailer section.
- `PRD.md` — removed the "Sub-feature: Deprecated pyabc backend" subsection.

Rollback is via the commit hash recorded above, if ever needed.

---

## 2026-04-24 — `AbstractSimulationSpec` / `SimulationSpec` refactor

Replaced the calibration's `redirect_stdout(devnull)` stopgap with a real `quiet=true` kwarg on `run` by completing the SimulationSpec refactor across MM and PCMM.

### Architecture

- **`AbstractSimulationSpec`** (in MM, `src/runner.jl`): abstract type, extension point for future simulators with distinctive per-spec state. Not a dispatch axis.
- **`SimulationSpec`** (in MM): concrete default subtype with just two fields: `simulation::Simulation` + `monad_id::Union{Missing,Int}`. PCMM uses this directly — no PCMM-specific spec needed because the spec is truly framework-agnostic.
- **One dispatch axis: simulator type.** No separate `dispatchSimulation` function. The existing `runSimulation(::AbstractSimulator, ...)` does all simulator-specific routing. Its signature is now `runSimulation(::AbstractSimulator, spec::AbstractSimulationSpec) → SimulationProcess`.
- **Setup hooks** (`setupMonad`, `setupSampling`) remain the simulator-specific injection point. They run once at the right level in `collectPendingSimulations`. Simulator-specific flags like PhysiCell's `force_recompile` flow as kwargs through `run` → setup hooks AND through `run` → per-spec `runSimulation`.
- **`do_full_setup` is encoded implicitly** in `ismissing(spec.monad_id)`: solo specs need full setup, monad-collected specs don't. PCMM's `runSimulation` derives this. Removed the explicit `do_full_setup` kwarg from the spec.

### Why drop `dispatchSimulation`

The earlier draft had `dispatchSimulation(::AbstractSimulationSpec; kwargs...)` as an interface stub for spec-type dispatch. Removed because: (a) for the common case of one spec type per simulator, it's redundant with simulator dispatch; (b) the user's intuition was right — by spec time, all simulator-specific routing should be done. `runSimulation(simulator, spec)` is the only dispatch we need.

### Restored: per-simulation `println`

The "Running simulation: N..." line was lost in modularization (verified by grep). Now restored, living inside the `@task begin … end` body in MM's `run` so it prints when the task is *scheduled* (i.e. when the simulation actually starts), not when the list comprehension constructs the task. Gated by the `quiet` kwarg.

### Files touched

- `~/.julia/dev/ModelManager/src/runner.jl`: defined `SimulationSpec <: AbstractSimulationSpec`; `collectPendingSimulations` now returns `Vector{<:AbstractSimulationSpec}` and forwards kwargs to setup hooks; `runSimulation` interface stub takes `(::AbstractSimulator, spec; kwargs...)`; removed old `dispatchSimulation(::Simulation; ...)`; `run(T; quiet=false, kwargs...)` builds `@task` wrappers itself with per-sim println inside, gated by `quiet`.
- `src/simulator_interface.jl`: deleted local `SimulationSpec`; imports `SimulationSpec`/`AbstractSimulationSpec` from MM; `runSimulation(::PhysiCellSimulator, spec; force_recompile, kwargs...)` derives `monad_id` and `do_full_setup` from `spec.monad_id`.
- `src/calibration/abc.jl`: replaced `redirect_stdout(devnull) do run(monad) end` with `run(monad; quiet=true)`.
- CLAUDE.md: removed the "Port `quiet` kwarg" to-do.

---

## 2026-04-22 — Julia-native ABC-SMC (replacing pyabc)

### Context

The pyabc backend (via PythonCall/CondaPkg) worked but carried baggage: conda environment management, `SingleCoreSampler` constraint (Julia closures can't be pickled), and a deep PythonCall bridge. Goal: replace with a native Julia implementation.

### Julia ABC ecosystem survey

- **ApproxBayes.jl** — 56 stars, compatible with Julia 1.9+, but last substantive commit Sept 2024 (license update). Parallelism via `Distributed.jl` conflicts with PCMM's Channel-based runner.
- **KissABC.jl** — ARCHIVED Dec 2025, redirects to ABCdeZ.jl (unproven).
- **GpABC.jl** — 58 stars, actively developed (CI runs on Julia 1.12). The `julia = "1.6, 1.7"` compat string parses as intersection = `>=1.7.0`, so it *is* compatible with modern Julia. Initial survey misread this. Has GP emulation — worth revisiting for future surrogate work.
- **SimulationBasedInference.jl** — early stage, ABC-SMC not fully implemented.

Decision: implement directly. ABC-SMC is ~250 lines of algorithm code (Toni et al. 2009 / Beaumont et al. 2009), no new dependencies, integrates cleanly with PCMM's Monad/runner infrastructure.

### Key design decisions

**Framework-agnostic algorithm core**
`src/calibration/abc_smc.jl` operates on a generic `evaluate_particle(params) → (distance, metadata)` callback. All PhysiCell-specific wiring (Monad creation, addVariations, run) is isolated in `src/calibration/abc.jl`. This makes the upcoming extraction to ModelManager.jl straightforward — the algorithm core moves to the base package, and PCMM provides the PhysiCell adapter.

**Extensible `AbstractCalibrationMethod` hierarchy**
Added `AbstractCalibrationMethod` supertype with `ABCSMC <: AbstractCalibrationMethod`. Future methods (GP-accelerated ABC, Bayesian optimization) are additional concrete subtypes. `runCalibration(problem, method)` is the dispatch point; `runABC` is a convenience wrapper that constructs an `ABCSMC` from keywords.

**No warm-start from existing simulations**
An earlier design seeded gen 1 with all existing monads for this InputFolders. Rejected because it biases the gen-1 population away from the prior (the prior samples need to be truly random for the ABC-SMC weights to be correct). Instead, `Monad(...; use_previous=true)` in every particle evaluation still reuses exact-match parameter points transparently — no statistical bias, and zero cost when matches exist.

**Quiet mode for `run`**
Added `pcmm_globals.quiet_run::Bool` flag and `quiet::Bool=false` kw on `run`. When true, suppresses the "Running Sampling/Simulation..." and "Finished..." output. The calibration loop sets it so console output stays focused on per-generation progress.

**pyabc extension: depwarn, then delete**
User decision: deprecate and remove, but wait to confirm native works before deleting. The extension (`PCMMCalibrationExt`) is now a one-line `__init__` that emits `Base.depwarn` and adds no methods. The pyabc-specific code (runABC override, prior builder, etc.) has been removed from the extension entirely — rollback is via `git checkout` if needed.

**Result persistence**
Each generation is saved as `generations/generation_{t}.csv` with columns = param names + weight + distance + monad_id. Settings saved as `method.toml`. Together these support `resumeABC(calibration, problem)` for crash/stop recovery.

### Correctness verification

- Toy test: recover the mean of a Normal distribution via ABC-SMC. Posterior mean converged to ~2.15 against observed ~2.14 (true=2.0) over 5 generations, with epsilon shrinking 7.17 → 0.27 as expected.
- Full test suite: 107 calibration tests pass (algorithm unit tests, PhysiCell end-to-end, resume).

### Open questions

- GP emulation (GpABC.jl or custom): would reduce expensive PhysiCell evaluations. The `AbstractCalibrationMethod` hierarchy is ready for this — add `GPAcceleratedABC <: AbstractCalibrationMethod` without restructuring.

---

## 2026-03-29 — Analysis naming decisions

**`finalPopulationCount(Monad)` placement**
Added to `src/analysis/population.jl` (not a calibration file) because it is a general analysis utility. The summary statistics in `standard_qois.jl` delegate to it.

**`meanPopulationTimeSeries` naming**
Rejected "endpointPopulationTimeSeries" (contradictory terms). Chose `meanPopulationTimeSeries` wrapping `MonadPopulationTimeSeries.mean` field.

---

## Test infrastructure — 2026-03-30

### Decisions made

- Cleanup runs at the **start** of `runtests.jl`, not the end. Artifacts remain after a run for manual inspection; they are cleared before the *next* run.
- Artifacts list is maintained in sync between `test/.gitignore` and the cleanup block in `runtests.jl`. Both must be updated when a new test adds output paths.
- `test.out` (redirected stdout from manual runs) added to `.gitignore`.
- `InvalidRulesetExport` (generated by `ExportTests.jl`) was missing from `.gitignore` — added.

### Pre-existing test failures (not related to calibration)

These existed before this feature branch and should be tracked separately:
- `PhysiCellVersionTests` — HTTP 401 from GitHub API (rate limit in CI).
- `PhysiCellStudioTests` — likely same network dependency.
- Several test suites require a downloaded PhysiCell binary; they fail locally when it is absent but pass on GitHub runners.

---

## 2026-03-31 — Optional names for variations

### Decisions made

- Added optional `name` fields to all concrete `AbstractVariation` subtypes: `DiscreteVariation`, `DistributedVariation`, `CoVariation`, and `LatentVariation`.
- Introduced `variationName(::AbstractVariation subtype)` as the unified accessor for display labels.
- Chose keyword argument `name=...` for constructors to preserve existing positional APIs.
- For omitted names, defaults follow `shortVariationName(location, columnName(target))` conventions so labels align with existing summary table naming.
- `CoVariation` stores a single name for the combined variation; child variation names remain on each entry in `cv.variations`.
- Sensitivity scheme headers now naturally inherit variation names because `LatentVariation(dv|cv)` uses `variationName(...)` for `latent_parameter_names`.

### Notes

- This change is metadata-only for display and reporting; it does not alter variation keys in SQLite tables, which remain XML-path-based.

---

## 2026-04-25 — PCMM side of SimulationSpec flatten / setup-collect split

Counterpart to the MM refactor of the same date. See MM `progress.md` for the design rationale.

### Changes in PCMM

- **`setupSampling`**: type annotation `Sampling` → `AbstractSampling`. No logic change — `loadCustomCode(S::AbstractSampling)` already works.
- **`setupMonad`**: removed `do_full_setup::Bool` kwarg and its `if do_full_setup ... loadCustomCode ... end` guard. `setupSampling` always runs before `setupMonad` now, so compilation is always covered. Type annotation `Monad` → `AbstractMonad`.
- **`runSimulation`**: removed `ismissing(spec.monad_id)` branch. `spec.monad_id` is always `Int` post-refactor.
- **`prepareSimulationCommand`**: removed `do_full_setup::Bool` parameter and the setup branch it guarded. Signature is now `(simulation, monad_id, force_recompile)`.
- **`HPCTests.jl`**: `SimulationSpec(simulation, missing)` → `SimulationSpec(simulation, monad.id)`.
- **Imports**: removed `AbstractSimulationSpec` from `using ModelManager: ...` line.

### Files touched
- `src/simulator_interface.jl`
- `test/test-scripts/HPCTests.jl`
