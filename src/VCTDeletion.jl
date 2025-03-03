using Dates

export deleteSimulation, deleteSimulations, deleteSimulationsByStatus, resetDatabase

"""
    deleteSimulations(simulation_ids::AbstractVector{<:Union{Integer,Missing}}; delete_supers::Bool=true, and_constraints::String="")

Deletes the simulations with the input IDs from the database and from the `data/outputs/simulations` folder.

Works with any vector of integers or a single integer.
If `delete_supers` is `true`, it will also delete any monads, samplings, and trials that no longer have any simulations associated with them.
It is recommended to leave this to `true` to keep the database clean.
The `and_constraints` argument allows for additional SQLite conditions to be added to the `WHERE` clause of the SQLite query. Use this only after inspecting the `simulations` table in the `data/vct.db` database.
    Note: `deleteSimulation` is an alias for `deleteSimulations`.

# Examples
```
deleteSimulations(1:3)
deleteSimulations(4)
deleteSimulations(1:100; and_constraints="AND config_id = 1") # delete simulations with IDs 1 to 100 that have config_id = 1
```
"""
function deleteSimulations(simulation_ids::AbstractVector{<:Union{Integer,Missing}}; delete_supers::Bool=true, and_constraints::String="")
    filter!(x -> !ismissing(x), simulation_ids)
    where_stmt = "WHERE simulation_id IN ($(join(simulation_ids,","))) $(and_constraints)"
    sim_df = constructSelectQuery("simulations", where_stmt) |> queryToDataFrame
    simulation_ids = sim_df.simulation_id #! update based on the constraints added
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")

    for row in eachrow(sim_df)
        rm_hpc_safe(outputFolder("simulation", row.simulation_id); force=true, recursive=true)

        for (location, location_dict) in pairs(inputs_dict)
            if !any(location_dict["varied"])
                continue
            end
            id_name = locationIDName(location)
            row_id = row[id_name]
            folder = inputFolderName(location, row_id)
            result_df = constructSelectQuery(
                "simulations",
                "WHERE $(id_name) = $(row_id) AND $(locationVarIDName(location)) = $(row[locationVarIDName(location)])";
                selection="COUNT(*)"
            ) |> queryToDataFrame
            if result_df.var"COUNT(*)"[1] == 0
                rm_hpc_safe(joinpath(locationPath(location, folder), variationsTableName(location), "$(location)_variation_$(row[locationVarIDName(location)]).xml"); force=true)
            end
        end
    end

    if !delete_supers
        return nothing
    end

    monad_ids = constructSelectQuery("monads"; selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
    monad_ids_to_delete = Int[]
    for monad_id in monad_ids
        monad_simulation_ids = readMonadSimulationIDs(monad_id)
        if !any(x -> x in simulation_ids, monad_simulation_ids) #! if none of the monad simulation ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in simulation_ids), monad_simulation_ids)
        if isempty(monad_simulation_ids)
            push!(monad_ids_to_delete, monad_id)
        else
            recordSimulationIDs(monad_id, monad_simulation_ids)
        end
    end
    if !isempty(monad_ids_to_delete)
        deleteMonad(monad_ids_to_delete; delete_subs=false, delete_supers=true)
    end
    return nothing
end

deleteSimulations(simulation_id::Int; delete_supers::Bool=true, and_constraints::String="") = deleteSimulations([simulation_id]; delete_supers=delete_supers, and_constraints=and_constraints)
deleteSimulation = deleteSimulations #! alias
deleteAllSimulations(; delete_supers::Bool=true, and_constraints::String="") = getSimulationIDs() |> x -> deleteSimulations(x; delete_supers=delete_supers, and_constraints=and_constraints)

function deleteMonad(monad_ids::AbstractVector{<:Integer}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM monads WHERE monad_id IN ($(join(monad_ids,",")));")
    simulation_ids_to_delete = Int[]
    for monad_id in monad_ids
        if delete_subs
            append!(simulation_ids_to_delete, readMonadSimulationIDs(monad_id))
        end
        rm_hpc_safe(outputFolder("monad", monad_id); force=true, recursive=true)
    end
    if !isempty(simulation_ids_to_delete)
        deleteSimulations(simulation_ids_to_delete; delete_supers=false)
    end

    if !delete_supers
        return nothing
    end

    sampling_ids = constructSelectQuery("samplings"; selection="sampling_id") |> queryToDataFrame |> x -> x.sampling_id
    sampling_ids_to_delete = Int[]
    for sampling_id in sampling_ids
        sampling_monad_ids = readSamplingMonadIDs(sampling_id)
        if !any(x -> x in monad_ids, sampling_monad_ids) #! if none of the sampling monad ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in monad_ids), sampling_monad_ids)
        if isempty(sampling_monad_ids)
            push!(sampling_ids_to_delete, sampling_id)
        else
            recordMonadIDs(sampling_id, sampling_monad_ids)
        end
    end
    if !isempty(sampling_ids_to_delete)
        deleteSampling(sampling_ids_to_delete; delete_subs=false, delete_supers=true)
    end
    return nothing
end

deleteMonad(monad_id::Int; delete_subs::Bool=true, delete_supers::Bool=true) = deleteMonad([monad_id]; delete_subs=delete_subs, delete_supers=delete_supers)

function deleteSampling(sampling_ids::AbstractVector{<:Integer}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM samplings WHERE sampling_id IN ($(join(sampling_ids,",")));")
    monad_ids_to_delete = Int[]
    for sampling_id in sampling_ids
        if delete_subs
            append!(monad_ids_to_delete, readSamplingMonadIDs(sampling_id))
        end
        rm_hpc_safe(outputFolder("sampling", sampling_id); force=true, recursive=true)
    end
    if !isempty(monad_ids_to_delete)
        all_sampling_ids = constructSelectQuery("samplings"; selection="sampling_id") |> queryToDataFrame |> x -> x.sampling_id
        for sampling_id in all_sampling_ids
            if sampling_id in sampling_ids
                continue #! skip the samplings to be deleted (we want to delete their monads)
            end
            #! this is then a sampling that we are not deleting, do not delete their monads!!
            monad_ids = readSamplingMonadIDs(sampling_id)
            filter!(x -> !(x in monad_ids), monad_ids_to_delete) #! if a monad to delete is in the sampling to keep, then do not delete it!! (or more in line with logic here: if a monad marked for deletion is not in this sampling we are keeping, then leave it in the deletion list)
        end
        deleteMonad(monad_ids_to_delete; delete_subs=true, delete_supers=false)
    end

    if !delete_supers
        return nothing
    end

    trial_ids = constructSelectQuery("trials"; selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
    trial_ids_to_delete = Int[]
    for trial_id in trial_ids
        trial_sampling_ids = readTrialSamplingIDs(trial_id)
        if !any(x -> x in sampling_ids, trial_sampling_ids) #! if none of the trial sampling ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in sampling_ids), trial_sampling_ids)
        if isempty(trial_sampling_ids)
            push!(trial_ids_to_delete, trial_id)
        else
            recordSamplingIDs(trial_id, trial_sampling_ids)
        end
    end
    if !isempty(trial_ids_to_delete)
        deleteTrial(trial_ids_to_delete; delete_subs=false)
    end
    return nothing
end

deleteSampling(sampling_id::Int; delete_subs::Bool=true, delete_supers::Bool=true) = deleteSampling([sampling_id]; delete_subs=delete_subs, delete_supers=delete_supers)

function deleteTrial(trial_ids::AbstractVector{<:Integer}; delete_subs::Bool=true)
    DBInterface.execute(db,"DELETE FROM trials WHERE trial_id IN ($(join(trial_ids,",")));")
    sampling_ids_to_delete = Int[]
    for trial_id in trial_ids
        if delete_subs
            append!(sampling_ids_to_delete, readTrialSamplingIDs(trial_id))
        end
        rm_hpc_safe(outputFolder("trial", trial_id); force=true, recursive=true)
    end
    if !isempty(sampling_ids_to_delete)
        all_trial_ids = constructSelectQuery("trials"; selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
        for trial_id in all_trial_ids
            if trial_id in trial_ids
                continue #! skip the trials to be deleted (we want to delete their samplings)
            end
            #! this is then a trial that we are not deleting, do not delete their samplings!!
            sampling_ids = readTrialSamplingIDs(trial_id)
            filter!(x -> !(x in sampling_ids), sampling_ids_to_delete) #! if a sampling to delete is in the trial to keep, then do not delete it!! (or more in line with logic here: if a sampling marked for deletion is not in this trial we are keeping, then leave it in the deletion list)
        end
        deleteSampling(sampling_ids_to_delete; delete_subs=true, delete_supers=false)
    end
    return nothing
end

deleteTrial(trial_id::Int; delete_subs::Bool=true) = deleteTrial([trial_id]; delete_subs=delete_subs)

"""
    resetDatabase()

Reset the database (after user confirmation) by deleting all simulations, monads, samplings, and trials.

All the base inputs files will be kept, so previously run scripts should still work as expected.
If the user aborts the reset, the user will then be asked if they want to continue with the script.

# Keyword Arguments
- `force_reset::Bool`: If `true`, skips the user confirmation prompt. Default is `false`.
- `force_continue::Bool`: If `true`, skips the user confirmation prompt for continuing with the script after aborting the reset. Default is `false`.
"""
function resetDatabase(; force_reset::Bool=false, force_continue::Bool=false)
    if !force_reset
        #! prompt user to confirm
        println("Are you sure you want to reset the database? (y/n)")
        response = readline()
        if response != "y" #! make user be very specific about resetting
            println("\tYou entered '$response'.\n\tResetting the database has been cancelled.")
            if !force_continue
                println("\nDo you want to continue with the script? (y/n)")
                response = readline()
                if response != "y" #! make user be very specific about continuing
                    println("\tYou entered '$response'.\n\tThe script has been cancelled.")
                    error("Script cancelled.")
                end
                println("You entered '$response'.\n\tThe script will continue.")
            end
            return
        end
    end
    for folder in ["simulations", "monads", "samplings", "trials"]
        rm_hpc_safe(joinpath(data_dir, "outputs", folder); force=true, recursive=true)
    end

    for (location, location_dict) in pairs(inputs_dict)
        if !any(location_dict["varied"])
            continue
        end
        path_to_location = locationPath(location)
        for folder in (readdir(path_to_location, sort=false, join=true) |> filter(x->isdir(x)))
            resetFolder(location, folder)
        end
        folders = constructSelectQuery(tableName(location); selection="folder_name") |> queryToDataFrame |> x -> x.folder_name
        for folder in folders
            resetFolder(location, joinpath(path_to_location, folder))
        end
    end

    for custom_code_folder in (readdir(locationPath(:custom_code), sort=false, join=true) |> filter(x->isdir(x)))
        files = [baseToExecutable("project"), "compilation.log", "compilation.err", "macros.txt"]
        for file in files
            rm_hpc_safe(joinpath(custom_code_folder, file); force=true)
        end
    end

    custom_code_folders = constructSelectQuery("custom_codes"; selection="folder_name") |> queryToDataFrame |> x -> x.folder_name
    for custom_code_folder in custom_code_folders
        rm_hpc_safe(joinpath(locationPath(:custom_code, custom_code_folder), baseToExecutable("project")); force=true)
    end

    if db.file == ":memory:"
        initializeDatabase()
    else
        rm_hpc_safe("$(db.file)"; force=true)
        initializeDatabase("$(db.file)")
    end
    return nothing
end

function resetFolder(location::Symbol, folder::String)
    inputs_dict_entry = inputs_dict[location]
    path_to_folder = locationPath(location, folder)
    if !isdir(path_to_folder)
        return
    end
    if inputs_dict_entry["basename"] isa Vector
        #! keep the most elementary of these and remove the rest
        ind = findfirst(x -> joinpath(path_to_folder, x) |> isfile, inputs_dict_entry["basename"])
        if isnothing(ind)
            return #! probably should not end up here, but it could happen if a location folder was created but never populated with the base file
        end
        for base_file in inputs_dict_entry["basename"][ind+1:end]
            rm_hpc_safe(joinpath(path_to_folder, base_file); force=true)
        end
    end
    rm_hpc_safe(joinpath(path_to_folder, "$(location)_variations.db"); force=true)
    rm_hpc_safe(joinpath(path_to_folder, variationsTableName(location)); force=true, recursive=true)
end

"""
    deleteSimulationsByStatus(status_codes_to_delete::Vector{String}=["Failed"]; user_check::Bool=true)

Delete simulations from the database based on their status codes.

The list of possible status codes is: "Not Started", "Queued", "Running", "Completed", "Failed".

# Arguments
- `status_codes_to_delete::Vector{String}`: A vector of status codes for which simulations should be deleted. Default is `["Failed"]`.
- `user_check::Bool`: If `true`, prompts the user for confirmation before deleting simulations. Default is `true`.
"""
function deleteSimulationsByStatus(status_codes_to_delete::Vector{String}=["Failed"]; user_check::Bool=true)
    df = """
        SELECT simulations.simulation_id, simulations.status_code_id, status_codes.status_code
        FROM simulations
        JOIN status_codes
        ON simulations.status_code_id = status_codes.status_code_id;
    """ |> queryToDataFrame

    for status_code in status_codes_to_delete
        simulation_ids = df.simulation_id[df.status_code .== status_code]
        if isempty(simulation_ids)
            continue
        end
        if user_check
            println("Are you sure you want to delete all $(length(simulation_ids)) simulations with status code '$status_code'? (y/n)")
            response = readline()
            println("You entered '$response'.")
            if response != "y" #! make user be very specific about resetting
                println("\tDeleting simulations with status code '$status_code' has been cancelled.")
                continue
            end
        end
        println("\tDeleting $(length(simulation_ids)) simulations with status code '$status_code'.")
        deleteSimulations(simulation_ids)
    end
end

"""
    eraseSimulationID(simulation_id::Int[; monad_id::Union{Missing,Int}=missing])

Erase a simulation ID from the `simulations.csv` file of the monad it belongs to.

If `monad_id` is not provided, the function will infer it from the simulation ID.
If the monad contains only the given simulation ID, the monad will be deleted.
This is used when running simulations if they error so that the monads no longer rely on them, but the simulation output can still be checked.
"""
function eraseSimulationID(simulation_id::Int; monad_id::Union{Missing,Int}=missing)
    if ismissing(monad_id)
        query = constructSelectQuery("simulations", "WHERE simulation_id = $(simulation_id)")
        df = queryToDataFrame(query)
        all_id_features = [locationIDName(loc) for loc in project_locations.varied] #! project_locations.varied is a Tuple, so doing locationIDName.(project_locations.varied) makes a Tuple, not a Vector
        add_id_values = [df[1, id_feature] for id_feature in all_id_features]
        all_variation_id_features = [locationVarIDName(loc) for loc in project_locations.varied] #! project_locations.varied is a Tuple, so doing locationVarIDName.(project_locations.varied) makes a Tuple, not a Vector
        all_variation_id_values = [df[1, variation_id_feature] for variation_id_feature in all_variation_id_features]
        all_features = [all_id_features; all_variation_id_features]
        all_values = [add_id_values; all_variation_id_values]
        where_stmt = "WHERE ($(join(all_features, ", "))) = ($(join(all_values, ", ")))"
        query = constructSelectQuery("monads", where_stmt; selection="monad_id")
        df = queryToDataFrame(query)
        monad_id = df.monad_id[1]
    end
    simulation_ids = readMonadSimulationIDs(monad_id)
    index = findfirst(x->x==simulation_id, simulation_ids)
    if isnothing(index)
        return #! maybe this could happen? so let's check just in case
    end
    if length(simulation_ids)==1
        #! then this was the only simulation in this monad; delete the monad and any samplings, etc. that depend on it
        #! do not delete the given simulation from the database so that we can check the output files
        deleteMonad(monad_id; delete_subs=false, delete_supers=true)
        return
    end
    deleteat!(simulation_ids, index)
    recordSimulationIDs(monad_id, simulation_ids)
end

function rm_hpc_safe(path::String; force::Bool=false, recursive::Bool=false)
    if !run_on_hpc
        rm(path; force=force, recursive=recursive)
        return
    end
    if !ispath(path)
        return
    end
    #! NFS filesystem could stop the deletion by putting a lock on the folder or something
    src = path
    path_rel_to_data = replace(path, "$(data_dir)/" => "")
    date_time = Dates.format(now(),"yymmdd")
    initial_dest = joinpath(data_dir, ".trash", "data-$(date_time)", path_rel_to_data)
    main_path, file_ext = splitext(initial_dest)
    suffix = ""
    path_to_dest(main_path, suffix, file_ext) = suffix == "" ? "$(main_path)$(file_ext)" : "$(main_path)-$(suffix)$(file_ext)"
    while ispath(path_to_dest(main_path, suffix, file_ext))
        suffix = suffix == "" ? "1" : string(parse(Int, suffix) + 1)
    end
    dest = path_to_dest(main_path, suffix, file_ext)
    mkpath(dirname(dest))
    mv(src, dest; force=force)
end