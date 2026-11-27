struct _AlgorithmTreeNode
    field::Symbol
    value::Any # Parsed Julia syntax: an Expr, Symbol, or literal value.
    line::Int
    prefix::String
    children::Vector{_AlgorithmTreeNode}
end

function _tree_node(field::Symbol, value::String, line::Int, prefix::String)::_AlgorithmTreeNode
    parsed = Meta.parse(value; raise = false)
    if isnothing(parsed) || (parsed isa Expr && parsed.head in (:toplevel, :error, :incomplete))
        throw(TreeExpressionError("expected one complete Julia expression", line))
    end

    return _AlgorithmTreeNode(field, parsed, line, prefix, _AlgorithmTreeNode[])
end

function _tree_lines(text::String)::Vector{Tuple{Int, String}}
    # Ignore blank lines and a common left margin, but keep source line numbers.
    entries = Tuple{Int, String}[]

    for (line, entry) in enumerate(split(text, '\n'))
        isempty(strip(entry)) && continue
        push!(entries, (line, String(rstrip(entry))))
    end

    isempty(entries) && throw(TreeInputError("empty tree", 1))
    margin = minimum(length(entry) - length(lstrip(entry)) for (_, entry) in entries)

    return [(line, String(chop(entry; head = margin, tail = 0))) for (line, entry) in entries]
end

function _tree_layout(entry::String, line::Int, graphical::Bool)::Tuple{Int, String, String}
    occursin('\t', entry) && throw(TreeLayoutError("use spaces instead of tabs", line))

    if !graphical
        spaces = length(entry) - length(lstrip(entry))
        spaces > 0 && iseven(spaces) || throw(TreeLayoutError("use two spaces per level", line))

        return spaces ÷ 2, String(lstrip(entry)), ""
    end

    # Consume one ancestor column at a time, then the node's own connector.
    # Every column and connector occupies three characters, including spaces.
    depth = 1
    prefix = ""
    body = entry

    while startswith(body, "│  ") || startswith(body, "   ")
        prefix *= first(body, 3)
        body = String(chop(body; head = 3, tail = 0))
        depth += 1
    end

    if !startswith(body, "├─ ") && !startswith(body, "└─ ")
        throw(TreeLayoutError("invalid connector", line))
    end

    # Preserve the prefix for validation once all siblings are known.
    prefix *= first(body, 3)
    body = String(chop(body; head = 3, tail = 0))

    return depth, body, prefix
end

function _tree_field(body::String, line::Int)::Tuple{Symbol, String}
    # Split only the field separator; a Julia leaf expression can contain colons.
    parts = split(body, ':'; limit = 2)
    length(parts) == 2 || throw(TreeFieldError("expected field: value", line))

    name, value = strip.(parts)
    Base.isidentifier(name) || throw(TreeFieldError("invalid field name $name", line))
    isempty(value) && throw(TreeFieldError("missing value for $name", line))

    return Symbol(name), String(value)
end

function _parse_algorithm_tree(text::Any)::_AlgorithmTreeNode
    # This is the single validation entry point, called during macro expansion.
    text isa String || throw(TreeInputError("@algorithm requires a literal tree string", nothing))

    entries = _tree_lines(text)
    line, title = first(entries)
    root = _tree_node(:root, String(strip(chopsuffix(title, ":"))), line, "")

    first_child_line = length(entries) > 1 ? entries[2][2] : ""
    graphical = startswith(first_child_line, "├─") || startswith(first_child_line, "└─")

    # The stack is the current path from the root. A field at depth d belongs
    # to stack[d]; moving to a sibling discards the previous branch's descendants.
    stack = [root]

    for (line, entry) in entries[2:end]
        depth, body, prefix = _tree_layout(entry, line, graphical)
        depth <= length(stack) || throw(TreeLayoutError("missing parent level", line))

        name, value = _tree_field(body, line)
        parent = stack[depth]

        for sibling in parent.children
            sibling.field == name && throw(TreeFieldError("duplicate field $name", line))
        end

        child = _tree_node(name, value, line, prefix)
        push!(parent.children, child)

        resize!(stack, depth)
        push!(stack, child)
    end

    _validate_tree_layout(root)
    return root
end

function _tree_prefixes(prefix::String, is_last::Bool)::Tuple{String, String}
    # Return the node's connector and the column to use for its children.
    if is_last
        return prefix * "└─ ", prefix * "   "
    end

    return prefix * "├─ ", prefix * "│  "
end

function _validate_tree_layout(node::_AlgorithmTreeNode, prefix::String = "")::Nothing
    for (i, child) in enumerate(node.children)
        is_last = i == length(node.children)
        expected_prefix, child_prefix = _tree_prefixes(prefix, is_last)

        if !isempty(child.prefix) && child.prefix != expected_prefix
            throw(TreeLayoutError("expected connector $(repr(expected_prefix))", child.line))
        end

        _validate_tree_layout(child, child_prefix)
    end

    return nothing
end
