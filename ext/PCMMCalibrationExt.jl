module PCMMCalibrationExt

using PhysiCellModelManager
using PythonCall

function __init__()
    Base.depwarn(
        """
        The PythonCall/pyabc backend for PhysiCellModelManager calibration is deprecated.
        A native Julia ABC-SMC implementation (`runABC`) is now the default — no Python
        runtime is required. Loading `PythonCall` alongside `PhysiCellModelManager` no
        longer affects calibration behavior.

        To use the native implementation:
            using PhysiCellModelManager
            result = runABC(problem; population_size=100, max_nr_populations=5)
        """,
        :PCMMCalibrationExt
    )
end

end # module PCMMCalibrationExt
