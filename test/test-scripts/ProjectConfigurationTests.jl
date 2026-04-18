filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

@test_throws ArgumentError PhysiCellModelManager.ModelManager.sanitizePathElement("..")
@test_throws ArgumentError PhysiCellModelManager.ModelManager.sanitizePathElement("~")
@test_throws ArgumentError PhysiCellModelManager.ModelManager.sanitizePathElement("/looks/like/absolute/path")

@test_throws ErrorException PhysiCellModelManager.folderIsVaried(:config, "not-a-config-folder")