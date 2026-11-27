```@meta
CollapsedDocStrings = true
```

# [The algorithm interface](@id sec_interface)

This section starts a single, cohesive story that will weave through all documentation pages.
We will incrementally build an iterative algorithm, enrich it with stopping criteria, and
finally refine how it records (logs) its progress. Instead of presenting the API in the
abstract, we anchor every concept in one concrete, tiny example you can copy & adapt.

Why an “interface” for algorithms? Iterative numerical methods nearly always share the
same moving pieces:

* immutable input (the mathematical problem you are solving),
* immutable configuration (parameters and knobs of the chosen algorithm), and
* mutable working data (current iterate, caches, diagnostics) that evolves as you step.

Bundling these together loosely without forcing one giant monolithic type makes it easier to:

* reason about what is allowed to change and what must remain fixed,
* write generic tooling (e.g. stopping logic, logging, benchmarking) that applies across many algorithms,
* test algorithms in isolation by constructing minimal `Problem`/`Algorithm` pairs, and
* extend behavior (add new stopping criteria, new logging events) without rewriting core loops.

The interface in this package formalizes those roles with three abstract types:
* [`Problem`](@ref): immutable, algorithm‑agnostic input data.
* [`Algorithm`](@ref): immutable configuration and parameters deciding how to iterate.
* [`State`](@ref): mutable data that evolves (current iterate, caches, counters, diagnostics).

It provides a framework for decomposing iterative methods into small, composable parts:
concrete `Problem`/`Algorithm`/`State` types have to implement a minimal set of core functionality,
and this package helps to stitch everything together and provide additional helper functionality such as stopping criteria and logging functionality.

## [Concrete example: Heron's method](@id sec_heron)

To make everything tangible, we will work through a concrete example to illustrate the library's goals and concepts.
Our running example is Heron's / Babylonian method for estimating $\sqrt{S}$.
(see also the concise background on Wikipedia: [Babylonian method (Heron's method)](https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)):
Starting from an initial guess $x_0$, we may converge to the solution by iterating:

```math
x_{k+1} = \frac{1}{2}\left(x_k + \frac{S}{x_k}\right)
```

We therefore suggest the following concrete implementations of the abstract types provided by this package:
They are illustrative; various performance and generality questions will be left unaddressed to keep this example simple.

### Algorithm types

```@example Heron
using AlgorithmsInterface

struct SqrtProblem <: Problem
    S::Float64                # number whose square root we seek
end

struct HeronAlgorithm <: Algorithm
    stopping_criterion        # will be plugged in later (any StoppingCriterion)
end
```

For the state, we use the [`DefaultState`](@ref), which stores the `iterate`, the `iteration` count and the `stopping_criterion_state`.
If you need more, see [defining your own state](@ref sec_custom_state) below.

### Initialization

There are two main entry points provided by the interface:

- [`initialize_state`](@ref) constructs an entirely new state for the algorithm
- [`initialize_state!`](@ref) (in-place) reset of an existing state.

Both have default implementations that work with a [`DefaultState`](@ref), so there is nothing to define here.

### Iteration steps

Algorithms define a mutable step via [`step!`](@ref). For Heron's method:

```@example Heron
function AlgorithmsInterface.step!(problem::SqrtProblem, algorithm::HeronAlgorithm, state::DefaultState)
    S = problem.S
    x = state.iterate
    state.iterate = 0.5 * (x + S / x)
    return state
end
```

Note that we are only focussing on the actual algorithm, and *not* incrementing the iteration counter.
These kinds of bookkeeping should be handled by the [`AlgorithmsInterface.increment!`](@ref) function, which will by default already increment the iteration counter.
The following generic functionality is therefore enough for our purposes, and does *not* need to be defined.
Nevertheless, if additional bookkeeping would be desired, this can be achieved by overloading that function:

```julia
function AlgorithmsInterface.increment!(state::State)
    state.iteration += 1
    return state
end
```

### Running the algorithm

With these definitions in place you can already run (assuming you also choose a stopping criterion – added in the next section):

```@example Heron
function heron_sqrt(x; maxiter = 10)
    prob = SqrtProblem(x)
    alg  = HeronAlgorithm(StopAfterIteration(maxiter))
    return solve(prob, alg; iterate = 1.0)  # initial guess, allocates & runs
end

println("Approximate sqrt: ", heron_sqrt(16.0))
```

Note that [`solve`](@ref) will default to returning `state.iterate`.
If desired, this can be customized by altering [`finalize_state!`](@ref).
We will refine this example with better halting logic and logging shortly.

### Carrying extra data

Any additional data the algorithm needs can be stored in the `data::D` field of the [`DefaultState{V, S, D}`](@ref).

```@example Heron
struct TrackingHeronAlgorithm <: Algorithm
    stopping_criterion
end

function AlgorithmsInterface.step!(problem::SqrtProblem, ::TrackingHeronAlgorithm, state::DefaultState)
    S = problem.S
    x = state.iterate
    state.iterate = 0.5 * (x + S / x)
    push!(state.data.residuals, abs(state.iterate^2 - S))
    return state
end

problem = SqrtProblem(16.0)
tracking = TrackingHeronAlgorithm(StopAfterIteration(5))
state = initialize_state(problem, tracking, 1.0, (; residuals = Float64[]))
solve!(problem, tracking, state)
state.data.residuals
```

Here the initial iterate and the data are passed positionally, as `initialize_state(problem, algorithm, iterate, state_data)`.

### [Defining your own state](@id sec_custom_state)

If you need named fields or want to dispatch on the state, subtype [`State`](@ref) instead.
Such a state has to provide the same three properties, as well as its own initialization methods:

```@example Heron
mutable struct HeronState <: State
    iterate::Float64          # current iterate
    iteration::Int            # current iteration count
    stopping_criterion_state  # any StoppingCriterionState
end

function AlgorithmsInterface.initialize_state(problem::SqrtProblem, algorithm::HeronAlgorithm; kwargs...)
    x0 = rand() # random initial guess
    stopping_criterion_state = initialize_state(problem, algorithm, algorithm.stopping_criterion)
    return HeronState(x0, 0, stopping_criterion_state)
end

function AlgorithmsInterface.initialize_state!(problem::SqrtProblem, algorithm::HeronAlgorithm, state::HeronState; kwargs...)
    # reset the state for the algorithm
    state.iterate = rand()
    state.iteration = 0

    # reset the state for the stopping criterion
    AlgorithmsInterface.initialize_state!(
        problem, algorithm, algorithm.stopping_criterion, state.stopping_criterion_state
    )
    return state
end

function AlgorithmsInterface.step!(problem::SqrtProblem, algorithm::HeronAlgorithm, state::HeronState)
    S = problem.S
    x = state.iterate
    state.iterate = 0.5 * (x + S / x)
    return state
end
```

Since this state picks its own initial guess, the `iterate` keyword is no longer needed:

```@example Heron
println("Approximate sqrt: ", solve(SqrtProblem(16.0), HeronAlgorithm(StopAfterIteration(10))))
```

Note that the three required *properties* do not enforce a struct with these *fields*, and the properties can be emulated with correct implementations of `Base.getproperty`.

## Tree input and display

Use `@algorithm` to write nested constructor arguments as a tree. For the
`HeronAlgorithm` defined above:

```@example Heron
limit = 8
algorithm = @algorithm """
HeronAlgorithm
└─ stopping_criterion: StopAfterIteration
   └─ max_iterations: limit
"""
solve(SqrtProblem(16.0), algorithm; iterate = 1.0)
```

Here `limit` is the local Julia variable. Two-space indentation and a constructor
call at the leaf produce the same configuration:

```@example Heron
algorithm = @algorithm """
HeronAlgorithm
  stopping_criterion: StopAfterIteration(limit)
"""
```

### [Tree input rules](@id algorithm-tree-input)

| Part | Rule |
| --- | --- |
| Argument | A nonempty literal string. Write variable names inside the tree; do not interpolate the outer string or pass a string variable. |
| Root | The first nonblank line names an `Algorithm` type. A trailing `:` is optional. |
| Children | Each line has `name: value`. Names must be Julia identifiers and cannot repeat under the same parent. Only the first `:` separates the name from the value. |
| Values | One complete Julia expression per line. Empty values, incomplete expressions, and separate expressions such as `1; 2` are rejected. Standalone comment lines are not supported. |
| Whitespace | Blank lines, trailing whitespace, and a common left margin are ignored. Use spaces for indentation. |
| Nesting | Choose two spaces per level or Unicode connectors. Do not mix styles or skip a parent level. |

In Unicode trees, the space after each connector is required. Ancestor columns
must also match the sibling structure:

| Prefix | Use |
| --- | --- |
| `├─ ` | A child followed by another sibling. |
| `└─ ` | The last child of a parent. |
| `│  ` | A column for an ancestor that has a later sibling: `│` and two spaces. |
| Three spaces | A column for an ancestor that has no later sibling. |

A node with children names an `Algorithm` or `StoppingCriterion` type. Qualified
names and explicit type parameters are allowed. A leaf is an ordinary Julia
expression, evaluated once in the caller's scope, in source order. A bare type at
a leaf remains a type value; use `EmptyAlgorithm()` to construct an instance.
The root is always constructed, even if it has no children.

An applicable keyword constructor receives the named fields and supplies its own
defaults. Otherwise, supply every stored field with no extras. The positional
constructor receives them in declaration order, regardless of their order in the
tree. For a `StopWhenAll` or `StopWhenAny` branch, use `criteria: (a, b)`; the tuple's
elements are passed as separate arguments. A one-element tuple needs a comma.

### When validation happens

The parser checks spacing, connectors, field syntax, duplicates, and Julia
expression syntax during macro expansion. A malformed tree inside a function is
rejected when the function definition is expanded, even if the function is never
called.

Constructor types, supported fields, and argument values are checked when the
generated code runs. They may depend on local variables or function arguments,
which the macro does not evaluate. Errors raised by leaf expressions or user
constructors keep their original exception types.

### Display and reconstruction

The default `text/plain` display of an `Algorithm`, including REPL display, shows
its stored fields as a Unicode tree. `AlgorithmsInterface.algorithmtree(algorithm)`
returns the same text; `style=:indent` selects two-space indentation. Two-argument
`show`, `@show`, and compact display keep their usual representation.

You can edit the output and pass it to `@algorithm` when its leaves are valid Julia
expressions and its constructors accept the displayed fields. The named modules
must be loaded. Leaf expressions execute Julia code.

The display has these limits:

- It reads stored fields with `getfield`; properties supplied by `getproperty` are
  not included.
- Constructor type parameters are inferred again. Parameters that cannot be
  recovered from the fields may be lost or prevent reconstruction.
- Shared references are printed separately. Reconstruction does not preserve
  their identity. Cycles print as `<cycle>` and cannot be reconstructed.
- Tuples, named tuples, and vectors use the tree's leaf printer recursively. Other
  containers use ordinary `show`, which may not preserve every element's type.
  Values such as closures and open streams generally cannot be reconstructed.

### Errors

The following exceptions are available through `AlgorithmsInterface.`:

| Exception | Cause |
| --- | --- |
| `TreeInputError` | Empty tree or nonliteral macro argument. |
| `TreeLayoutError` | Invalid indentation, connectors, or nesting. |
| `TreeFieldError` | Malformed or repeated fields, or fields that do not match a positional constructor. |
| `TreeExpressionError` | A value is not one complete Julia expression. |
| `TreeConstructorError` | The root or a branch evaluates to an unsupported type. |

They inherit from `AlgorithmsInterface.AlgorithmTreeError` and provide `message`
and `line` fields. Line numbers refer to the tree string; nonliteral input has
`line = nothing`. An unsupported display style raises `ArgumentError`.

```@docs
@algorithm
AlgorithmsInterface.algorithmtree
AlgorithmsInterface.AlgorithmTreeError
AlgorithmsInterface.TreeInputError
AlgorithmsInterface.TreeLayoutError
AlgorithmsInterface.TreeFieldError
AlgorithmsInterface.TreeExpressionError
AlgorithmsInterface.TreeConstructorError
```

## Reference: Core interface types & functions

Below are the automatic API docs for the core interface pieces. Read them after grasping the example above – the intent should now be clearer.

```@autodocs
Modules = [AlgorithmsInterface]
Pages = ["interface/interface.jl"]
Order = [:type, :function]
Private = true
```

### Algorithm

```@autodocs
Modules = [AlgorithmsInterface]
Pages = ["interface/algorithm.jl"]
Order = [:type, :function]
Private = true
```

### Problem

```@autodocs
Modules = [AlgorithmsInterface]
Pages = ["interface/problem.jl"]
Order = [:type, :function]
Private = true
```

### State

```@autodocs
Modules = [AlgorithmsInterface]
Pages = ["interface/state.jl", "default_state.jl"]
Order = [:type, :function]
Private = true
```

### Next: Stopping criteria

Proceed to the stopping criteria section to add robust halting logic (iteration caps, time limits, tolerance on successive iterates, and combinations) to this square‑root example.
