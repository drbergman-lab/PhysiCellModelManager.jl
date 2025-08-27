# Database upgrades
Over time, the database structure of PhysiCellModelManager.jl will evolve to reflect new capabilities, features, and improvements.
Not every release will change the database structure, but when one does in a way that could affect your workflow, PhysiCellModelManager.jl will throw a warning.
The warning will link to this page and the function will wait for user input to proceed.
Changes are listed in reverse chronological order.

## to v0.1.3
Rename the database file from `pcvct.db` to `pcmm.db` to reflect the name change of the package.

## to v0.0.30
The `pcvct_version` table is renamed to `pcmm_version` due to the name change of the package.
Also, check any environment variables you have set, e.g., in the `~/.zshrc` or `~/.bashrc` files, and update them to reflect the new package name.
Any that were prefixed with `PCVCT_` should now be prefixed with `PCMM_`.

## to v0.0.29
The `inputs.toml` file has been moved from `data/` to `data/inputs/`.

## to v0.0.15
Introduce XML-based ECM initial conditions. This introduces `ic_ecm_variations`.
Also, introduce Dirichlet initial conditions from file, which introduces the `ic_dc_id` in the database.
For any simulations in the database before upgrading, both of these will be set to `-1` (i.e., no initial conditions) except if  `ic_ecm_id` is not `-1`, in which case `ic_ecm_variation_id` will be set to `0` (i.e., the default ECM initial conditions which is all the original CSV version can handle).

## to v0.0.10
Start tracking the PhysiCell version used in the simulation.
This introduces the `physicell_versions` table which tracks the PhysiCell versions used in simulations.
Currently, only supports reading the PhysiCell version, not setting it (e.g., through git commands).
Key changes include:
- Adding the `physicell_version_id` column to the `simulations`, `monads`, and `samplings` tables.
- Adding the `physicell_versions` table.
  - If `PhysiCell` is a git-tracked repo, this will store the commit hash as well as any tag and repo owner it can find based on the remotes. It will also store the date of the commit.
  - If `PhysiCell` is not a git-tracked repo, it will read the `VERSION.txt` file and store that as the `commit_hash` with `-download` appended to the version.

## to v0.0.3
Introduce XML-based cell initial conditions. This introduces `ic_cell_variations`.
Also, standardized the use of `config_variation` in place of `variation`. Key changes include:
- Renaming the `variation_id` column in the `simulations` and `monads` tables to `config_variation_id`.
- Adding the `ic_cell_variation_id` column to the `simulations` and `monads` tables.
- In `data/inputs/configs`, renaming all instances of "variation" to "config_variation" in filenames and databases.