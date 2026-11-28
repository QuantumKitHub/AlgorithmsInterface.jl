function _tree_prefixes(prefix::String, is_last::Bool)::Tuple{String, String}
    # Return the node's connector and the column to use for its children.
    if is_last
        return prefix * "└─ ", prefix * "   "
    end

    return prefix * "├─ ", prefix * "│  "
end

function _show_algorithm_tree(
        io::IO, value::Union{Algorithm, StoppingCriterion},
        prefix::String, depth::Int, style::Symbol, active::IdDict
    )::Nothing
    if haskey(active, value)
        print(io, "<cycle>")
        return nothing
    end

    print(io, sprint(show, typeof(value)))
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
                show(IOContext(io, :compact => false, :limit => false), child)
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

Leaf values use ordinary `show` with full precision and no truncation.
Cycles between algorithms or stopping criteria print as `<cycle>`.
The output is intended for inspection; it does not preserve every leaf's type.

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
