function _tree_expression(node::_AlgorithmTreeNode, source::LineNumberNode; root::Bool = false)::Any
    # The parser has validated the entire tree and parsed every value already.
    if !root && isempty(node.children)
        return node.value
    end

    keywords = Expr(:parameters)

    for child in node.children
        value = _tree_expression(child, source)
        location = LineNumberNode(source.line + child.line - 1, source.file)
        located_value = Expr(:block, location, value)

        push!(keywords.args, Expr(:kw, child.field, located_value))
    end

    fields = Expr(:tuple, keywords)
    return Expr(:call, GlobalRef(@__MODULE__, :_tree_construct), node.value, fields, node.line, root)
end

function _tree_construct(constructor::Any, fields::NamedTuple, line::Int, root::Bool)::Union{}
    throw(TreeConstructorError("expected a type, got $(typeof(constructor))", line))
end

function _tree_construct(
        constructor::Type{T}, fields::NamedTuple, line::Int, root::Bool
    )::Union{Algorithm, StoppingCriterion} where {T}
    if root
        constructor <: Algorithm || throw(TreeConstructorError("root must name an Algorithm type", line))
    elseif !(constructor <: Union{Algorithm, StoppingCriterion})
        throw(TreeConstructorError("branch must name an Algorithm or StoppingCriterion type", line))
    end

    if applicable(Core.kwcall, fields, constructor)
        return constructor(; fields...)
    end

    # The static type keeps field names inferable for unparameterized constructors.
    names = fieldnames(T)
    same_field_count = length(fields) == length(names)
    all_fields_present = all(haskey(fields, name) for name in names)

    if !same_field_count || !all_fields_present
        throw(TreeFieldError("$constructor needs fields $names or a keyword constructor", line))
    end

    if constructor <: Union{StopWhenAll, StopWhenAny}
        return constructor(fields.criteria...)
    end

    # Positional arguments follow the struct's declaration order, not input order.
    # Splat the generator directly; collecting it first can lose inferred types.
    arguments = (fields[name] for name in names)
    return constructor(arguments...)
end

"""
    @algorithm "tree"

Construct an [`Algorithm`](@ref) from a literal string.

The first line names the algorithm type. Each following line supplies a field as
`name: value`, nested with two spaces per level or Unicode tree connectors.
A value with children names an `Algorithm` or [`StoppingCriterion`](@ref) type.
A value without children is a Julia expression evaluated once in the caller's scope.

If a keyword constructor applies, it receives the named fields and supplies any
defaults. Otherwise, every stored field is required; arguments are passed to the
positional constructor in field order. Use `criteria: (a, b)` for a branch containing
[`StopWhenAll`](@ref) or [`StopWhenAny`](@ref).

Malformed tree syntax throws an [`AlgorithmTreeError`](@ref) during macro expansion.
Constructor types and arguments are checked at runtime. Exceptions from leaf
expressions and user constructors are passed through unchanged.

See [Tree input rules](@ref algorithm-tree-input) for spacing and expression rules.
"""
macro algorithm(text::Any)
    tree = _parse_algorithm_tree(text)
    expression = _tree_expression(tree, __source__; root = true)

    return esc(Expr(:(::), expression, GlobalRef(@__MODULE__, :Algorithm)))::Expr
end
