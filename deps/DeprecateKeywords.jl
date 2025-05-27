module DeprecateKeywords

using MacroTools

"""
    @depkws [force=false] def

Macro to deprecate keyword arguments. Use by wrapping a function signature,
while using `@deprecate(old_kw, new_kw)` within the function signature to deprecate.

# Examples

```julia
@depkws function f(; a=2, @deprecate(b, a))
    a
end
```

```julia
# force the deprecation warning to be emitted
@depkws force=true function f(; a=2, @deprecate(b, a))
    a
end
```
"""
macro depkws(args...)
    options = parse_options(args[1:end-1])
    return esc(_depkws(args[end], options))
end

function parse_options(args)
    options = default_options()
    for arg in args
        if isa(arg, Expr) && arg.head == :(=)
            @assert arg.args[1] ∈ keys(options) "Unknown option: $(arg.args[1])"
            options[arg.args[1]] = arg.args[2]
        else
            error("Invalid option: $arg")
        end
    end
    return options
end

function default_options()
    return Dict{Symbol, Any}(:force => false)
end

abstract type DeprecatedDefault end

function _depkws(def, options)
    sdef = splitdef(def)
    func_symbol = Expr(:quote, sdef[:name])  # Double quote for expansion

    new_symbols = Symbol[]
    deprecated_symbols = Symbol[]
    kwargs_to_remove = Int[]
    for (i, param) in enumerate(sdef[:kwargs])
        isa(param, Symbol) && continue
        # Look for @deprecated macro:
        if param.head == :macrocall && param.args[1] == Symbol("@deprecate")
            # e.g., params.args[2] is the line number
            deprecated_symbol = param.args[end-1]
            new_symbol = param.args[end]
            if !isa(new_symbol, Symbol)
                # Remove line numbers nodes:
                clean_param = deepcopy(param)
                filter!(x -> !isa(x, LineNumberNode), clean_param.args)
                error(
                    "The expression\n    $(clean_param)\ndoes not appear to be two symbols in a `@deprecate`. This can happen if you use `@deprecate` in a function " *
                    "definition without " *
                    "parentheses, such as `f(; @deprecate a b, c=2)`. Instead, you should write `f(; (@deprecate a b), c=2)` or alternatively " *
                    "`f(; @deprecate(a, b), c=2)`.)"
                )
            end
            push!(deprecated_symbols, deprecated_symbol)
            push!(new_symbols, new_symbol)
            push!(kwargs_to_remove, i)
        end
    end
    deleteat!(sdef[:kwargs], kwargs_to_remove)

    # Add deprecated kws:
    for deprecated_symbol in deprecated_symbols
        pushfirst!(sdef[:kwargs], Expr(:kw, deprecated_symbol, DeprecatedDefault))
    end

    symbol_mapping = Dict(new_symbols .=> deprecated_symbols)

    # Update new symbols to use deprecated kws if passed:
    for (i, kw) in enumerate(sdef[:kwargs])
        no_default_type_assertion = !isa(kw, Symbol) && kw.head != :kw
        no_default_naked = isa(kw, Symbol)
        no_default = no_default_naked || no_default_type_assertion

        (kw, type_assertion) = if no_default_type_assertion
            @assert kw.head == :(::)
            # Remove type assertion from keyword; we will
            # assert it later.
            kw.args
        else
            (kw, Nothing)
        end

        new_kw, default = if no_default
            (kw, DeprecatedDefault)
        else
            (kw.args[1], kw.args[2])
        end


        _get_symbol(new_kw) in deprecated_symbols && continue
        !(_get_symbol(new_kw) in new_symbols) && continue

        deprecated_symbol = symbol_mapping[_get_symbol(new_kw)]
        depwarn_string = "Keyword argument `$(deprecated_symbol)` is deprecated. Use `$(_get_symbol(new_kw))` instead."
        new_kwcall = quote
            if $deprecated_symbol !== $(DeprecatedDefault)
                Base.depwarn($depwarn_string, $func_symbol; force=$(options[:force]))
                $deprecated_symbol
            else
                $default
            end
        end
        sdef[:kwargs][i] = Expr(:kw, new_kw, new_kwcall)

        if no_default_type_assertion
            pushfirst!(
                sdef[:body].args,
                Expr(:(::), _get_symbol(new_kw), type_assertion)
            )
        end

        if no_default
            # Propagate UndefKeywordError
            pushfirst!(
                sdef[:body].args,
                Expr(:if,
                    Expr(:call, :(===), _get_symbol(new_kw), DeprecatedDefault),
                    Expr(:call, :throw,
                        Expr(:call, :UndefKeywordError, QuoteNode(_get_symbol(new_kw)))
                    )
                )
            )
        end
    end

    return combinedef(sdef)
end

# This is used to go from a::Int to a
_get_symbol(e::Expr) = first(map(_get_symbol, e.args))
_get_symbol(e::Symbol) = e

end
