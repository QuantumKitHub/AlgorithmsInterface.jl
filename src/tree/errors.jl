"""
    AlgorithmTreeError <: Exception

Abstract type for tree-input errors. Subtypes store a `message` and a `line` number
within the input string. Nonliteral macro input has `line = nothing`.
"""
abstract type AlgorithmTreeError <: Exception end

"""
    TreeInputError(message, line)

The tree is empty, or the macro argument is not a literal string.
An empty tree reports line 1; a nonliteral argument reports `nothing`.
"""
struct TreeInputError <: AlgorithmTreeError
    message::String
    line::Union{Nothing, Int}
end

"""
    TreeLayoutError(message, line)

Indentation or Unicode connectors do not match the tree's parent and sibling structure.
"""
struct TreeLayoutError <: AlgorithmTreeError
    message::String
    line::Int
end

"""
    TreeFieldError(message, line)

A field is malformed or repeated, or the supplied fields do not match a positional
constructor. Errors raised by a keyword constructor keep their original type.
"""
struct TreeFieldError <: AlgorithmTreeError
    message::String
    line::Int
end

"""
    TreeExpressionError(message, line)

A node's value cannot be parsed as one complete Julia expression.
"""
struct TreeExpressionError <: AlgorithmTreeError
    message::String
    line::Int
end

"""
    TreeConstructorError(message, line)

The root is not an `Algorithm` type, or a branch is neither an `Algorithm` nor a
`StoppingCriterion` type. This check runs when the tree is constructed.
"""
struct TreeConstructorError <: AlgorithmTreeError
    message::String
    line::Int
end

function Base.showerror(io::IO, err::AlgorithmTreeError)::Nothing
    print(io, nameof(typeof(err)), ": algorithm tree")

    if !isnothing(err.line)
        print(io, ", line ", err.line)
    end

    print(io, ": ", err.message)
    return nothing
end
