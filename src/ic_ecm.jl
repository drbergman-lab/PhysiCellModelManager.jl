using PhysiCellECMCreator

@compat public createICECMXMLTemplate

"""
    createICECMXMLTemplate(folder::String)

Create folder with a template XML file for IC ECM.

See the [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl) documentation for more information on IC ECM and how this function works outside of PhysiCellModelManager.jl.
This PhysiCellModelManager.jl function runs the `createICECMXMLTemplate` function from PhysiCellECMCreator.jl and then updates the database.
Furthermore, the folder can be passed in just as the name of the folder located in `data/inputs/ics/ecms/` rather than the full path.

This functionality is run outside of a PhysiCell runtime.
It will not work in PhysiCell!
This function creates a template XML file for IC ECM, showing all the current functionality of this initialization scheme.
The `ID` attribute in `patch` elements is there to allow variations to target specific patches within a layer.
Manually maintain these or you will not be able to vary specific patches effectively.

Each time a simulation is run that is using a ecm.xml file, a new CSV file will be created.
These will all be stored with `data/inputs/ics/ecms/folder/ic_ecm_variations` as `ic_ecm_variation_#_s#.csv` where the first `#` is the variation ID associated with variation on the XML file and the second `#` is the simulation ID.
Importantly, no two simulations will use the same CSV file.
"""
function createICECMXMLTemplate(folder::String)
    if length(splitpath(folder)) == 1
        @assert isInitialized() "Must supply a full path to the folder if the database is not initialized."
        #! then the folder is just the name of the ics/ecms/folder folder
        path_to_folder = locationPath(:ic_ecm, folder)
    else
        path_to_folder = folder
        folder = splitpath(folder)[end]
    end

    if isfile(joinpath(path_to_folder, "ecm.xml"))
        println("ecm.xml already exists in $path_to_folder. Skipping.")
        return folder
    end

    PhysiCellECMCreator.createICECMXMLTemplate(path_to_folder)

    #! finish by adding this folder to the database
    if isInitialized()
        insertFolder(:ic_ecm, folder)
    end

    return folder
end