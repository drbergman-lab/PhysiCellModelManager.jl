using PhysiCellCellCreator

@compat public createICCellXMLTemplate

"""
    createICCellXMLTemplate(folder::String)

Create folder with a template XML file for IC cells.

See the [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) documentation for more information on IC cells and how this function works outside of PhysiCellModelManager.jl.
This PhysiCellModelManager.jl function runs the `createICCellXMLTemplate` function from PhysiCellCellCreator.jl and then updates the database.
Furthermore, the folder can be passed in just as the name of the folder located in `data/inputs/ics/cells/` rather than the full path.

This functionality is run outside of a PhysiCell runtime.
It will not work in PhysiCell!
This function creates a template XML file for IC cells, showing all the current functionality of this initialization scheme.
It uses the cell type \"default\".
Create ICs for more cell types by copying the `cell_patches` element.
The `ID` attribute in `patch` elements is there exactly to allow variations to target specific patches.
Manually maintain these or you will not be able to vary specific patches effectively.

Each time a simulation is run that is using a cells.xml file, a new CSV file will be created, drawing randomly from the patches defined in the XML file.
These will all be stored with `data/inputs/ics/cells/folder/ic_cell_variations` as `ic_cell_variation_#_s#.csv` where the first `#` is the variation ID associated with variation on the XML file and the second `#` is the simulation ID.
Importantly, no two simulations will use the same CSV file.
"""
function createICCellXMLTemplate(folder::String)
    if length(splitpath(folder)) == 1
        @assert pcmm_globals.initialized "Must supply a full path to the folder if the database is not initialized."
        #! then the folder is just the name of the ics/cells/folder folder
        path_to_folder = locationPath(:ic_cell, folder)
    else
        path_to_folder = folder
        folder = splitpath(folder)[end]
    end

    if isfile(joinpath(path_to_folder, "cells.xml"))
        println("cells.xml already exists in $path_to_folder. Skipping.")
        return folder
    end

    PhysiCellCellCreator.createICCellXMLTemplate(path_to_folder)

    #! finish by adding this folder to the database
    if pcmm_globals.initialized
        insertFolder(:ic_cell, folder)
    end

    return folder
end