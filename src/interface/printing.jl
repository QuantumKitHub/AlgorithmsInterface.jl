const TREE_MAX_DEPTH = 20

function _show_children(
        io::IO, x::T, prefix::String = "", depth::Int = 0,
    )::Nothing where {T}
    names = propertynames(x)
    isempty(names) && return nothing

    # Bound recursive configurations without tracking object identities.
    if depth >= TREE_MAX_DEPTH
        print(io, '\n', prefix, "…")
        return nothing
    end

    for (i, name) in enumerate(names)
        child = getproperty(x, name)
        is_last = i == length(names)
        connector = is_last ? "└─ " : "├─ "

        print(io, '\n', prefix, connector, name, ": ")

        if child isa Algorithm || child isa StoppingCriterion
            print(io, sprint(show, typeof(child)))

            column = is_last ? "   " : "│  "
            child_prefix = prefix * column
            _show_children(io, child, child_prefix, depth + 1)
        else
            show(io, child)
        end
    end

    return nothing
end

"""
    show(io::IO, ::MIME"text/plain", algorithm::Algorithm)

Print an algorithm as a tree, expanding nested algorithms and stopping criteria.
"""
function Base.show(io::IO, ::MIME"text/plain", algorithm::Algorithm)::Nothing
    print(io, sprint(show, typeof(algorithm)))
    if get(io, :compact, false)
        print(io, "(…)")
    else
        _show_children(io, algorithm)
    end
    return nothing
end
