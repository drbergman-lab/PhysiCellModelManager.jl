filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

include(joinpath(@__DIR__, "..", "..", "deps", "DeprecateKeywords.jl"))
import .DeprecateKeywords: @depkws

@testset "Basic" begin
    # force the deprecation warning to be emitted
    @depkws force=true function f(; a=2, @deprecate b a)
        a
    end

    @test f(a=1) === 1
    @test_warn "Keyword argument `b` is deprecated. Use `a` instead." (@test f(b=1) == 1)
    @test_warn "Keyword argument `b` is deprecated. Use `a` instead." (@test f(b=nothing) === nothing)
end

@testset "Multi-param" begin
    # do not force the deprecation warning to be emitted (default behavior)
    @depkws force=false function g(; α=2, γ=4, @deprecate(β, α), @deprecate(δ, γ))
        α + γ
    end

    @test g() === 6
    @test g(α=1, γ=3) === 4

    @test_warn "Keyword argument `β` is deprecated. Use `α` instead." (@test g(β=1, γ=3) === 4)
    @test_warn "Keyword argument `δ` is deprecated. Use `γ` instead." (@test g(α=1, δ=3) === 4)
    @test_warn "Keyword argument `β` is deprecated. Use `α` instead." (@test g(β=1, δ=3) === 4)
end

@testset "With types" begin
    # default behavior is to not emit deprecation warnings, so it will not be emitted
    @depkws h(; (@deprecate old_kw new_kw), new_kw::Int=3) = new_kw
    @test h() === 3
    @test h(new_kw=1) === 1
    @test_warn "Keyword argument `old_kw` is deprecated. Use `new_kw` instead." (@test h(old_kw=1) === 1)
end

@testset "Error catching" begin
    # Incorrect scope:
    @test_throws LoadError (@eval @depkws k(; @deprecate a b, b = 10) = b)

    # Use type assertion with no default set:
    @depkws y(; a::Int, (@deprecate b a)) = a

    @test y(a=1) == 1
    @test_warn "Keyword argument `b` is deprecated. Use `a` instead." (@test y(b=1) == 1)
    # Type assertion should still work:
    @test_throws TypeError y(a=1.0)

    # We shouldn't interfere with regular kwargs:
    @depkws y2(; a::Int) = a
    @test y2(a=1) == 1
end

@testset "No default set" begin
    @depkws k(x; (@deprecate a b), b) = x + b
    @test_throws UndefKeywordError k(1.0)
    @test_warn "Keyword argument `a` is deprecated. Use `b` instead." (@test k(1.0; a=2.0) == 3.0)
    @test k(1.0; b=2.0) == 3.0
end

@testset "Name conflicts" begin
    @depkws force(; a="cat", @deprecate(b, a)) = a
    @test_warn "Keyword argument `b` is deprecated. Use `a` instead." (@test force(b="dog") == "dog")
    @test macroexpand(DeprecateKeywords, :(@depkws force(; a="cat", @deprecate(b, a)) = a)) |> string |> contains("force = false")
    @test macroexpand(DeprecateKeywords, :(@depkws force=true force(; a="cat", @deprecate(b, a)) = a)) |> string |> contains("force = true")
end

@testset "Correct head" begin
    @test_throws LoadError (@eval @depkws fake_head-true k(; @deprecate a b, b = 10) = b)
end