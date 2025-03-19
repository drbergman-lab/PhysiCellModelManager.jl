filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

simulation = Simulation(inputs)
@test simulation isa Simulation

simulation = Simulation(1)
@test simulation isa Simulation

monad = Monad(1)
@test monad isa Monad

n_replicates = 1
config_variation_ids = [1, 2]
rulesets_collection_variation_ids = [1, 1]
ic_cell_variation_ids = [0, 0]
location_variation_ids = Dict{Symbol,Union{Integer,AbstractArray{<:Integer}}}(
    :config => config_variation_ids,
    :rulesets_collection => rulesets_collection_variation_ids,
    :ic_cell => ic_cell_variation_ids
)
sampling = Sampling(inputs;
    n_replicates=n_replicates,
    location_variation_ids=location_variation_ids
)
@test sampling isa Sampling

trial = Trial(1)
@test trial isa Trial

samplings = [Sampling(1), Sampling(2)]
@test all(typeof.(samplings) .== Sampling)

trial = Trial(samplings)
@test trial isa Trial

@test_throws ErrorException Simulation(999)
@test_throws ErrorException Monad(999)
@test_throws ErrorException Sampling(999)

# misc tests
inputs = InputFolders(; config="0_template", custom_code="0_template")
simulation = Simulation(Monad(1))
sampling = Sampling(inputs; location_variation_ids=Dict{Symbol,Union{Integer,AbstractArray{<:Integer}}}(:config => 0, :rulesets_collection => -1, :ic_cell => -1))
sampling = Sampling(inputs; location_variation_ids=Dict{Symbol,Union{Integer,AbstractArray{<:Integer}}}(:config => [0], :rulesets_collection => -1, :ic_cell => -1))
sampling = Sampling(Monad(1))
all_monads = getSimulationIDs() .|> Simulation .|> Monad
all_monad_ids = [monad.id for monad in all_monads] |> unique
trial = Trial(Monad.(all_monad_ids))