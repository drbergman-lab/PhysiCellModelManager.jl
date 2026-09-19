# Every name a user can reach through `using PhysiCellModelManager` — exported or `public`, PCMM's
# own or re-exported from ModelManager — must have a home in the manual: a user page under
# `docs/src/man/` or a Dev-tier page under `docs/src/dev/`. The alphabetical index (a Documenter
# `@index`) and the generated journal do not count. See CLAUDE.md / CONTRIBUTING.md,
# "Documentation", and PRD.md, "Tiered Manual with Full Public-API Coverage".
#
#! Like DocstringRefTests.jl this needs `Base.ispublic` (Julia 1.11+); on 1.10 `@compat public` is a
#! no-op and the public-but-unexported names cannot be enumerated, so the check is skipped there.
#! Presence is a whole-word match anywhere on a page, code blocks and tier blocks included: which
#! tier a name is introduced in is a documentation judgement (recorded in PRD.md), not a test.

@static if isdefined(Base, :ispublic)
    @testset "ManualCoverageTests.jl" begin
        MM = PhysiCellModelManager.ModelManager
        publicNames(m) = Set(n for n in names(m; all=true) if Base.ispublic(m, n))
        skip = Set([:PhysiCellModelManager, :ModelManager])
        all_names = setdiff(union(Set(names(PhysiCellModelManager)), publicNames(PhysiCellModelManager), publicNames(MM)), skip)
        #! `names(PhysiCellModelManager)` already carries the ModelManager exports via Reexport.

        docs_src = normpath(joinpath(@__DIR__, "..", "..", "docs", "src"))
        excluded = Set(normpath.(joinpath.(docs_src, ["man/index.md", "dev/journal.md"])))
        pages = String[]
        for sub in ("man", "dev"), (root, _, files) in walkdir(joinpath(docs_src, sub)), f in files
            endswith(f, ".md") || continue
            p = normpath(joinpath(root, f))
            p in excluded || push!(pages, p)
        end
        @test !isempty(pages)
        text = join((read(p, String) for p in pages), "\n")

        #! `\b` fails after a trailing `!`, so use explicit non-word lookarounds; the name itself is
        #! quoted so `Sobolʼ` and `!` are matched literally.
        present(n) = occursin(Regex("(?<!\\w)" * replace(string(n), r"([\\^\$.|?*+()\[\]{}!])" => s"\\\1") * "(?!\\w)"), text)

        missing_names = sort!([string(n) for n in all_names if !present(n)])
        if !isempty(missing_names)
            @info "Public names with no manual page (add a section, or a `!!! tierdev` block, under docs/src/man or docs/src/dev):" missing_names
        end
        @test isempty(missing_names)
    end
end
