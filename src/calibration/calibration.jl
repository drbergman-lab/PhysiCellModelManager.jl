using Dates, CSV, Statistics

include("problem.jl")
include("distance.jl")
include("abc.jl")

################## Folder Helpers ##################

"""
    calibrationsDir()

Return the path to the top-level calibrations output directory:
`data/outputs/calibrations/`.
"""
calibrationsDir() = joinpath(dataDir(), "outputs", "calibrations")

"""
    calibrationFolder(calibration_id::Int)

Return the path to the output folder for a given calibration run.
"""
calibrationFolder(calibration_id::Int) = joinpath(calibrationsDir(), string(calibration_id))
calibrationFolder(calibration::Calibration) = calibrationFolder(calibration.id)

"""
    calibrationMonadsCSV(calibration_id::Int)

Return the path to the `monads.csv` file for a given calibration run.
This file is appended to as each pyabc particle is evaluated.
"""
calibrationMonadsCSV(calibration_id::Int) = joinpath(calibrationFolder(calibration_id), "monads.csv")
calibrationMonadsCSV(calibration::Calibration) = calibrationMonadsCSV(calibration.id)

"""
    calibrationABCDBPath(calibration_id::Int)

Return the filesystem path (not the SQLite URI) to the pyabc history database for a
given calibration run.
"""
calibrationABCDBPath(calibration_id::Int) = joinpath(calibrationFolder(calibration_id), "abc_history.db")
calibrationABCDBPath(calibration::Calibration) = calibrationABCDBPath(calibration.id)

################## Database Operations ##################

"""
    createCalibration(method::String; description::String="") → Calibration

Insert a new row into the `calibrations` table and create the output folder.
Returns the resulting [`Calibration`](@ref) object.
"""
function createCalibration(method::String; description::String="")
    dt = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    result = DBInterface.execute(centralDB(),
        """
        INSERT INTO calibrations (datetime, description, method)
        VALUES (:dt, :desc, :method)
        RETURNING calibration_id;
        """,
        (; dt=dt, desc=description, method=method)
    ) |> DataFrame
    calibration_id = result.calibration_id[1]
    mkpath(calibrationFolder(calibration_id))
    return Calibration(calibration_id)
end

"""
    calibrationMonadIDs(calibration::Calibration) → Vector{Int}

Return the monad IDs evaluated during this calibration run, in evaluation order.
"""
function calibrationMonadIDs(calibration::Calibration)
    path_to_csv = calibrationMonadsCSV(calibration)
    return constituentIDs(path_to_csv)
end

