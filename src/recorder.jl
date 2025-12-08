"""
    recordConstituentIDs(T::Type{<:AbstractTrial}, id::Int, ids::Array{Int})
    recordConstituentIDs(T::AbstractTrial, ids::Array{Int})

Record the IDs of the constituents of an [`AbstractTrial`](@ref) object in a CSV file.
"""
function recordConstituentIDs(T::Type{<:AbstractTrial}, id::Int, ids::Array{Int})
    path_to_folder = trialFolder(T, id)
    mkpath(path_to_folder)
    path_to_csv = joinpath(path_to_folder, constituentTypeFilename(T))
    lines_table = compressIDs(ids)
    CSV.write(path_to_csv, lines_table; header=false)
end

recordConstituentIDs(T::AbstractTrial, ids::Array{Int}) = recordConstituentIDs(typeof(T), T.id, ids)

################## Compression Functions ##################

"""
    compressIDs(ids::AbstractArray{Int})

Compress a list of IDs into a more compact representation by grouping consecutive IDs together.
"""
function compressIDs(ids::AbstractArray{Int})
    ids = ids |> vec |> unique |> sort
    lines = String[]
    while !isempty(ids) #! while there are still ids to compress
        if length(ids) == 1 #! if there's only one id left
            next_line = string(ids[1]) #! just add it to the list
            popfirst!(ids) #! and remove it from the list of ids
        else #! if there's more than one id left
            I = findfirst(diff(ids) .!= 1) #! find the first index where the difference between consecutive ids is greater than 1
            I = isnothing(I) ? length(ids) : I #! if none found, then all the diffs are 1 so we want to take the entire list
            if I > 1 #! if compressing multiple ids
                next_line = "$(ids[1]):$(ids[I])" #! add the first and last id separated by a colon
                ids = ids[I+1:end] #! remove the ids that were just compressed
            else #! if only compressing one id
                next_line = string(ids[1]) #! just add the id to the list
                popfirst!(ids) #! and remove it from the list of ids
            end
        end
        push!(lines, next_line) #! add the compressed id(s) to the list of lines
    end
    return Tables.table(lines)
end
