# Querying parameters
Access the parameters of past simulations two ways:
- [`simulationsTable`](@ref) — reads the databases; best for readability.
- [`getAllParameterValues`](@ref) — reads every XML value; best for programmatic access.

## [`simulationsTable`](@ref)
[`simulationsTable`](@ref) returns a table of simulation data. By default it shows only varied values and renames columns to be human-readable.

[`printSimulationsTable`](@ref) is a wrapper that prints the table directly. Use the `sink` keyword argument to redirect the output, e.g. to a file.

### Monad-level: [`monadsTable`](@ref)
[`monadsTable`](@ref) is the monad-level analogue of [`simulationsTable`](@ref): it returns one row per monad (a group of replicate simulations sharing the same parameters) rather than one row per simulation. Pass it any `AbstractTrial` (e.g. a `Sampling`), a vector of monad IDs, or nothing (for all monads):

```julia
monadsTable(sampling)                      # one row per monad in the sampling
monadsTable([1, 2, 3]; remove_constants=false)  # by monad ID, keeping constant columns
```

[`printMonadsTable`](@ref) prints the table directly, mirroring [`printSimulationsTable`](@ref).

## [`getAllParameterValues`](@ref)
[`getAllParameterValues`](@ref) returns every terminal element in the XML input files for a set of simulations, which must all belong to the same `Sampling` (i.e. use the same input files). Column names are the XML paths, so splitting one on `/` gives a path ready for [`DiscreteVariation`](@ref):

```julia
df = getAllParameterValues(sampling)
col1 = names(df)[1] # get the name of the first column
xml_path = split(col1, "/") # convert to XML path format
dv = DiscreteVariation(xml_path, [0.0, 1.0]) # create a discrete variation using this parameter
```

The internal functions [`PhysiCellModelManager.columnName`](@ref) and [`PhysiCellModelManager.columnNameToXMLPath`](@ref) can also be used to convert between the column names and XML paths.

!!! note
    The XML paths returned by [`getAllParameterValues`](@ref) as column names **may** include what look like attributes to distinguish between multiple children with the same tag. Find these by searching for column names containing `":temp_id:"`:

    ```julia
    df = getAllParameterValues(sampling)
    names_with_temp_id = filter(contains(":temp_id:"), names(df))
    ```