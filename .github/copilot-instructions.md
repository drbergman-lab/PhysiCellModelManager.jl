# PhysiCellModelManager.jl Copilot Instructions

## Repository Overview

**PhysiCellModelManager.jl** is a Julia package that manages PhysiCell simulations (a C++ multicellular modeling framework). It provides a high-level interface for parameterizing, executing, compiling, and analyzing large-scale simulation studies including parameter sweeps and sensitivity analysis. The package handles C++ compilation, SQLite databases, and integrates with high-performance computing environments.

**Repository Size**: ~30 Julia source files, comprehensive test suite (30+ test files), extensive documentation
**Languages**: Julia (primary) with C++ compilation components
**Target Runtime**: Julia ≥1.6.7, requires g++ compiler for PhysiCell builds
**Key Dependencies**: SQLite, DataFrames, LightXML, PhysiCell C++ framework

## Build and Validation Process

### Environment Setup (ALWAYS REQUIRED)
```bash
# 1. Add required registry (mandatory before any other steps)
julia -e 'import Pkg; Pkg.Registry.add(Pkg.RegistrySpec(url="https://github.com/drbergman-lab/BergmanLabRegistry"))'

# 2. Activate project and install dependencies
julia -e 'import Pkg; Pkg.activate("."); Pkg.instantiate()'
```

### Testing (Commands verified to work)
```bash
# Run full test suite (takes 10-60 minutes)
export PCMM_NUM_PARALLEL_SIMS=8
export PHYSICELL_CPP=g++
julia --project=. -e 'import Pkg; Pkg.test()'

# Run specific test files (tests must run in order defined in test/runtests.jl)
julia --project=. test/runtests.jl
```

### Environment Variables (Required for Full Functionality)
- `PHYSICELL_CPP=g++` - C++ compiler for PhysiCell builds (defaults to g++)  
- `PCMM_NUM_PARALLEL_SIMS=8` - Number of parallel simulations
- `PCMM_PYTHON_PATH=/usr/bin/python3` - Python path for PhysiCell Studio integration
- `PCMM_STUDIO_PATH=/path/to/PhysiCell-Studio` - PhysiCell Studio directory path
- `PCMM_IMAGEMAGICK_PATH` and `PCMM_FFMPEG_PATH` - Paths for visualization tools

### C++ Compilation Process
PhysiCellModelManager.jl automatically handles C++ compilation via:
- Uses `make -j 8 CC=$PHYSICELL_CPP` with custom CFLAGS
- Compiles PhysiCell projects in temporary directories
- Handles libRoadrunner setup for intracellular models
- Compilation logs saved to `data/inputs/custom_codes/*/compilation.log`

### Known Build Issues and Workarounds
- **Registry Issue**: Must add BergmanLabRegistry before instantiation or tests will fail
- **Dependency Conflicts**: If Pkg.instantiate() fails, clear ~/.julia/compiled and retry
- **C++ Compilation**: Requires g++ (or g++-14 on macOS), fails without proper compiler setup
- **HPC Environments**: Set `PCMM_NUM_PARALLEL_SIMS` appropriately for system resources

## Project Architecture and Layout

### Core Directory Structure
```
src/                          # Main Julia source code
├── PhysiCellModelManager.jl  # Main module file, exports, initialization
├── compilation.jl            # C++ build system, make integration
├── runner.jl                 # Simulation execution engine  
├── database.jl               # SQLite database management
├── loader.jl                 # Data loading and analysis tools
├── creation.jl               # Project setup (createProject function)
└── analysis/                 # Analysis tools and plotting

test/                         # Test suite (run in specific order)
├── runtests.jl              # Test runner with ordered test list
└── test-scripts/            # Individual test files

docs/                        # Documentation (Documenter.jl)
├── src/man/getting_started.md  # Primary user guide
└── src/man/best_practices.md    # Suggested ways to use

.github/workflows/CI.yml     # CI pipeline: Ubuntu/macOS, Julia LTS/1/pre
Project.toml                 # Package dependencies and metadata
```

### Key Architectural Components
- **Trial Hierarchy**: `Trial > Sampling > Monad > Simulation` for organizing large studies
- **Input Management**: `InputFolders` struct manages configs, custom code, rules, initial conditions
- **Database**: SQLite central database tracks all simulations to avoid reruns
- **Compilation System**: Automatic C++ compilation with PhysiCell integration
- **HPC Integration**: Built-in parallel execution and cluster job management

### Configuration Files
- `Project.toml` - Julia package dependencies and compatibility
- `.github/workflows/CI.yml` - CI/CD configuration for multiple platforms
- `data/inputs.toml` - Project-specific input folder configuration (created by user)

### Typical Project Structure (Created by `createProject()`)
```
MyProject/
├── PhysiCell/               # PhysiCell C++ framework (submodule)
├── data/                    # Managed by PhysiCellModelManager.jl
│   ├── inputs/              # Input files organized by type
│   ├── outputs/             # Simulation results
│   └── pcmm.db              # SQLite tracking database
└── scripts/
    └── GenerateData.jl      # Main simulation script template
```

## Validation and CI/CD Process

### GitHub Actions Workflow
- **Platforms**: Ubuntu (primary), macOS-latest (ARM64)
- **Julia Versions**: LTS, stable (1), pre-release
- **Compilers**: g++ (Linux), g++-14 (macOS)
- **Special Requirements**: ImageMagick, FFmpeg, libRoadrunner dependencies

### Pre-commit Validation Steps
1. **Registry Setup**: Verify BergmanLabRegistry is accessible
2. **Dependency Resolution**: Ensure all packages in Project.toml resolve
3. **Test Suite**: Run full test suite with proper environment variables
4. **C++ Compilation**: Validate g++ compilation works for sample projects
5. **Documentation**: Run doctests and build documentation

### Common Failure Points
- Missing BergmanLabRegistry causes dependency resolution failures
- C++ compiler issues on different platforms (especially macOS ARM64)
- Environment variables not set correctly for parallel execution
- PhysiCell submodule not initialized properly in new projects

## Quick Development Workflow

1. **Setup**: Add BergmanLabRegistry, activate project, instantiate packages
2. **Create Test Project**: `julia -e 'using PhysiCellModelManager; createProject("test_project")'`
3. **Initialize**: `julia -e 'using PhysiCellModelManager; initializeModelManager()'`
4. **Run Tests**: Export required environment variables and run test suite
5. **Validate Changes**: Ensure no regressions in C++ compilation or database operations

**Trust these instructions and only search for additional information if specific commands fail or requirements are unclear.**
