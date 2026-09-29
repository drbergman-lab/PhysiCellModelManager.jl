# [Querying parameters](@id querying_parameters_man)
Read back the parameters that past simulations actually ran with.

| Function | Reads | Best for |
|---|---|---|
| [`simulationsTable`](@ref) | the databases | readability |
| [`getAllParameterValues`](@ref) | every XML value | programmatic access |
| `getParameterValue` | one XML value | a single parameter |

## [`simulationsTable`](@id simulations_table_section)

!!! tiergloss
    [`simulationsTable`](@ref) returns a table of simulation data. By default it shows only varied
    values, renames columns to be human-readable, and sorts by every parameter column; keywords
    change each of these and can append tag and post-processing columns.
    [`printSimulationsTable`](@ref) is a wrapper that prints the table directly and takes the same
    keywords; its `sink` keyword redirects the output, and is called with the table, so pass a
    one-argument function.

```julia
using CSV

simulationsTable(sampling)                                 # one row per simulation
simulationsTable(sampling; remove_constants = false)       # keep the columns that never vary
simulationsTable(sampling; short_names = false)            # raw XML-path column names
simulationsTable(sampling; sort_by = ["Max Time"])         # sort by these columns only (names as printed)
simulationsTable(sampling; sort_ignore = ["Max Time"])     # sort by every other parameter column
simulationsTable(sampling; tags = true)                    # plus a `tag:<key>` column per tag key
simulationsTable(sampling; post_processing = true)         # plus the stored post-processing quantities
printSimulationsTable(sampling)                            # the same table, printed
printSimulationsTable(sampling; sink = CSV.write("runs.csv"))
```

### [Monad-level: `monadsTable`](@id monads_table_section)

!!! tiergloss
    [`monadsTable`](@ref) is the monad-level analogue of [`simulationsTable`](@ref): one row per
    monad (a group of replicate simulations sharing the same parameters) rather than one row per
    simulation. It takes any `AbstractTrial` (e.g. a `Sampling`), a vector of monad IDs, or nothing
    (for all monads). [`printMonadsTable`](@ref) prints it, mirroring
    [`printSimulationsTable`](@ref).

```julia
monadsTable(sampling)                           # one row per monad in the sampling
monadsTable([1, 2, 3]; remove_constants=false)  # by monad ID, keeping constant columns
```

## [Accessing any parameter value](@id get_all_parameter_values_section)

!!! tiergloss
    [`getAllParameterValues`](@ref) returns every terminal element in the XML input files for a set
    of simulations, which must all belong to the same `Sampling` (i.e. use the same input files).
    Column names are the XML paths. `getParameterValue(monad_or_simulation, xml_path)` reads one
    parameter for one `Monad`, `Simulation`, or simulation ID. The location (`:config`,
    `:rulesets_collection`, …) is inferred from the path; on a `Monad` or `Simulation` you may also
    pass it explicitly as a middle argument.

!!! tierwhy
    Because the column names of [`getAllParameterValues`](@ref) *are* the paths, splitting one on
    `/` gives a vector ready to hand to [`DiscreteVariation`](@ref) — it turns "what could I vary
    here?" into a table you can filter, rather than a document you have to read. Everything
    appears, varied or not, so this is also how you check a parameter you never touched.

    `getParameterValue` reads the same way whether or not the parameter was varied: it takes the
    value from the variations database when that column exists and falls back to the base XML file
    when it does not. `"true"`/`"false"` come back as `Bool` and numeric strings as `Float64`;
    anything else is returned as-is.

```julia
df = getAllParameterValues(sampling)
col1 = names(df)[1]                          # the name of the first column
xml_path = split(col1, "/")                  # convert to XML path format
dv = DiscreteVariation(xml_path, [0.0, 1.0]) # vary that parameter

getParameterValue(monad, configPath("max_time"))           # one value, for a Monad or Simulation
getParameterValue(5, configPath("max_time"))               # ...or by simulation ID
getParameterValue(monad, :config, configPath("max_time"))  # with the location given explicitly
```

!!! tierdev
    **Column names are XML paths.** [`columnName`](@ref ModelManager.columnName) joins a path vector
    into the slash-separated string used as a column name, and
    [`columnNameToXMLPath`](@ref ModelManager.columnNameToXMLPath) is its inverse; the `split` above
    is the hand-rolled version of the latter. Both are exported by ModelManager and re-exported here,
    so they need no prefix.

### [Telling identical siblings apart: PCMM's `temp_id` attribute](@id temp_id_columns)

!!! tiergloss
    When several sibling elements share a tag, a column name includes one of their attributes to
    say which sibling it means, as `<tag>:<attribute>:<value>`. When no attribute tells them apart,
    PCMM inserts a positional `temp_id` attribute, `<tag>:temp_id:<index>`, in the *column name
    only* — not in your XML — so the columns stay unique. Find those columns by searching for
    `":temp_id:"`.

!!! tierwhy
    [`getAllParameterValues`](@ref) looks for an attribute whose value differs across the siblings,
    preferring `name`, `ID`, and `id`, and falls back to `temp_id` only when none does. Because
    `temp_id` exists in the column name and nowhere in the input file, such a column is readable
    but not varyable: to vary that parameter, add a real distinguishing attribute to those siblings
    in the input file, then query again.

```julia
df = getAllParameterValues(sampling)
names_with_temp_id = filter(contains(":temp_id:"), names(df))
```
