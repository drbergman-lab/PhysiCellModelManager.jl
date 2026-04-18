#! PhysiCell-specific sensitivity analysis additions.
#!
#! All generic GSA infrastructure (MOAT, Sobolʼ, RBD, runSensitivitySampling,
#! calculateGSA!, recordSensitivityScheme, evaluateFunctionOnSampling, etc.) is
#! now defined in ModelManager/src/sensitivity.jl.
#!
#! SobolPCMM (PCMM backward-compat alias for Sobolʼ) is defined in
#! PhysiCellModelManager.jl as `const SobolPCMM = SobolMM`.
#!
#! This file is intentionally minimal.  Add PhysiCell-specific GSA extensions here
#! if needed in the future.
