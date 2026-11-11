```@meta
CollapsedDocStrings = true
```

# [Logging](@id sec_logging)

In the final part of the square‑root story we augment Heron's iteration with logging functionality.
For example, we might be interested in the convergence behavior throughout the iterations, timing information, or storing intermediate values for later analysis.
The logging system is designed to provide full flexibility over this behavior, without polluting the core algorithm implementation.
Additionally, we strive to *pay for what you get*: when no logging is configured, there is minimal overhead.

## Why separate logging from algorithms?

Decoupling logging from algorithm logic lets us:

* Add diagnostic output without modifying algorithm code.
* Compose multiple logging behaviors (printing, storing, timing) independently.
* Reuse generic logging actions across different algorithms.
* Disable logging globally with zero runtime cost.
* Instrument algorithms with custom events for domain-specific diagnostics.
* Customize logging behavior *a posteriori*: users can add logging features to existing algorithms without modifying library code.

The logging system aims to achieve these goals by separating the logging logic into two separate parts.
These parts can be roughly described as *events* and *actions*, where the logging system is responsible for mapping between them.
Concretely, we have:

* **When do we log?** → [`with_algorithmlogger`](@ref) controls how events are mapped to actions.
* **What happens when we log?** → a [`LoggingAction`](@ref) determines what to do when an event happens.

This separation allows users to compose rich behaviors (printing, collecting statistics, plotting) without modifying algorithm code, and lets algorithm authors emit domain‑specific events.

## Using the default logging actions

Continuing from the [Stopping Criteria](@ref sec_stopping) page, we have our Heron's method implementation ready:

```@example Heron
using AlgorithmsInterface
using Printf
using Dates # hide

struct SqrtProblem <: Problem
    S::Float64
end

struct HeronAlgorithm <: Algorithm
    stopping_criterion
end

function AlgorithmsInterface.step!(problem::SqrtProblem, algorithm::HeronAlgorithm, state::DefaultState)
    S = problem.S
    x = state.iterate
    state.iterate = 0.5 * (x + S / x)
    return state
end

function heron_sqrt(x; stopping_criterion = StopAfterIteration(10))
    prob = SqrtProblem(x)
    alg  = HeronAlgorithm(stopping_criterion)
    return solve(prob, alg; iterate = 1.0)  # allocates & runs
end
nothing # hide
```

It is already interesting to note that there are no further modifications necessary to start leveraging the logging system.

### Basic iteration printing

Let's start with a very basic example of logging: printing iteration information after each step.
We use [`CallbackAction`](@ref) to wrap a simple function that accesses the state, and prints the `iteration` as well as the `iterate`.

```@example Heron
using Printf
iter_printer = CallbackAction() do problem, algorithm, state
    @printf("Iter %3d: x = %.12f\n", state.iteration, state.iterate)
end
nothing # hide
```

To activate this logger, we wrap the section of code that we want to enable logging for, and map the `:PostStep` context to our action.
This is achieved through the [`with_algorithmlogger`](@ref) function, which under the hood uses Julia's `with` function to manipulate a scoped value.
The actions are grouped in an [`AlgorithmLogger`](@ref) for the solve they apply to, which is identified by its name, by default that of the type of its algorithm:

```@example Heron
with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => iter_printer)) do
    sqrt2 = heron_sqrt(2.0)
end
nothing # hide
```

### Default logging contexts

The default `solve!` loop emits logging events at several key points during iteration:

|  context  |              event                  |
| --------- | ----------------------------------- |
| :Start    | The solver will start.              |
| :PreStep  | The solver is about to take a step. |
| :PostStep | The solver has taken a step.        |
| :Stop     | The solver has finished.            |

Any of these events can be hooked into to attach a logging action.
For example, we may expand on the previous example as follows:

```@example Heron
start_printer = CallbackAction() do problem, algorithm, state
    @printf("Start: x = %.12f\n", state.iterate)
end
stop_printer = CallbackAction() do problem, algorithm, state
    @printf("Stop %3d: x = %.12f\n", state.iteration, state.iterate)
end

with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:Start => start_printer, :PostStep => iter_printer, :Stop => stop_printer)) do
    sqrt2 = heron_sqrt(2.0)
end
nothing # hide
```

Furthermore, specific algorithms could emit events for custom contexts too.
We will come back to this in the section on the [`AlgorithmLogger`](@ref sec_algorithmlogger) design.

### Reporting why we stopped

The `:Stop` context is where the [stopping criterion](@ref sec_stopping) has its say, and [`StopReasonAction`](@ref) is a ready-made action that prints it:

```@example Heron
with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:Stop => StopReasonAction())) do
    heron_sqrt(2.0)
end
nothing # hide
```

This is a thin wrapper around [`get_reason`](@ref), so anything that criterion reports shows up here.
See [querying the verdict](@ref sec_stopping_verdict) for the machine-readable counterparts, which are useful in an [`IfAction`](@ref) predicate — for example to only dump diagnostics on a run that failed to converge.

### Timing execution

Let's add timing information to see how long each iteration takes:

```@example Heron
start_time = Ref{Float64}(0.0)

record_start = CallbackAction() do problem, algorithm, state
    start_time[] = time()
end

show_elapsed = CallbackAction() do problem, algorithm, state
    dt = time() - start_time[]
    @printf("  elapsed = %.3fs\n", dt)
end

timing = AlgorithmLogger(
    :Start => record_start,
    :PostStep => show_elapsed,
    :Stop => CallbackAction() do problem, algorithm, state
        total = time() - start_time[]
        @printf("Done after %d iterations (total %.3fs)\n", state.iteration, total)
    end,
)
with_algorithmlogger(:HeronAlgorithm => timing) do
    sqrt2 = heron_sqrt(2)
end
nothing # hide
```

### Conditional logging

Sometimes we only want to log at specific iterations. [`IfAction`](@ref) wraps another action behind a predicate:

```@example Heron
every_two = IfAction(
    (problem, algorithm, state; kwargs...) -> state.iteration % 2 == 0,
    iter_printer,
)

with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => every_two)) do
    sqrt2 = heron_sqrt(2)
end
nothing # hide
```

This prints only on even iterations, reducing output for long-running algorithms.

### Storing intermediate values

Instead of just printing, we can capture the entire trajectory for later analysis:

```@example Heron
struct CaptureHistory <: LoggingAction
    iterates::Vector{Float64}
end
CaptureHistory() = CaptureHistory(Float64[])

function AlgorithmsInterface.handle_message!(
        action::CaptureHistory,
        problem::SqrtProblem,
        algorithm::HeronAlgorithm,
        state::DefaultState;
        kwargs...
)
    push!(action.iterates, state.iterate)
    return nothing
end

history = CaptureHistory()

with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => history)) do
    sqrt2 = heron_sqrt(2)
end

println("Stored ", length(history.iterates), " iterates")
println("First few values: ", history.iterates[1:min(3, end)])
```

You can later analyze convergence rates, plot trajectories, or export data—all without modifying the algorithm.

### Combining multiple logging behaviors

We can combine printing, timing, and storage simultaneously:

```@example Heron
history2 = CaptureHistory()

combined = AlgorithmLogger(
    :Start => record_start,
    :PostStep => ActionGroup(iter_printer, history2),
    :Stop => CallbackAction() do problem, algorithm, state
        @printf("Captured %d iterates in %.3fs\n", length(history2.iterates), time() - start_time[])
    end,
)
with_algorithmlogger(:HeronAlgorithm => combined) do
    sqrt2 = heron_sqrt(2)
end
nothing # hide
```

## Implementing custom LoggingActions

While [`CallbackAction`](@ref) is convenient for quick instrumentation, custom types give more control and possibly better performance.
Let's implement a more sophisticated example: tracking iteration statistics.

### The required interface

To implement a custom [`LoggingAction`](@ref), you need:

1. A concrete subtype of `LoggingAction`.
2. An implementation of [`AlgorithmsInterface.handle_message!`](@ref) that defines the behavior.

The signature of `handle_message!` is:

```julia
function handle_message!(
        action::YourAction, problem::Problem, algorithm::Algorithm, state::State; kwargs...
)
    # Your logging logic here
    return nothing
end
```

The `kwargs...` can contain context-specific information, though the default contexts don't currently pass additional data.

### Example: Statistics collector

Let's build an action that tracks statistics across iterations:

```@example Heron
mutable struct StatsCollector <: LoggingAction
    count::Int              # aggregate number of evaluations
    sum::Float64            # sum of all intermediate values
    sum_squares::Float64    # square sum of all intermediate values
end
StatsCollector() = StatsCollector(0, 0.0, 0.0)

function AlgorithmsInterface.handle_message!(
        action::StatsCollector, problem::SqrtProblem, algorithm::HeronAlgorithm, state::DefaultState;
        kwargs...
)
    action.count += 1
    action.sum += state.iterate
    action.sum_squares += state.iterate^2
    return nothing
end

function compute_stats(stats::StatsCollector)
    n = stats.count
    mean = stats.sum / n
    variance = (stats.sum_squares / n) - mean^2
    return (mean=mean, variance=variance, count=n)
end

stats = StatsCollector()

with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => stats)) do
    sqrt2 = heron_sqrt(2.0; stopping_criterion = StopAfter(Millisecond(50)))
end

result = compute_stats(stats)
println("Collected $(result.count) samples")
println("Mean iterate: $(result.mean)")
println("Variance: $(result.variance)")
```

This pattern of collecting data during iteration and post-processing afterward is efficient and keeps the hot loop fast.

## [The AlgorithmLogger](@id sec_algorithmlogger)

The [`AlgorithmsInterface.AlgorithmLogger`](@ref) is the dispatcher that routes logging events to actions.
Understanding its design helps when adding custom logging contexts.

### How logging events are emitted

Inside the `solve!` function, logging events are emitted at key points:

```julia
function solve!(problem::Problem, algorithm::Algorithm, state::State; kwargs...)
    initialize_state!(problem, algorithm, state; kwargs...)
    emit_message(problem, algorithm, state, :Start)

    while !is_finished!(problem, algorithm, state)
        emit_message(problem, algorithm, state, :PreStep)

        increment!(state)
        step!(problem, algorithm, state)

        emit_message(problem, algorithm, state, :PostStep)
    end

    emit_message(problem, algorithm, state, :Stop)

    return finalize_state!(problem, algorithm, state)
end
```

The [`emit_message`](@ref) function looks up the context (e.g., `:PostStep`) in the logger of the running solve and calls `handle_message!` on the corresponding action.
That logger is the entry of the enclosing logger named after the solve, as described in [Nested solves](@ref sec_nested_solves).

### Global enable/disable

For production runs or benchmarking, you can disable all logging globally:

```@example Heron
# By default, logging is enabled:
println("Logging enabled: ", AlgorithmsInterface.get_global_logging_state())
with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => iter_printer)) do
    heron_sqrt(2.0)
end
nothing # hide
```

```@example Heron
# But, logging can also be disabled:
previous_state = AlgorithmsInterface.set_global_logging_state!(false)

# This will not log anything, even with a logger configured
with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => iter_printer)) do
    heron_sqrt(2.0)
end

# Restore previous state
AlgorithmsInterface.set_global_logging_state!(previous_state)
nothing # hide
```

This works since the default implementation of [`emit_message`](@ref) first retrieves the current logger through [`AlgorithmsInterface.algorithm_logger`](@ref):

```julia
emit_message(problem, algorithm, state, context; kwargs...) =
    emit_message(algorithm_logger(), problem, algorithm, state, context; kwargs...)
```

When logging is disabled globally, [`algorithm_logger`](@ref AlgorithmsInterface.algorithm_logger) returns `nothing`, and `emit_message` becomes a no-op with minimal overhead.

### Error isolation

If a `LoggingAction` throws an exception, the logging system catches it and reports an error without aborting the algorithm:

```@example Heron
buggy_action = CallbackAction() do problem, algorithm, state
    if state.iteration == 3
        error("Intentional logging error at iteration 3")
    end
    @printf("Iter %d\n", state.iteration)
end

with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:PostStep => buggy_action)) do
    heron_sqrt(2.0)
    println("Algorithm completed despite logging error")
end
```

This robustness ensures that bugs in logging code don't compromise the algorithm's correctness.

## Adding custom logging contexts

Algorithms can emit custom logging events for domain-specific scenarios.
For example, adaptive algorithms might emit events when step sizes are reduced, or when steps are rejected.
Here we will illustrate this by a slight adaptation of our algorithm, which could restart if convergence wasn't reached after 10 iterations.

### Emitting custom events

To emit a custom logging event from within your algorithm, call [`emit_message`](@ref):

```@example Heron
function AlgorithmsInterface.step!(problem::SqrtProblem, algorithm::HeronAlgorithm, state::DefaultState)
    # Suppose we check for numerical issues
    if !isfinite(state.iterate) || mod(state.iteration, 10) == 0
        emit_message(problem, algorithm, state, :Restart)
        state.iterate = rand()  # Reset the iterate and try again
    end

    # Normal step
    S = problem.S
    x = state.iterate
    state.iterate = 0.5 * (x + S / x)
    return state
end
nothing # hide
```

Now users can attach actions to the `:Restart` context:

```@example Heron
issue_counter = Ref(0)
issue_action = CallbackAction() do problem, algorithm, state
    issue_counter[] += 1
    println("⚠️  Numerical issue detected at iteration ", state.iteration)
end

with_algorithmlogger(:HeronAlgorithm => AlgorithmLogger(:Restart => issue_action, :PostStep => iter_printer)) do
    sqrt2 = heron_sqrt(2.0; stopping_criterion = StopAfterIteration(30))
end

nothing # hide
```


## [Nested solves](@id sec_nested_solves)

An algorithm can solve subproblems by making use of other algorithms from within its `step!`.
For example, the fourth root can be computed by taking the square root twice:

```@example Heron
struct FourthRootAlgorithm <: Algorithm
    stopping_criterion
    sqrt_algorithm::HeronAlgorithm
end

function AlgorithmsInterface.step!(problem::SqrtProblem, algorithm::FourthRootAlgorithm, state::DefaultState)
    root = solve(problem, algorithm.sqrt_algorithm; name = :first_sqrt, iterate = 1.0)
    state.iterate = solve(SqrtProblem(root), algorithm.sqrt_algorithm; name = :second_sqrt, iterate = 1.0)
    return state
end

fourth_root = FourthRootAlgorithm(StopAfterIteration(1), HeronAlgorithm(StopAfterIteration(5)))
nothing # hide
```

To interact with the logging system, every solve can be given a name, which is the `name` keyword of [`solve`](@ref) and [`solve!`](@ref), and defaults to [`algorithm_name`](@ref), the name of the type of its algorithm.
The logging system will then look up the appropriate logger for that name, such that subsolvers can be independently controlled.

```@example Heron
logger = AlgorithmLogger(
    :FourthRootAlgorithm => AlgorithmLogger(
        :PostStep => iter_printer,
        :second_sqrt => AlgorithmLogger(:PostStep => iter_printer),
    ),
)
with_algorithmlogger(logger) do
    solve(SqrtProblem(16.0), fourth_root; iterate = 1.0)
end
nothing # hide
```

Here the first five lines are the steps of the second square root, and the last one is the single step of the outer algorithm.
Since both subproblems use the same algorithm, only their names tell them apart.
Algorithms that solve subproblems should therefore document the names they use, in the same way as their custom contexts.
Alternatively, a `with_algorithmlogger` scope opened inside `step!` adds to the logger of the running solve, which lets an algorithm configure the logging of its subproblems itself.

## Best practices

### Performance considerations

* Logging actions can be as fast or slow as needed; the overhead is only incurred when they are actually used.
* Algorithms should be mindful of emitting events in hot loops. These events incur an overhead similar to accessing a `ScopedValue` (~10-100 ns), even when no logging action is registered.
* For expensive operations (plotting, I/O), it is often better to collect data during iteration and process afterward.
* Use `set_global_logging_state!(false)` for production benchmarks.

### Guidelines for custom actions

When designing custom logging actions for your algorithms:

* It is good practice to avoid **modifying** the algorithm state, as this might leave the algorithm in an invalid state to continue running.
* The logging state and global state can be mutated as you see fit, but be mindful of properly initializing and resetting the state if so desired.
* If you need to influence the algorithm, use stopping criteria or modify the algorithm itself.
* For generic and reusable actions, document which properties they access from the `problem, algorithm, state` triplet, and be prepared to handle cases where these aren't present.

### Guidelines for custom contexts

When designing custom logging contexts for your algorithms:

* Use descriptive symbol names (`:LineSearchFailed`, `:StepRejected`, `:Refined`).
* Document which contexts your algorithm emits and when.
* Keep context-specific data in `kwargs...` if needed (though the default contexts don't use this).
* Emit events at meaningful decision points, not in tight inner loops.

## Summary

Implementing logging involves three main components:

1. **LoggingAction**: Define what happens when a logging event occurs.
   * Use `CallbackAction` for quick inline functions.
   * Use `StopReasonAction` at `:Stop` to report what made the algorithm stop.
   * Implement custom subtypes for reusable, stateful logging.
   * Implement `handle_message!(action, problem, algorithm, state; kwargs...)`.

2. **AlgorithmLogger**: Map contexts (`:Start`, `:PostStep`, etc.) to actions.
   * Construct with `AlgorithmLogger(:Context => action, ...)`, and activate with `with_algorithmlogger(:Name => logger)`.
   * Use `ActionGroup` to compose multiple actions at one context.
   * Reach subproblems by their `name` with `name => AlgorithmLogger(...)`.

3. **Custom contexts**: Emit domain-specific events from algorithms.
   * Call `emit_message(problem, algorithm, state, :YourContext)`.
   * Document custom contexts in your algorithm's documentation.
   * Use descriptive symbol names.

The logging system is designed for composability and zero-overhead when disabled, letting you instrument algorithms without compromising performance or code clarity.

## Reference API

Auto‑generated documentation for logging infrastructure follows.

```@autodocs
Modules = [AlgorithmsInterface]
Pages = ["logging.jl"]
Order = [:type, :function]
Private = true
```

## Wrap‑up

You have now seen the three pillars of the AlgorithmsInterface:

* [**Interface**](@ref sec_interface): Defining algorithms with `Problem`, `Algorithm`, and `State`.
* [**Stopping criteria**](@ref sec_stopping): Controlling when iteration halts with composable conditions.
* [**Logging**](@ref sec_logging): Instrumenting execution with flexible, composable actions.

Together, these patterns encourage modular, testable, and maintainable iterative algorithm design.
You can now build algorithms that are easy to configure, monitor, and extend without invasive modifications to core logic.
