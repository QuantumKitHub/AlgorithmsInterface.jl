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

Print the public properties of `algorithm` as a tree with Unicode connectors.
Names come from `propertynames` and values from `getproperty`.
Nested algorithms and stopping criteria expand; other values use ordinary `show`.
Type names use ordinary `show`, including type parameters and default module qualification.
Expansion stops after 20 levels and prints `…` for remaining children.
The output is intended for inspection; it does not preserve every leaf's type.

Two-argument `show` and compact display keep their usual representation.
Use `sprint(show, MIME"text/plain"(), algorithm)` when a string is needed.
"""
function Base.show(io::IO, ::MIME"text/plain", algorithm::Algorithm)::Nothing
    if get(io, :compact, false)
        show(io, algorithm)
    else
        print(io, sprint(show, typeof(algorithm)))
        _show_children(io, algorithm)
    end

    return nothing
end
