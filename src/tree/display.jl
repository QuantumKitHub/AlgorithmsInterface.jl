function _tree_name(type::Type)::String
    module_path = Base.fullname(parentmodule(type))
    return join((module_path..., nameof(type)), ".")
end

_show_tree_leaf(io::IO, value::Any)::Nothing = _show_tree_leaf(io, value, IdDict())

function _show_tree_leaf(io::IO, value::Any, active::IdDict)::Nothing
    show(IOContext(io, :compact => false, :limit => false), value)
    return nothing
end

function _show_tree_leaf(io::IO, value::Signed, active::IdDict)::Nothing
    # Ordinary show omits the type of small signed integer values.
    context = IOContext(io, :compact => false, :limit => false)

    if value isa Int
        show(context, value)
    else
        print(io, _tree_name(typeof(value)), '(')
        show(context, value)
        print(io, ')')
    end

    return nothing
end

function _show_tree_leaf(io::IO, value::Tuple, active::IdDict)::Nothing
    print(io, '(')

    for (i, item) in enumerate(value)
        i > 1 && print(io, ", ")
        _show_tree_leaf(io, item, active)
    end

    # The comma distinguishes a singleton tuple from a parenthesized expression.
    if !isempty(value)
        print(io, ',')
    end

    print(io, ')')
    return nothing
end

function _show_tree_leaf(io::IO, value::NamedTuple{names, T}, active::IdDict)::Nothing where {names, T}
    # Keep declared field types, including fields deliberately widened to Any.
    print(io, "NamedTuple{", repr(names), ", ", repr(T), "}(")
    _show_tree_leaf(io, Tuple(value), active)
    print(io, ')')

    return nothing
end

function _show_tree_leaf(io::IO, value::Vector{T}, active::IdDict)::Nothing where {T}
    if haskey(active, value)
        print(io, "<cycle>")
        return nothing
    end

    active[value] = nothing

    try
        _show_tree_leaf(io, T, active)
        print(io, '[')

        for (i, item) in enumerate(value)
            i > 1 && print(io, ", ")
            _show_tree_leaf(io, item, active)
        end

        print(io, ']')
    finally
        delete!(active, value)
    end

    return nothing
end

function _show_tree_leaf(io::IO, value::Union{StopWhenAll, StopWhenAny}, active::IdDict)::Nothing
    print(io, _tree_name(typeof(value)))
    return _show_tree_leaf(io, value.criteria, active)
end

function _show_algorithm_tree(
        io::IO, value::Union{Algorithm, StoppingCriterion},
        prefix::String, depth::Int, style::Symbol, active::IdDict
    )::Nothing
    if haskey(active, value)
        print(io, "<cycle>")
        return nothing
    end

    print(io, _tree_name(typeof(value)))
    names = fieldnames(typeof(value))

    if isempty(names) && depth > 0
        print(io, "()")
    end

    active[value] = nothing

    try
        for (i, name) in enumerate(names)
            is_last = i == length(names)
            line_prefix, child_prefix = _tree_prefixes(prefix, is_last)

            if style === :unicode
                marker = line_prefix
            else
                marker = repeat("  ", depth + 1)
            end

            print(io, '\n', marker, name, ": ")
            child = getfield(value, name)

            if child isa Union{Algorithm, StoppingCriterion}
                _show_algorithm_tree(
                    io, child, child_prefix,
                    depth + 1, style, active
                )
            else
                _show_tree_leaf(io, child, active)
            end
        end
    finally
        delete!(active, value)
    end

    return nothing
end

"""
    AlgorithmsInterface.algorithmtree(algorithm; style=:unicode) -> String

Return a string showing the stored fields of `algorithm` as a tree.
Use `style=:unicode` for tree connectors or `style=:indent` for two-space indentation.
Other styles throw `ArgumentError`.

The output can be passed to [`@algorithm`](@ref) if the leaf values print as Julia
expressions and the constructors accept the displayed fields. The named modules
must be loaded. Constructor type parameters are inferred again; shared references
are not preserved. Cycles print as `<cycle>` and cannot be reconstructed.

The default `text/plain` display of an `Algorithm` uses this tree. Two-argument
`show` and compact display keep their usual representation.
"""
function algorithmtree(algorithm::Algorithm; style::Symbol = :unicode)::String
    if style !== :unicode && style !== :indent
        throw(ArgumentError("style must be :unicode or :indent"))
    end

    io = IOBuffer()
    _show_algorithm_tree(io, algorithm, "", 0, style, IdDict())

    return String(take!(io))
end

function Base.show(io::IO, ::MIME"text/plain", algorithm::Algorithm)::Nothing
    if get(io, :compact, false)
        show(io, algorithm)
    else
        _show_algorithm_tree(io, algorithm, "", 0, :unicode, IdDict())
    end

    return nothing
end
