# Querying parameters
It is often helpful to access the parameters used in a simulation after it has been run.
There are two main ways to achieve this:
- [`simulationsTable`](@ref) uses the databases and excels at user-readability
- [`getAllParameterValues`](@ref) uses all values in the XMLs, exceling at programmatic access

## [`simulationsTable`](@ref)
The function [`simulationsTable`](@ref) can be used to print a table of simulation data.
This function, by default, only prints varied values and does some renaming to make the column names more human-readable.

The function [`printSimulationsTable`](@ref) is a convenience wrapper around [`simulationsTable`](@ref) that prints the table directly.
Use the `sink` keyword argument to, for example, redirect the output to a file instead of the console.

## [`getAllParameterValues`](@ref)
The function [`getAllParameterValues`](@ref) can be used to programmatically access all the terminal elements in the XML input files for a given set of simulations.
The simulations must all belong to the same `Sampling`, i.e. use the same input files.
The column names are the XML paths to the parameters, meaning they can be converted into the format for creating a [`DiscreteVariation`](@ref), for example, by splitting on `/`.

```julia
df = getAllParameterValues(sampling)
col1 = names(df)[1] # get the name of the first column
xml_path = split(col1, "/") # convert to XML path format
dv = DiscreteVariation(xml_path, [0.0, 1.0]) # create a discrete variation using this parameter
```

The internal functions [`PhysiCellModelManager.columnName`](@ref) and [`PhysiCellModelManager.columnNameToXMLPath`](@ref) can also be used to convert between the column names and XML paths.

> Note: The XML paths returned by [`getAllParameterValues`](@ref) as column names **may** include what look like attributes to distinguish between multiple children with the same tag.
> These can be found by searching for column names with `":temp_id:"` in them:

```julia
df = getAllParameterValues(sampling)
names_with_temp_id = filter(contains(":temp_id:"), names(df))
```