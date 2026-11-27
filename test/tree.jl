using AlgorithmsInterface
using AlgorithmsInterface: AlgorithmTreeError, TreeInputError, TreeLayoutError,
    TreeFieldError, TreeExpressionError, TreeConstructorError
using Test
using Dates: Dates, Minute

# Re-evaluating a displayed tree resolves its qualified constructor names.
# Give the fixtures a stable path instead of ParallelTestRunner's anonymous module.
@eval Main module AlgorithmTreeFixtures
using AlgorithmsInterface
using Dates: Minute

# No keyword constructor: exercises positional construction and type inference.
struct Leaf{T} <: Algorithm
    value::T
end
struct Empty <: Algorithm end

# Keyword defaults and validation must still run when construction uses a tree.
struct Solver{A, S} <: Algorithm
    inner::A
    stopping_criterion::S
    steps::Int
end
function Solver(;
        inner::A = Leaf(1), stopping_criterion::S = StopAfterIteration(10),
        steps::Int = 2
    )::Solver{A, S} where {A, S}
    steps > 0 || throw(DomainError(steps))
    return Solver(inner, stopping_criterion, steps)
end

function keyword_tree(value::T, steps::Int)::Solver where {T}
    return @algorithm """
    Solver
      inner: Leaf
        value: value
      steps: steps
    """
end

function local_constructor_tree(constructor::Type{A}, value::T)::Algorithm where {A, T}
    return @algorithm """
    constructor
      value: value
    """
end

# Complete nested example used by the inference checks below. Both algorithms
# have their own stopping criteria, and the outer criterion combines two limits.
struct Inner{S <: StoppingCriterion} <: Algorithm
    step_size::Float64
    stopping_criterion::S
end

struct Outer{A <: Algorithm, S <: StoppingCriterion} <: Algorithm
    inner::A
    stopping_criterion::S
end

function make_algorithm(step_size::Float64, inner_limit::Int)::Outer
    return @algorithm """
    Outer
    ├─ inner: Inner
    │  ├─ step_size: step_size
    │  └─ stopping_criterion: StopAfterIteration
    │     └─ max_iterations: inner_limit
    └─ stopping_criterion: StopWhenAny
       └─ criteria: (StopAfterIteration(100), StopAfter(Minute(1)))
    """
end

# Mutable solely so display can be tested against a self-reference.
mutable struct Cycle <: Algorithm
    child::Any
end
end

using Main: AlgorithmTreeFixtures
const TreeFixtures = AlgorithmTreeFixtures

@testset "tree construction and display inference" begin
    # Use runtime arguments: literal-only examples can hide inference problems
    # through constant folding. @inferred checks the full concrete return type.
    algorithm = @inferred TreeFixtures.make_algorithm(0.1, 10)
    @test algorithm.inner.step_size == 0.1
    @test algorithm.inner.stopping_criterion.max_iterations == 10
    @test (@inferred AlgorithmsInterface.algorithmtree(algorithm)) isa String
    @test (@inferred show(IOBuffer(), MIME"text/plain"(), algorithm)) === nothing

    # Also check the keyword-constructor path with defaults and generic leaf types.
    for value in (1, 0.1, "value")
        configured = @inferred TreeFixtures.keyword_tree(value, 3)
        @test configured.inner.value === value
        @test configured.steps == 3
    end
end

# Exercise the public macro on the actual displayed text. repr quotes the outer
# string safely, including quotes, dollar signs, backslashes and newlines in leaves.
function restore_tree(text::AbstractString)::Algorithm
    return include_string(@__MODULE__, "@algorithm " * repr(text))
end

@testset "tree input" begin
    @testset "Unicode branches evaluate leaves once, in source order" begin
        calls = Int[]

        function record_call(i::Int)::Int
            push!(calls, i)
            return i
        end

        algorithm = @algorithm """
        TreeFixtures.Solver
        ├─ inner: TreeFixtures.Leaf
        │  └─ value: record_call(1)
        ├─ stopping_criterion: StopAfterIteration
        │  └─ max_iterations: record_call(2)
        └─ steps: record_call(3)
        """

        @test algorithm.inner.value == 1
        @test algorithm.stopping_criterion.max_iterations == 2
        @test algorithm.steps == 3

        # Checking values alone would miss duplicate or reordered evaluations.
        @test calls == [1, 2, 3]
    end

    @testset "Indented leaves use caller scope without capturing local names" begin
        let value = "x:y", constructor = :shadow, kwargs = :shadow
            algorithm = @algorithm """
            TreeFixtures.Leaf
              value: value
            """
            @test algorithm.value == "x:y"
        end
    end

    @testset "Constructors retain defaults, explicit types and validation" begin
        @test (@algorithm "TreeFixtures.Solver").steps == 2
        @test (@algorithm "TreeFixtures.Empty") isa TreeFixtures.Empty
        @test (@algorithm "TreeFixtures.Leaf{Int}\n  value: 7").value === 7

        # The keyword constructor's own error must propagate, not trigger a fallback.
        @test_throws DomainError (@algorithm "TreeFixtures.Solver\n  steps: -1")
        @test_throws TreeFieldError (@algorithm "TreeFixtures.Leaf\n  wrong: 1")
        @test_throws TreeConstructorError (@algorithm "Int\n  value: 1")
        @test_throws TreeConstructorError (@algorithm "1")
        @test_throws TreeConstructorError (@algorithm "StopAfterIteration\n  max_iterations: 1")

        # A failure in caller code is not a tree syntax or construction error.
        @test_throws DivideError (@algorithm "TreeFixtures.Leaf\n  value: div(1, 0)")
    end

    @testset "Leaf expressions are not mistaken for tree structure" begin
        # A connector inside a string must not select Unicode-tree parsing.
        @test (@algorithm "TreeFixtures.Leaf\n  value: \"└─ text\"").value == "└─ text"

        # A leaf can construct an object directly instead of opening another branch.
        algorithm = @algorithm """
        TreeFixtures.Solver
          steps: 4
          inner: TreeFixtures.Empty()
        """
        @test algorithm.inner isa TreeFixtures.Empty
    end
end

@testset "malformed tree input" begin
    # Expand only: these are syntax errors and must fail before any constructor runs.
    # Named cases make failures explain the rejected rule rather than just a string.
    cases = (
        ("empty tree", TreeInputError, 1, ""),
        ("skipped parent level", TreeLayoutError, 2, "TreeFixtures.Leaf\n    value: 1"),
        ("tab indentation", TreeLayoutError, 2, "TreeFixtures.Leaf\n\tvalue: 1"),
        ("duplicate field", TreeFieldError, 3, "TreeFixtures.Leaf\n  value: 1\n  value: 2"),
        ("missing field separator", TreeFieldError, 2, "TreeFixtures.Leaf\n  value 1"),
        ("missing leaf value", TreeFieldError, 2, "TreeFixtures.Leaf\n  value:"),
        ("invalid field identifier", TreeFieldError, 2, "TreeFixtures.Leaf\n  bad name: 1"),
        ("multiple leaf expressions", TreeExpressionError, 2, "TreeFixtures.Leaf\n  value: 1; 2"),
        ("incomplete leaf expression", TreeExpressionError, 2, "TreeFixtures.Leaf\n  value: ("),
        ("last child uses a continuing connector", TreeLayoutError, 2, "TreeFixtures.Leaf\n├─ value: 1"),
        ("connector is missing its following space", TreeLayoutError, 2, "TreeFixtures.Leaf\n└─value: 1"),
        (
            "ancestor column is too short", TreeLayoutError, 3, """
            TreeFixtures.Solver
            ├─ inner: TreeFixtures.Leaf
            │ └─ value: 1
            └─ steps: 2
            """,
        ),
        (
            "ancestor continuation is missing", TreeLayoutError, 3, """
            TreeFixtures.Solver
            ├─ inner: TreeFixtures.Leaf
               └─ value: 1
            └─ steps: 2
            """,
        ),
    )
    # The parser owns all text validation; macro expansion must expose the same
    # errors without evaluating names, leaf expressions, or constructors.
    for (description, error_type, line, text) in cases, phase in (:parser, :macro)
        @testset "$description ($phase)" begin
            caught = try
                if phase === :parser
                    AlgorithmsInterface._parse_algorithm_tree(text)
                else
                    macroexpand(@__MODULE__, Expr(:macrocall, Symbol("@algorithm"), LineNumberNode(1), text))
                end
                nothing
            catch err
                err
            end

            @test caught isa error_type
            @test caught isa AlgorithmTreeError
            if caught isa AlgorithmTreeError
                @test caught.line == line
                @test occursin("line $line", sprint(showerror, caught))
            end
        end
    end
    @testset "Input must be a literal string" begin
        @test_throws TreeInputError AlgorithmsInterface._parse_algorithm_tree(:variable)
        @test_throws TreeInputError macroexpand(@__MODULE__, :(@algorithm variable))
    end
end

@testset "macro expansion versus runtime validation" begin
    # Parsing and layout validation return concrete types even though individual
    # Julia syntax values can be expressions, symbols, or literals.
    tree = @inferred AlgorithmsInterface._parse_algorithm_tree("TreeFixtures.Leaf\n  value: 7")
    @test tree.children[1].value === 7
    @test (@inferred AlgorithmsInterface._validate_tree_layout(tree)) === nothing

    # Expanding a function rejects malformed tree syntax before the function runs.
    definition = :(
        function invalid_tree(value::Int)::Algorithm
            @algorithm "TreeFixtures.Leaf\n  value: ("
        end
    )
    @test_throws TreeExpressionError macroexpand(@__MODULE__, definition)

    # Names and calls remain unevaluated during expansion. Resolving them here
    # would reject valid local constructors or execute caller code prematurely.
    expression = :(@algorithm "constructor\n  value: error(\"runtime only\")")
    @test macroexpand(@__MODULE__, expression) isa Expr

    algorithm = @inferred TreeFixtures.local_constructor_tree(TreeFixtures.Leaf{Int}, 7)
    @test algorithm.value === 7
    @test_throws TreeConstructorError TreeFixtures.local_constructor_tree(Int, 7)
end

@testset "tree error rendering and runtime locations" begin
    @test sprint(showerror, TreeInputError("expected a literal string", nothing)) ==
        "TreeInputError: algorithm tree: expected a literal string"

    caught = try
        @algorithm """
        TreeFixtures.Solver
          inner: Int
            value: 1
        """
    catch err
        err
    end
    @test caught isa TreeConstructorError
    @test caught.line == 2
    @test (@inferred showerror(IOBuffer(), caught)) === nothing
end

@testset "editable tree output" begin
    @testset "Integer expressions preserve their concrete types" begin
        # Equal numeric values can still select different algorithm methods.
        # Check the reconstructed type as well as the value, including boundaries.
        for T in (Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128)
            @testset "$T" begin
                for value in (typemin(T), T(2), typemax(T))
                    original = TreeFixtures.Leaf(value)
                    tree = AlgorithmsInterface.algorithmtree(original)
                    restored = restore_tree(tree)

                    @test typeof(restored) === typeof(original)
                    @test restored.value === value
                end
            end
        end
    end

    @testset "Containers recursively preserve integers and criterion groups" begin
        group = StopWhenAny(StopAfterIteration(10), StopAfterIteration(20))
        cases = (
            "integer tuple" => (Int8(2), Int32(3)),
            "integer named tuple" => (count = Int8(2),),
            "integer vector" => Int8[2, 3],
            "group in named tuple" => (stop = group,),
            "group in vector" => [group],
            "nested containers" => [(count = Int8(2), stops = (group,))],
            "empty named tuple" => NamedTuple(),
            "empty typed vector" => typeof(group)[],
            "abstract vector element type" => StoppingCriterion[group, StopAfterIteration(5)],
            "abstract named-tuple field type" => NamedTuple{(:stop,), Tuple{Any}}((group,)),
        )
        for (description, value) in cases
            @testset "$description" begin
                original = TreeFixtures.Leaf(value)
                for style in (:unicode, :indent)
                    tree = AlgorithmsInterface.algorithmtree(original; style)
                    restored = restore_tree(tree)
                    @test typeof(restored) === typeof(original)
                    @test isequal(restored.value, value)
                end
                # Check the printer methods, not just the public String wrapper.
                @test (@inferred AlgorithmsInterface._show_tree_leaf(IOBuffer(), value)) === nothing
            end
        end
    end

    @testset "Tuple leaves and group calls preserve their argument structure" begin
        # A singleton tuple needs a comma. A group needs separate constructor
        # arguments, not a single tuple argument, including when nested in a tuple.
        cases = (
            "empty tuple" => (),
            "singleton tuple" => (1,),
            "multiple tuple elements" => (1, 2),
            "empty criterion group" => StopWhenAll(),
            "singleton criterion group" => StopWhenAny(StopAfterIteration(10)),
            "criterion group inside a tuple" =>
                (StopWhenAll(StopAfterIteration(10), StopAfterIteration(20)),),
        )
        for (description, value) in cases
            @testset "$description" begin
                tree = AlgorithmsInterface.algorithmtree(TreeFixtures.Leaf(value))
                @test restore_tree(tree).value === value
            end
        end
    end

    @testset "Display preserves numeric precision and complete containers" begin
        # Julia's compact printing rounds floats; limited printing abbreviates arrays.
        # Neither is acceptable when the displayed text will reconstruct the settings.
        cases = (
            "scalar precision" => 1.234567890123,
            "vector element precision" => [1.234567890123],
            "named-tuple field precision" => (; value = 1.234567890123),
            "array is not truncated" => collect(1:30),
        )
        for (description, value) in cases
            @testset "$description" begin
                original = TreeFixtures.Leaf(value)
                tree = sprint(show, MIME"text/plain"(), original; context = :limit => true)
                @test isequal(restore_tree(tree).value, value)
            end
        end
    end

    @testset "Both tree styles reconstruct nested settings and escaped strings" begin
        original = TreeFixtures.Solver(inner = TreeFixtures.Leaf("quote: \"; dollar: \$; slash: \\; newline: \n"))
        for style in (:unicode, :indent)
            @testset "$style" begin
                restored = restore_tree(AlgorithmsInterface.algorithmtree(original; style))
                @test restored.inner.value == original.inner.value
                @test restored.steps == original.steps
                @test restored.stopping_criterion == original.stopping_criterion
            end
        end
    end

    @testset "Built-in stopping criteria reconstruct through their constructors" begin
        # Cover a time value, a named function, and a mixed AND/OR group whose
        # constructor takes varargs even though its stored field is a tuple.
        # These tests check configuration reconstruction, not stopping behavior.
        cases = (
            "time limit" => StopAfter(Minute(1)),
            "named function and threshold" => StopWhenBelow(abs, 0.1),
            "nested AND/OR groups" =>
                (StopAfterIteration(10) | StopAfterIteration(20)) & StopAfter(Minute(1)),
        )
        for (description, criterion) in cases
            @testset "$description" begin
                original = TreeFixtures.Solver(inner = TreeFixtures.Empty(), stopping_criterion = criterion)
                restored = restore_tree(AlgorithmsInterface.algorithmtree(original))
                @test restored.inner isa TreeFixtures.Empty
                @test restored.stopping_criterion === criterion
            end
        end
    end
end

@testset "tree display behavior" begin
    original = TreeFixtures.Solver()

    @testset "Plain-text display uses the Unicode tree" begin
        tree = sprint(show, MIME"text/plain"(), original)
        @test tree == AlgorithmsInterface.algorithmtree(original)
        @test occursin("│  └─ value:", tree)
        @test_throws ArgumentError AlgorithmsInterface.algorithmtree(original; style = :bad)
    end

    @testset "Compact contexts retain ordinary Julia printing" begin
        compact_plain = sprint(show, MIME"text/plain"(), original; context = :compact => true)
        compact_show = sprint(show, original; context = :compact => true)
        @test compact_plain == compact_show
        @test !occursin('\n', repr([original]))
    end

    @testset "Cycles terminate, but shared children are not cycles" begin
        cycle = TreeFixtures.Cycle(nothing)
        cycle.child = cycle
        @test occursin("<cycle>", sprint(show, MIME"text/plain"(), cycle))

        # Visiting the same child on two separate branches must remain valid.
        shared = TreeFixtures.Leaf(2)
        shared_algorithm = TreeFixtures.Solver(shared, shared, 2)
        tree = AlgorithmsInterface.algorithmtree(shared_algorithm)
        @test !occursin("<cycle>", tree)

        # Recursive container printing must also stop cycles through a named tuple.
        cyclic = Any[]
        push!(cyclic, (self = cyclic,))
        @test occursin("<cycle>", AlgorithmsInterface.algorithmtree(TreeFixtures.Leaf(cyclic)))

        shared_vector = Int8[2]
        value = (first = shared_vector, second = shared_vector)
        tree = AlgorithmsInterface.algorithmtree(TreeFixtures.Leaf(value))
        @test !occursin("<cycle>", tree)
        @test isequal(restore_tree(tree).value, value)
    end
end
