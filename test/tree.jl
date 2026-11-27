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
    end
end

@testset "nested tree display in both styles" begin
    # Build the object with ordinary constructors. These checks need no input macro.
    algorithm = TreeFixtures.Outer(
        TreeFixtures.Inner(0.1, StopAfterIteration(10)), StopAfterIteration(20)
    )
    unicode_tree = """
    Main.AlgorithmTreeFixtures.Outer
    ├─ inner: Main.AlgorithmTreeFixtures.Inner
    │  ├─ step_size: 0.1
    │  └─ stopping_criterion: AlgorithmsInterface.StopAfterIteration
    │     └─ max_iterations: 10
    └─ stopping_criterion: AlgorithmsInterface.StopAfterIteration
       └─ max_iterations: 20
    """
    indented_tree = """
    Main.AlgorithmTreeFixtures.Outer
      inner: Main.AlgorithmTreeFixtures.Inner
        step_size: 0.1
        stopping_criterion: AlgorithmsInterface.StopAfterIteration
          max_iterations: 10
      stopping_criterion: AlgorithmsInterface.StopAfterIteration
        max_iterations: 20
    """
    @test (@inferred AlgorithmsInterface.algorithmtree(algorithm)) == chomp(unicode_tree)
    @test (@inferred AlgorithmsInterface.algorithmtree(algorithm; style = :indent)) == chomp(indented_tree)
    @test (@inferred show(IOBuffer(), MIME"text/plain"(), algorithm)) === nothing
    @test AlgorithmsInterface.algorithmtree(TreeFixtures.Empty()) == "Main.AlgorithmTreeFixtures.Empty"
end
