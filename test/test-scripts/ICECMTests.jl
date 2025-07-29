using LightXML, PhysiCellECMCreator

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

ic_ecm_folder = "1_xml"
ic_ecm_folder = PhysiCellModelManager.createICECMXMLTemplate(ic_ecm_folder)
@test_nowarn PhysiCellModelManager.createICECMXMLTemplate(ic_ecm_folder)

config_folder = "template-ecm"
custom_code_folder = "template-ecm"
rulesets_collection_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_ecm=ic_ecm_folder)

n_replicates = 1

dv1 = DiscreteVariation(["overall", "max_time"], 12.0)
dv2 = DiscreteVariation(icECMPath(2, "ellipse", 1, "density"), [0.25, 0.75])
dv3 = DiscreteVariation(icECMPath(2, "ellipse_with_shell", 1, "interior", "density"), 0.2)
out = run(inputs, [dv1, dv2, dv3]; n_replicates=n_replicates)

macros_lines = PhysiCellModelManager.readMacrosFile(out.trial)
@test "ADDON_PHYSIECM" in macros_lines

# test failing ecm sim
xml_path1 = icECMPath(2, "ellipse", 1, "a")
xml_path2 = icECMPath(2, "elliptical_disc", 1, "a")
dv1 = DiscreteVariation(xml_path1, 50.0)
dv2 = DiscreteVariation(xml_path2, 80.0)
cv = CoVariation(dv1, dv2)

out_fail = run(out.trial.monads[1], cv; n_replicates=n_replicates)
@test out_fail.n_success == 0