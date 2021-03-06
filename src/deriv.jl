
# diff_base.jl - common routines for ordinary symbolic and tensor differentiation

const IDX_NAMES = Espresso.IDX_NAMES


abstract type AbstractDiffRule end

struct DiffRule <: AbstractDiffRule
    pat::Expr        # pattern of expression to differentiate
    dpat::Any        # pattern of differentiation expression
end


const DIFF_PHS = Set([:x, :y, :z, :a, :b, :c, :m, :n])

const DIFF_RULES =
    Dict{Tuple{OpName, Vector{Type}, Int}, DiffRule}()


opname(mod, op) = canonical(mod, op)

"""
Define new differentiation rule. Arguments:

 * `ex` - original expression in a form `func(arg1::Type1, arg2::Type2, ...)`
 * `idx` - index of argument to differentiate over
 * `dex` - expression of corresponding derivative

Example:

    @diff_rule *(x::Number, y::Number) 1 y

Which means: derivative of a product of 2 numbers w.r.t. 1st argument
is a second argument.

Note that rules are always defined as if arguments were ordinary variables
and not functions of some other variables, because this case will be
automatically handled by chain rule in the differentiation engine.

"""
macro diff_rule(ex::Expr, idx::Int, dex::Any)
    @assert ex.head == :call
    op = opname(current_module(), ex.args[1])
    types = [eval(exa.args[2]) for exa in ex.args[2:end]]
    new_args = Symbol[exa.args[1] for exa in ex.args[2:end]]
    canonical_ex = Expr(:call, op, new_args...)
    # canonical_ex = canonical_calls(current_module(), ex)
    canonical_dex = canonical_calls(current_module(), dex)
    DIFF_RULES[(op, types, idx)] = DiffRule(canonical_ex, canonical_dex)
end


"""
Find differentiation rule for `op` with arguments of `types`
w.r.t. `idx`th argument. Example:

    rule = find_rule(:*, [Int, Int], 1)

Which reads as: find rule for product of 2 Ints w.r.t. 1st argument.

In addition to the types passed, rules for all combinations of all their
ansestors (as defined by `type_ansestors()`) will be checked.

Rule itself is an opaque object containing information needed for derivation
and guaranted to be compatible with `apply_rule()`.
"""
function find_rule(op::OpName, types::Vector{DataType}, idx::Int)
    type_ans = map(type_ansestors, types)
    type_products = product(type_ans...)
    ks = ((op, [tp...], idx) for tp in type_products)
    for k in ks
        if haskey(DIFF_RULES, k)
            return Nullable(DIFF_RULES[k])
        end
    end
    return Nullable()
end

"""
Apply rule retrieved using `find_rule()` to an expression.
"""
function apply_rule(rule::DiffRule, ex::Expr)
    deriv_ex = rewrite(ex, rule.pat, rule.dpat; phs=DIFF_PHS)
    return deriv_ex
end


## register rule

function without_output_tuple(ex::Expr)
    @assert(ex.head == :block && ex.args[end].head == :tuple,
            "Got unexpected derivative expression: $ex")
    return Expr(ex.head, ex.args[1:end-1]...)
end


"""
Add to all intermediate variables a prefix of a function name to avoid name conflicts
"""
function with_opname_prefix(ex::Expr, fname::OpName)
    @assert ex.head == :block
    prefix = isa(fname, Symbol) ? "__$(fname)_" : "__$(fname.args[1])_$(fname.args[2].value)_"
    st = Dict()
    for subex in ex.args
        if subex.head == :(=)
            vname = split_indexed(subex.args[1])[1]
            st[vname] = Symbol("$(prefix)_$(vname)")
        end
    end
    return subs(ex, st)
end


"""
Register new differentiation rule for function `fname` with arguments
of `types` at index `idx`, return this new rule.
"""
function register_rule(fname::OpName, types::Vector{DataType}, idx::Int)
    # TODO: check module
    f = eval(fname)
    args, ex = funexpr(f, (types...))
    # ex = sanitize(ex)
    xs = [(arg, ones(T)[1]) for (arg, T) in zip(args, types)]
    dex = xdiff(ex; xs...)
    prefixed_dex = with_opname_prefix(remove_unused(dex), fname)
    pure_dex = without_output_tuple(prefixed_dex)
    fex = Expr(:call, fname, args...)
    new_rule = DiffRule(fex, pure_dex)
    DIFF_RULES[(fname, types, idx)] = new_rule
    return new_rule
end

## derivative (for primitive expressions)

function derivative(pex::Expr, types::Vector{DataType}, idx::Int;
                    mod=current_module())
    @assert pex.head == :call
    op = canonical(mod, pex.args[1])
    maybe_rule = find_rule(op, types, idx)
    if !isnull(maybe_rule)
        rule = get(maybe_rule)
    else
        error("Primitive expression $pex with types $types at index $idx " *
              "doesn't have a registered derivative. Use `@diff_rule` to register one. " *
              "Note: currently automatic derivative inference of nested functions " *
              "is turned off as unreliable, but this may change in the future.")
        # register_rule(op, types, idx)
    end
    return apply_rule(rule, pex) |> sanitize
end

derivative(var::Symbol, types::Vector{DataType}, idx::Int) = 1
