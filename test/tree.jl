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

@testset "Nested tree display" begin
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
    @test repr("text/plain", algorithm) == chomp(unicode_tree)

    # Compact display omits children.
    @test repr("text/plain", algorithm; context = :compact => true) == outer_name * "(…)"
end

@testset "An algorithm without properties prints only its type name" begin
    @test repr("text/plain", TreeFixtures.Empty()) == "Main.AlgorithmTreeFixtures.Empty"
end

@testset "A repeated child prints on both branches" begin
    shared = StopAfterIteration(10)
    algorithm = TreeFixtures.Outer(TreeFixtures.Inner(0.1, shared), shared)
    expected = """
    $(sprint(show, typeof(algorithm)))
    ├─ inner: $(sprint(show, typeof(algorithm.inner)))
    │  ├─ step_size: 0.1
    │  └─ stopping_criterion: $(sprint(show, StopAfterIteration))
    │     └─ max_iterations: 10
    └─ stopping_criterion: $(sprint(show, StopAfterIteration))
       └─ max_iterations: 10
    """
    @test repr("text/plain", algorithm) == chomp(expected)
end

@testset "A self-reference is truncated" begin
    cycle = TreeFixtures.Cycle(nothing)
    cycle.child = cycle
    tree = repr("text/plain", cycle)
    @test endswith(tree, "…")
end

@testset "Public properties and ordinary leaf values" begin
    algorithm = TreeFixtures.PublicOptions(0.25)
    expected = """
    $(sprint(show, typeof(algorithm)))
    └─ tolerance: 0.5
    """
    @test repr("text/plain", algorithm) == chomp(expected)

    # Literal expected values make quoting and leaf formatting visible here.
    for (value, printed) in (
            (0.125, "0.125"),
            ("hello", "\"hello\""),
            (TreeFixtures.PlainValue(7), "$(sprint(show, TreeFixtures.PlainValue))(7)"),
        )
        algorithm = TreeFixtures.Leaf(value)
        expected = """
        $(sprint(show, typeof(algorithm)))
        └─ value: $(printed)
        """
        @test repr("text/plain", algorithm) == chomp(expected)
    end

    # Unrelated types keep their ordinary display.
    value = TreeFixtures.PlainValue(7)
    @test sprint(show, MIME"text/plain"(), value) == sprint(show, value)
end
