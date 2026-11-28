using AlgorithmsInterface
using Test

# Give displayed type names a stable path outside the test runner's anonymous module.
@eval Main module AlgorithmTreeFixtures
using AlgorithmsInterface

# A leaf with a field whose type depends on its value.
struct Leaf{T} <: Algorithm
    value::T
end
struct Empty <: Algorithm end

# Default settings used by the display tests.
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

# The nested display example gives each algorithm its own stopping criterion.
struct Inner{S <: StoppingCriterion} <: Algorithm
    step_size::Float64
    stopping_criterion::S
end

struct Outer{A <: Algorithm, S <: StoppingCriterion} <: Algorithm
    inner::A
    stopping_criterion::S
end

# Expose a computed property instead of the internal storage field.
struct PublicOptions <: Algorithm
    storage::Float64
end
Base.propertynames(::PublicOptions)::Tuple{Symbol} = (:tolerance,)
function Base.getproperty(x::PublicOptions, name::Symbol)::Float64
    return name === :tolerance ? 2getfield(x, :storage) : getfield(x, name)
end

# This is a leaf, even though it has properties of its own.
struct PlainValue
    number::Int
end

# Mutable solely so display can be tested against a self-reference.
mutable struct Cycle <: Algorithm
    child::Any
end
end

using Main: AlgorithmTreeFixtures
const TreeFixtures = AlgorithmTreeFixtures

@testset "tree display behavior" begin
    original = TreeFixtures.Solver()

    @testset "Plain-text display uses the Unicode tree" begin
        tree = sprint(show, MIME"text/plain"(), original)
        @test occursin("├─ inner:", tree)
        @test occursin("│  └─ value:", tree)
    end

    @testset "Compact contexts retain ordinary Julia printing" begin
        compact_plain = sprint(show, MIME"text/plain"(), original; context = :compact => true)
        compact_show = sprint(show, original; context = :compact => true)
        @test compact_plain == compact_show
        @test !occursin('\n', repr([original]))
    end

    @testset "Depth is bounded and shared children print on both branches" begin
        cycle = TreeFixtures.Cycle(nothing)
        cycle.child = cycle
        tree = sprint(show, MIME"text/plain"(), cycle)
        @test endswith(tree, "…")
        @test length(split(tree, '\n')) <= 25

        # Visiting the same child on two separate branches must remain valid.
        shared = TreeFixtures.Leaf(2)
        shared_algorithm = TreeFixtures.Solver(shared, shared, 2)
        tree = sprint(show, MIME"text/plain"(), shared_algorithm)
        @test !occursin("…", tree)
        @test count("value: 2", tree) == 2
    end
end

@testset "nested tree display writes Unicode directly to IO" begin
    # Build the object with ordinary constructors. These checks need no input macro.
    algorithm = TreeFixtures.Outer(
        TreeFixtures.Inner(0.1, StopAfterIteration(10)), StopAfterIteration(20)
    )
    # Type headers follow Base.show, including parameters and default qualification.
    outer_name = sprint(show, typeof(algorithm))
    inner_name = sprint(show, typeof(algorithm.inner))
    criterion_name = sprint(show, StopAfterIteration)
    unicode_tree = """
    $(outer_name)
    ├─ inner: $(inner_name)
    │  ├─ step_size: 0.1
    │  └─ stopping_criterion: $(criterion_name)
    │     └─ max_iterations: 10
    └─ stopping_criterion: $(criterion_name)
       └─ max_iterations: 20
    """
    io = IOBuffer()
    @test (@inferred show(io, MIME"text/plain"(), algorithm)) === nothing
    @test String(take!(io)) == chomp(unicode_tree)
    @test sprint(show, MIME"text/plain"(), TreeFixtures.Empty()) == sprint(show, TreeFixtures.Empty)
end

@testset "Public properties and ordinary leaf values" begin
    algorithm = TreeFixtures.PublicOptions(0.25)
    tree = sprint(show, MIME"text/plain"(), algorithm)
    @test tree == sprint(show, typeof(algorithm)) * "\n└─ tolerance: 0.5"
    @test !occursin("storage:", tree)

    # Real leaf values must appear, including quoted strings and structured leaves.
    for value in (0.125, "hello", TreeFixtures.PlainValue(7))
        algorithm = TreeFixtures.Leaf(value)
        @test sprint(show, MIME"text/plain"(), algorithm) ==
            sprint(show, typeof(algorithm)) * "\n└─ value: " * sprint(show, value)
    end

    # The generic helper must not install tree display for unrelated types.
    value = TreeFixtures.PlainValue(7)
    @test sprint(show, MIME"text/plain"(), value) == sprint(show, value)
end
