# [Utilities](@id utilities_dev)

The small shared helpers PhysiCellModelManager.jl and ModelManager are built out of: use them rather
than reaching for SQLite, LightXML or `run` directly, so that one fix reaches every caller.

## SQLite

[`centralDB`](@ref) is the project's one connection, and it is the default `db` keyword on every
function below — pass another only for a per-folder variations database, which
[`locationVariationsDatabase`](@ref) opens for a given location and folder (returning `nothing` when
the location is unused and `missing` when the file does not exist), or for the post-processing sink
at [`postProcessingDBPath`](@ref), which is created lazily the first time a `post_processor` returns
a quantity to store.

Read with [`queryToDataFrame`](@ref) when the SQL is fixed and [`stmtToDataFrame`](@ref) when a value
has to be bound; both take `is_row=true` to assert exactly one row. Build the SQL with
[`constructSelectQuery`](@ref) and [`buildWhereClause`](@ref ModelManager.buildWhereClause) rather than by interpolating strings:
`buildWhereClause` is what turns a list of IDs and a `Dict` of column filters into a clause, and it
is the same clause the table-printing functions use, so a query written this way keeps agreeing with
them. Create a table with [`createMMTable`](@ref) — it enforces the naming convention the rest of
the database relies on, a plural table name with a `<singular>_id` primary key — and get a column's
type from [`sqliteDataType`](@ref), which maps a Julia type or an `ElementaryVariation` to the string
the schema needs. [`tableExists`](@ref) and [`tableColumns`](@ref) are how migrations in `src/up.jl`
check what they are about to change. Wrap several statements in [`withTransaction`](@ref) so they
land in one commit; nested calls join the enclosing transaction instead of starting their own, so it
is safe in a function that may itself be called from inside one.

```julia
using DataFrames, SQLite

# Fixed SQL: every completed simulation and the config variation it used.
query = constructSelectQuery("simulations", "WHERE status_code_id = 3";
                             selection = "simulation_id, config_variation_id")
completed = queryToDataFrame(query)

# Bound values instead of interpolation, asserting exactly one row comes back.
row = stmtToDataFrame("SELECT * FROM simulations WHERE simulation_id = ?", (7,); is_row = true)

# A table of our own, filled in a single commit.
withTransaction() do
    tableExists("notes") || createMMTable("notes", "note_id INTEGER PRIMARY KEY,
                                                    simulation_id INTEGER,
                                                    body TEXT")
    for id in completed.simulation_id
        DBInterface.execute(centralDB(),
                            "INSERT INTO notes (simulation_id, body) VALUES (?, ?)",
                            (id, "checked"))
    end
end

tableColumns("notes")   # ["note_id", "simulation_id", "body"]
```

## XML

PhysiCell's inputs are XML, so most of PCMM's configuration code is element lookup. Every helper
takes the path as a vector of tag names, with `tag:attribute:value` to select among siblings by
attribute and `tag::child_tag:content` — two colons after the tag — to select by a child's
content, as PhysiCell's initial parameter distributions require — [`getChildByAttribute`](@ref ModelManager.getChildByAttribute)
and [`getChildByChildContent`](@ref ModelManager.getChildByChildContent) are what resolve those two forms, and are worth calling directly
when you already hold the parent element.

[`retrieveElement`](@ref) walks a path and returns the element, throwing through
[`retrieveElementError`](@ref ModelManager.retrieveElementError) — which names the exact path component that failed, the part that
makes a wrong path diagnosable — unless `required=false`, in which case it returns `nothing`.
[`getSimpleContent`](@ref) and [`setSimpleContent`](@ref ModelManager.setSimpleContent) read and write a leaf's text through it,
asserting first with [`elementIsTerminal`](@ref ModelManager.elementIsTerminal) that the element really has no children, so a typo
that lands on a container fails loudly instead of silently destroying its subtree. Content comes back
as a string; [`parseValueFromString`](@ref) is the one place that decides what it means — `Bool` for
`"true"` and `"false"`, `Float64` for anything numeric, and the original string otherwise.

```julia
using LightXML

xml_doc = parse_file(joinpath(locationPath(:config, simulation), "PhysiCell_settings.xml"))

# Read a leaf; the path selects a <variable> by its name attribute.
raw = getSimpleContent(xml_doc, ["microenvironment_setup",
                                "variable:name:oxygen",
                                "physical_parameter_set",
                                "diffusion_coefficient"])
D = parseValueFromString(raw)          # 100000.0

# An optional element: nothing rather than an error when it is absent.
maybe = retrieveElement(xml_doc, ["user_parameters", "random_seed"]; required = false)

# Two colons select a sibling by a child's content instead of by an attribute:
# the <distribution> whose <behavior> child reads "oxygen uptake".
dist = retrieveElement(xml_doc, ["cell_definitions",
                                 "cell_definition:name:default",
                                 "initial_parameter_distributions",
                                 "distribution::behavior:oxygen uptake"]; required = false)

# Write it back.
setSimpleContent(xml_doc, ["overall", "max_time"], 720.0)
save_file(xml_doc, path_to_variation_xml)
free(xml_doc)
```

## Shell and filesystem

[`shellCommandExists`](@ref ModelManager.shellCommandExists) is the probe every optional external tool goes through — it is how
`isRunningOnHPC` looks for `sbatch` and how the movie code checks for ImageMagick and FFmpeg — so
prefer it to a bare `which`. [`quietRun`](@ref ModelManager.quietRun) runs a command with stdout and stderr sent to
`devnull`, which is what `src/compilation.jl` uses for `make clean` and similar steps whose output
would otherwise interleave across concurrently compiling samplings.

[`rm_hpc_safe`](@ref) replaces `rm` everywhere PCMM deletes project data. Off HPC it *is* `rm`,
exceptions included. On HPC it tries `rm` first, then moves whatever a network filesystem refused to
release into `data/.trash/data-YYMMDD/`, and returns `:removed`, `:staged` or `:unremoved` rather
than throwing — because every caller deletes the database rows first, and an exception would abandon
a bulk deletion with the rows already gone. Check the return value wherever the removal has to be
guaranteed.

[`gitState`](@ref) returns `(commit, branch, dirty)` for the repository containing a directory, or
empty strings when there is no repository. It is what stamps provenance rows, and `dirty` is the
point of it: a commit hash alone is a false promise of reproducibility if the working tree had
uncommitted changes.

```julia
# Optional tools are probed, never assumed.
shellCommandExists("ffmpeg") || error("ffmpeg not found on PATH")

# Build noise stays out of the console.
cd(() -> quietRun(`make clean`), temp_physicell_dir)

# Record what PhysiCell was when this ran.
state = gitState(physicellDir())
state.dirty == "true" && @warn "PhysiCell has uncommitted changes; this run is not reproducible"

# Delete a simulation's output, tolerating a cluster filesystem that will not let go.
if rm_hpc_safe(joinpath(dataDir(), "outputs", "simulations", "7");
               force = true, recursive = true) === :staged
    @info "still on disk under $(joinpath(dataDir(), ".trash"))"
end
```
