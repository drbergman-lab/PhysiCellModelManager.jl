# [Querying parameters](@id querying_parameters_man)
Read back the parameters that past simulations actually ran with.

| Function | Reads | Best for |
|---|---|---|
| [`simulationsTable`](@ref) | the databases | readability |
| [`getAllParameterValues`](@ref) | every XML value | programmatic access |

## [`simulationsTable`](@id simulations_table_section)

!!! tiergloss
    [`simulationsTable`](@ref) returns a table of simulation data. By default it shows only varied
    values and renames columns to be human-readable. [`printSimulationsTable`](@ref) is a wrapper
    that prints the table directly; its `sink` keyword redirects the output, and is called with the
    table, so pass a one-argument function.

```julia
using CSV

simulationsTable(sampling)                                          # one row per simulation
printSimulationsTable(sampling)                                     # the same table, printed
printSimulationsTable(sampling; sink=df -> CSV.write("runs.csv", df))
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

## [`getAllParameterValues`](@id get_all_parameter_values_section)

!!! tiergloss
    [`getAllParameterValues`](@ref) returns every terminal element in the XML input files for a set
    of simulations, which must all belong to the same `Sampling` (i.e. use the same input files).
    Column names are the XML paths.

!!! tierwhy
    Because the column names *are* the paths, splitting one on `/` gives a vector ready to hand to
    [`DiscreteVariation`](@ref) — which is the point of the function: it turns "what could I vary
    here?" into a table you can filter, rather than a document you have to read. Everything appears,
    varied or not, so this is also how you check a parameter you never touched.

```julia
df = getAllParameterValues(sampling)
col1 = names(df)[1]                          # the name of the first column
xml_path = split(col1, "/")                  # convert to XML path format
dv = DiscreteVariation(xml_path, [0.0, 1.0]) # vary that parameter
```

!!! tierdev
    **Column names are XML paths.** [`columnName`](@ref ModelManager.columnName) joins a path vector
    into the slash-separated string used as a column name, and
    [`columnNameToXMLPath`](@ref ModelManager.columnNameToXMLPath) is its inverse; the `split` above
    is the hand-rolled version of the latter. Both are exported by ModelManager and re-exported here,
    so they need no prefix.

    **One value at a time.** `getParameterValue(M, xp)` reads a single parameter for a monad or
    simulation ID: it takes the value from the variations database when that column exists and falls
    back to the base XML file when it does not, which is what makes an unvaried parameter readable
    the same way as a varied one. The location is inferred from the [`XMLPath`](@ref) unless you pass
    it explicitly as a middle argument. `"true"`/`"false"` come back as `Bool` and numeric strings as
    `Float64`; anything else is returned as-is. [`getAllParameterValues`](@ref) is the bulk form and
    is what user code should normally call.

### Columns that carry an attribute

!!! tiergloss
    Some column names include what look like attributes, to tell apart several children with the
    same tag. Those spelled `<tag>:temp_id:<index>` are the ones you cannot vary as they stand.
    Find them by searching for `":temp_id:"`.

!!! tierwhy
    Identically tagged siblings need something in the path to tell them apart, so
    [`getAllParameterValues`](@ref) looks for an attribute that distinguishes them, preferring
    `name`, `ID`, and `id`. When no attribute does, it invents a positional one so the column names
    stay unique — but it does **not** write that attribute into your XML. A `:temp_id:` column is
    therefore readable and not varyable: to vary such a parameter, add a real identifying attribute
    to those siblings in the input file yourself, then query again.

```julia
df = getAllParameterValues(sampling)
names_with_temp_id = filter(contains(":temp_id:"), names(df))
```
