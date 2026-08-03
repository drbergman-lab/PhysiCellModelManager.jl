# A docstring that `@ref`s a non-public binding cannot resolve now that `docs/src/lib/*.md`
# renders only the public API. Without this guard the failure only shows up in CI's `docs`
# job, as a `:cross_references` error that terminates `makedocs` before rendering anything.
# This runs with the ordinary suite and needs no docs build.
# See CLAUDE.md, "Docstring cross-references".
#
#! Only `Docs.meta(PhysiCellModelManager)` is walked: that is the set of docstrings this repo
#! can actually fix. Docstrings written in PCMM's source on a ModelManager function land there
#! too (keyed by the ModelManager binding), so the simulator-interface methods are covered.
#! ModelManager's own docstrings are deliberately out of scope — it has an equivalent guard of
#! its own, and PCMM's suite should not go red over a defect in a dependency it cannot patch.
#! Targets still resolve against *both* public sets, since PCMM's doc site renders both modules
#! (see docs/make.jl) and a PCMM docstring may legitimately ref a public ModelManager name.
#! Julia 1.10 (the compat floor) has neither `Base.ispublic` nor the `public` keyword, so
#! `@compat public` is a no-op there and every name would look private. The check is only
#! meaningful on 1.11+; docs CI must run 1.11+ as well, or Documenter's `Private = false`
#! will not classify these names correctly either.

@static if isdefined(Base, :ispublic)
    @testset "DocstringRefTests.jl" begin
        #! `[`foo`](@ref)` → `foo`; also handles `Mod.foo`, `foo(x)`, and `Foo{T}`.
        refTarget(s) = strip(first(split(replace(s, r"^(PhysiCellModelManager\.)?(ModelManager\.)?" => ""), r"[({]")))

        MM = PhysiCellModelManager.ModelManager
        isResolvable(sym) = Base.ispublic(PhysiCellModelManager, sym) || Base.ispublic(MM, sym)

        violations = Tuple{Symbol,String}[]
        for (binding, multidoc) in Docs.meta(PhysiCellModelManager)
            for docstr in values(multidoc.docs)
                text = join(Iterators.filter(x -> x isa AbstractString, docstr.text), "")
                for m in eachmatch(r"\[`([^`]+)`\]\(@ref\)", text)
                    target = Symbol(refTarget(m.captures[1]))
                    isResolvable(target) && continue
                    push!(violations, (binding.var, m.captures[1]))
                end
            end
        end

        if !isempty(violations)
            msg = join(["  $(owner) → [`$(target)`](@ref)" for (owner, target) in sort(unique(violations))], "\n")
            @info "Docstrings referencing non-public bindings:\n$msg"
        end
        @test isempty(violations)
    end
else
    @info "Skipping \"DocstringRefTests.jl\": needs Julia 1.11+ for Base.ispublic."
end
