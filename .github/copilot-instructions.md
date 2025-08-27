# PhysiCellModelManager.jl Development Instructions

**CRITICAL: Always follow these instructions completely before attempting any other approaches. Only fallback to additional search and context gathering if the information in these instructions is incomplete or found to be in error.**

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Bootstrap, Build, and Test the Repository

**CRITICAL - Set proper timeouts for ALL build/test commands:**

1. **Install Julia and Dependencies** (5-10 minutes):
   ```bash
   # Install Julia 1.6.7+ (compatible versions: 1.6.7 to 1.11.6+)
   curl -fsSL https://install.julialang.org | sh
   
   # Add required registries
   julia -e 'import Pkg; Pkg.Registry.add("General"); Pkg.Registry.add(Pkg.RegistrySpec(url="https://github.com/drbergman-lab/BergmanLabRegistry.git"))'
   ```

2. **System Dependencies** (Ubuntu/Linux):
   ```bash
   # Install required system packages for PhysiCell compilation
   sudo apt-get update
   sudo apt-get install build-essential g++ make python3
   
   # Install libRoadRunner dependencies (required for intracellular models)
   wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
   sudo apt-get install -y ./libtinfo5_6.3-2ubuntu0.1_amd64.deb
   
   # Optional: Install ImageMagick and FFmpeg for movie generation
   sudo apt-get install imagemagick ffmpeg
   ```

3. **Project Setup and Build** -- **NEVER CANCEL: Build takes 15-45 minutes. Set timeout to 60+ minutes.**
   ```bash
   cd /path/to/PhysiCellModelManager.jl
   
   # Instantiate dependencies (can take 15-30 minutes due to C++ compilation)
   julia --project=. -e 'import Pkg; Pkg.instantiate()'
   ```
   **WARNING**: The build process compiles PhysiCell C++ code and may appear to hang. DO NOT CANCEL.

4. **Run Tests** -- **NEVER CANCEL: Full test suite takes 30-60 minutes. Set timeout to 90+ minutes.**
   ```bash
   # Set parallel simulations for faster testing
   export PCMM_NUM_PARALLEL_SIMS=8
   export PHYSICELL_CPP=g++
   
   # Run all tests
   julia --project=. -e 'import Pkg; Pkg.test()'
   ```

### Working with the Package

1. **Basic Package Loading**:
   ```julia
   using PhysiCellModelManager
   ```

2. **Create a New Project**:
   ```julia
   # Creates directory structure with PhysiCell, data, and scripts folders
   createProject("MyProject")
   
   # Navigate to project and initialize
   cd("MyProject")
   initializeModelManager()
   ```

3. **Run First Simulation** (5-15 minutes per simulation):
   ```bash
   # Run the default GenerateData.jl script
   julia scripts/GenerateData.jl
   
   # Or with parallel simulations
   PCMM_NUM_PARALLEL_SIMS=4 julia scripts/GenerateData.jl
   ```

## Validation

### Manual Testing Requirements
After making changes, ALWAYS validate functionality by running complete workflows:

1. **Basic Environment Validation**:
   ```bash
   # Verify all system dependencies are available
   which julia g++ make python3
   julia --version  # Should be 1.6.7+
   
   # Test registry access
   julia -e 'import Pkg; Pkg.Registry.status()'
   ```

2. **Test Project Creation**:
   ```julia
   using PhysiCellModelManager
   createProject("TestProject"; template_as_default=true)
   cd("TestProject")
   initializeModelManager()
   ```

3. **Test Simulation Execution**:
   ```julia
   # Run at least one complete simulation to verify functionality
   config_folder = "0_template"
   custom_code_folder = "0_template" 
   inputs = InputFolders(config_folder, custom_code_folder)
   out = run(inputs; n_replicates = 1)
   ```

4. **Test Parameter Variations**:
   ```julia
   xml_path = configPath("default", "cycle", "duration")
   dv = DiscreteVariation(xml_path, [12.0, 24.0])
   out = run(inputs, dv; n_replicates = 2)
   ```

5. **Critical Success Scenarios**:
   - Project creation completes without errors
   - PhysiCell directory is properly cloned/downloaded
   - At least one simulation runs to completion
   - Database is created and accessible
   - Parameter variations generate expected number of simulations

### Pre-commit Validation
**ALWAYS run these checks before committing - they will fail in CI otherwise:**

1. **Format and Style Checks**:
   ```bash
   # Julia has no standard formatter by default - check existing code style
   # Follow patterns in existing .jl files for consistent formatting
   ```

2. **Run Focused Tests** (10-20 minutes):
   ```bash
   # Test specific functionality you modified
   julia --project=. -e 'using Pkg; Pkg.test(; test_args=["CreateProjectTests"])'
   ```

## Build Process Details

### Compilation Process
- PhysiCell C++ code compilation happens automatically during first project creation
- Compilation uses `make -j 8` with configurable compiler (default: g++)
- libRoadRunner downloaded and configured automatically for intracellular models
- Executables cached per custom code configuration to avoid recompilation

### Environment Variables
Set these for optimal development experience:
```bash
export PCMM_NUM_PARALLEL_SIMS=8        # Number of parallel simulations
export PHYSICELL_CPP=g++               # C++ compiler to use
export JULIA_NUM_THREADS=4             # Julia thread count
```

## Common Development Tasks

### Repository Structure
```
PhysiCellModelManager.jl/
├── src/                    # Main Julia source code
│   ├── PhysiCellModelManager.jl  # Main module file
│   ├── creation.jl         # Project creation functions
│   ├── runner.jl          # Simulation execution
│   ├── compilation.jl     # PhysiCell C++ compilation
│   └── analysis/          # Data analysis tools
├── test/                  # Test suite
│   ├── runtests.jl       # Test runner
│   └── test-scripts/     # Individual test files
├── docs/                 # Documentation source
└── deps/                 # Build dependencies
```

### Key APIs
- `createProject()` - Create new PhysiCell project structure
- `initializeModelManager()` - Initialize database and project
- `run(inputs)` - Execute simulations
- `InputFolders()` - Specify input file locations
- `DiscreteVariation()` - Define parameter variations

### Database Operations
- Uses SQLite for tracking simulations and preventing re-runs
- Database schema managed automatically with version upgrades
- Located at `data/pcmm.db` in each project

### Working with PhysiCell
- Automatically clones/downloads drbergman/PhysiCell fork
- Custom C++ code placed in `data/inputs/custom_codes/`
- Compilation managed through Makefile system
- Supports intracellular models via libRoadRunner

## Time Expectations

**CRITICAL - Always set appropriate timeouts:**

- **Package instantiation**: 15-30 minutes (includes C++ compilation)
- **Full test suite**: 30-60 minutes
- **Individual simulation**: 5-15 minutes  
- **Project creation**: 2-5 minutes
- **Parameter study (9 sims)**: 45-135 minutes

**NEVER CANCEL long-running operations**. The system is designed for computational biology workflows that naturally take extended time.

## Known Limitations

1. **Network Dependencies**: Requires internet access for:
   - Julia package registry updates
   - PhysiCell repository download from https://github.com/drbergman/PhysiCell
   - libRoadRunner binary download
   - BergmanLabRegistry access

2. **System Requirements**:
   - Linux/macOS recommended (Windows support limited)
   - C++ compiler (g++ or clang++, version 11+)
   - At least 4GB RAM for compilation
   - ~1GB disk space for full installation
   - Python 3.x for PhysiCell setup scripts

3. **HPC Usage**: 
   - Automatically detects SLURM environments (`sbatch` command)
   - Falls back to local parallel execution otherwise
   - Set `useHPC(false)` to force local execution

4. **Common Build Issues**:
   - Dependency resolution may fail if network connectivity is limited
   - OptimizationBase git object errors indicate registry sync issues
   - Some packages may require specific commit hashes that could be temporarily unavailable

## Troubleshooting

### Dependency Resolution Issues
1. **OptimizationBase git object errors**: 
   ```bash
   # Try clearing package cache and re-instantiating
   julia -e 'import Pkg; Pkg.gc()'
   julia --project=. -e 'import Pkg; Pkg.resolve()'
   ```

2. **Registry sync problems**:
   ```bash
   # Remove and re-add registries
   julia -e 'import Pkg; Pkg.Registry.rm("General"); Pkg.Registry.add("General")'
   julia -e 'import Pkg; Pkg.Registry.add(Pkg.RegistrySpec(url="https://github.com/drbergman-lab/BergmanLabRegistry.git"))'
   ```

### Build Process Issues
1. **Missing C++ compiler**: 
   ```bash
   sudo apt-get install build-essential g++
   ```

2. **libRoadRunner errors**: 
   ```bash
   # Ensure libtinfo5 is installed (Ubuntu/Debian)
   wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
   sudo apt-get install -y ./libtinfo5_6.3-2ubuntu0.1_amd64.deb
   ```

3. **Permission errors**: 
   ```bash
   # Check write permissions in project directory
   chmod -R u+w /path/to/project
   ```

4. **Git submodule issues**: 
   ```bash
   git submodule update --init --recursive
   ```

### Runtime Issues  
1. **Package loading failures**:
   - Ensure all dependencies are properly instantiated before importing
   - Use `julia --project=.` to ensure correct environment
   
2. **Simulation execution problems**:
   - Verify PhysiCell directory exists and is properly cloned
   - Check that custom code compiles successfully
   - Ensure database permissions are correct

3. **Parallel execution issues**: 
   ```bash
   # Reduce parallel simulations if system overloaded
   export PCMM_NUM_PARALLEL_SIMS=2
   ```

4. **Memory issues**: 
   - Close other applications during compilation
   - Consider reducing Julia thread count: `export JULIA_NUM_THREADS=2`

### Development Workflow Issues
1. **When build fails**: DO NOT immediately cancel and retry
   - Wait at least 15 minutes as compilation can appear to hang
   - Check system resources (disk space, memory)
   - Review error messages for specific dependency failures

2. **When tests hang**: This is expected behavior
   - Full test suite includes actual PhysiCell simulations
   - Each simulation can take 5-15 minutes
   - Total time scales with number of test simulations

Remember: This package manages complex computational biology workflows. Expect longer execution times than typical software development tools.