# LoggingAction interface
# -----------------------
"""
    LoggingAction

Abstract supertype for defining an action that generates a log record.

## Methods
Any concrete subtype should at least implement the following method to handle the logging event:

- [`handle_message!(action, problem, algorithm, state, args...; kwargs...)`](@ref handle_message!)
"""
abstract type LoggingAction end

@doc """
    handle_message!(action::LoggingAction, problem::Problem, algorithm::Algorithm, state::State; kwargs...)

Entry-point for defining an implementation of how to handle a logging event for a given [`LoggingAction`](@ref).
""" handle_message!(::LoggingAction, ::Problem, ::Algorithm, ::State; kwargs...)

# Concrete LoggingActions
# -----------------------
"""
    ActionGroup(actions::LoggingAction...)
    ActionGroup(actions::Vector{<:LoggingAction})

Concrete [`LoggingAction`](@ref) that can be used to sequentially perform each of the `actions`.
"""
struct ActionGroup{A <: LoggingAction} <: LoggingAction
    actions::Vector{A}
end
ActionGroup(actions::LoggingAction...) = ActionGroup(collect(LoggingAction, actions))

function handle_message!(
        action::ActionGroup, problem::Problem, algorithm::Algorithm, state::State; kwargs...
    )
    for child in action.actions
        handle_message!(child, problem, algorithm, state; kwargs...)
    end
    return nothing
end

"""
    CallbackAction(callback)

Concrete [`LoggingAction`](@ref) that handles a logging event through an arbitrary callback function.
The callback function must have the following signature:
```julia
callback(problem, algorithm, state; kwargs...) = ...
```
Here `kwargs...` are optional and can be filled out with context-specific information.
"""
struct CallbackAction{F} <: LoggingAction
    callback::F
end

function handle_message!(
        action::CallbackAction, problem::Problem, algorithm::Algorithm, state::State; kwargs...
    )
    action.callback(problem, algorithm, state; kwargs...)
    return nothing
end

"""
    IfAction(predicate, action)

Concrete [`LoggingAction`](@ref) that wraps another action and hides it behind a clause, only
emitting logging events whenever the `predicate` evaluates to true. The `predicate` must have
the signature:
```julia
predicate(problem, algorithm, state; kwargs...)::Bool
```
"""
struct IfAction{F, A <: LoggingAction} <: LoggingAction
    predicate::F
    action::A
end

function handle_message!(
        action::IfAction, problem::Problem, algorithm::Algorithm, state::State; kwargs...
    )
    return action.predicate(problem, algorithm, state; kwargs...) ?
        handle_message!(action.action, problem, algorithm, state; kwargs...) :
        nothing
end

"""
    StopReasonAction(io::IO = stdout; prefix::String = "")

Concrete [`LoggingAction`](@ref) that reports why an algorithm stopped, by printing
[`get_reason`](@ref) of its [`StoppingCriterion`](@ref) prefixed by `prefix`.

This is intended for the `:Stop` context:

```julia
with_algorithmlogger(:Stop => StopReasonAction()) do
    solve(problem, algorithm)
end
```

Nothing is printed while no criterion has indicated to stop, so registering this on another
context is harmless.

See also [`indicates_convergence`](@ref) to distinguish stopping because of convergence from
merely running out of budget, and [`get_active_stopping_criteria`](@ref) to inspect which
criteria became active.
"""
struct StopReasonAction <: LoggingAction
    io::IO
    prefix::String
end
StopReasonAction(io::IO = stdout; prefix::String = "") = StopReasonAction(io, prefix)

function handle_message!(
        action::StopReasonAction, ::Problem, algorithm::Algorithm, state::State; kwargs...
    )
    reason = get_reason(algorithm, state)
    isnothing(reason) || print(action.io, action.prefix, reason)
    return nothing
end

"""
    NoLogging()

Concrete [`LoggingAction`](@ref) that does nothing.
Registering it for a context silences that context, also for actions coming from enclosing
scopes.
"""
struct NoLogging <: LoggingAction end

handle_message!(::NoLogging, ::Problem, ::Algorithm, ::State; kwargs...) = nothing

# Algorithm Logger
# ----------------
"""
    AlgorithmLogger(context => action, ..., name => logger, ...) -> logger

Logging transformer that handles the logic of dispatching logging events to logging actions.
This is implemented through `logger[context]`.

A `context => action` pair maps the events of `context` emitted by the solve using this logger
to `action`.
A `name => logger` pair, with `logger::AlgorithmLogger`, is the logger of the solves named
`name` started from within that solve.

Every [`solve`](@ref) descends one level: a solve named `name` uses the `name => logger` entry
of the logger of the current scope, and no logging happens when there is no such entry.
A solve that is not given a `name` is named by [`algorithm_name`](@ref).

```julia
AlgorithmLogger(
    :GradientDescent => AlgorithmLogger(
        :PostStep => print_iteration,
        :linesearch => AlgorithmLogger(:Stop => StopReasonAction()),
    ),
)
```

See also the scoped value [`AlgorithmsInterface.algorithm_logger`](@ref).
"""
struct AlgorithmLogger
    actions::Dict{Symbol, LoggingAction}
    loggers::Dict{Symbol, AlgorithmLogger}
end
function AlgorithmLogger(@nospecialize(args::Pair...))
    logger = AlgorithmLogger(Dict{Symbol, LoggingAction}(), Dict{Symbol, AlgorithmLogger}())
    for (key, value) in args
        if value isa AlgorithmLogger
            logger.loggers[key] = value
        else
            logger.actions[key] = value
        end
    end
    return logger
end

Base.getindex(logger::AlgorithmLogger, context::Symbol) = get(logger.actions, context, nothing)

Base.isempty(logger::AlgorithmLogger) = isempty(logger.actions) && isempty(logger.loggers)

_isactive(logger::AlgorithmLogger) =
    any(action -> !(action isa NoLogging), values(logger.actions)) ||
    any(_isactive, values(logger.loggers))

"""
    merge(outer::AlgorithmLogger, inner::AlgorithmLogger) -> AlgorithmLogger

Layer the logger of a scope `inner` on top of that of its enclosing scope `outer`.
A context present in both runs the outer action and then the inner one, unless either is
[`NoLogging`](@ref).
Named loggers present in both are merged in the same way.
"""
function Base.merge(outer::AlgorithmLogger, inner::AlgorithmLogger)
    isempty(outer) && return inner
    isempty(inner) && return outer
    actions = mergewith(_layer, outer.actions, inner.actions)
    loggers = mergewith(merge, outer.loggers, inner.loggers)
    return AlgorithmLogger(actions, loggers)
end

_layer(outer::LoggingAction, inner::LoggingAction) =
    outer isa NoLogging || inner isa NoLogging ? inner : ActionGroup(outer, inner)

"""
    with_algorithmlogger(f, (name => logger)::Pair{Symbol, AlgorithmLogger}...; inherit = true)
    with_algorithmlogger(f, logger::AlgorithmLogger; inherit = true)
    with_algorithmlogger((name => logger)::Pair{Symbol, AlgorithmLogger}...; inherit = true) do
        # insert arbitrary code here
    end

Run the given zero-argument function `f()` with `logger` added to the logger of the current scope.
A solve named `name` started in `f` uses the `name => logger` entry, see [`AlgorithmLogger`](@ref).
Inside a solve, `context => action` pairs apply to the events emitted by that solve.

Use `context => NoLogging()` to silence a single context, or `inherit = false` to discard the
logger of enclosing scopes.
By default, the following events trigger a logging action with the given `context`:

|  context  |              event                  |
| --------- | ----------------------------------- |
| :Start    | The solver will start.              |
| :PreStep  | The solver is about to take a step. |
| :PostStep | The solver has taken a step.        |
| :Stop     | The solver has finished.            |

However, further events and actions can be emitted through the [`emit_message`](@ref) interface.

See also the scoped value [`AlgorithmsInterface.algorithm_logger`](@ref).
"""
@inline with_algorithmlogger(f, args::Pair...; inherit::Bool = true) =
    with_algorithmlogger(f, AlgorithmLogger(args...); inherit)
@inline function with_algorithmlogger(f, logger::AlgorithmLogger; inherit::Bool = true)
    inherit && (logger = merge(ALGORITHM_LOGGER[], logger))
    return with(f, ALGORITHM_LOGGER => logger)
end

@doc """
    get_global_logging_state()
    set_global_logging_state!(state::Bool) -> previous_state

Retrieve or set the value to globally enable or disable the handling of logging events.
""" get_global_logging_state, set_global_logging_state!

const LOGGING_ENABLED = Ref(true)

get_global_logging_state() = LOGGING_ENABLED[]
function set_global_logging_state!(state::Bool)
    previous = LOGGING_ENABLED[]
    LOGGING_ENABLED[] = state
    return previous
end

@doc """
    algorithm_logger()::Union{AlgorithmLogger, Nothing}

Retrieve the current logger that is responsible for handling logging events.
The current logger is determined by a `ScopedValue`, which inside a [`solve`](@ref) is the
logger of that solve.
Whenever `nothing` is returned, no logging should happen.

See also [`set_global_logging_state!`](@ref) for globally toggling whether logging should happen.
""" algorithm_logger

const ALGORITHM_LOGGER = ScopedValue(AlgorithmLogger())

function algorithm_logger()
    LOGGING_ENABLED[] || return nothing
    logger = ALGORITHM_LOGGER[]
    _isactive(logger) || return nothing
    return logger
end

"""
    emit_message(problem::Problem, algorithm::Algorithm, state::State, context::Symbol; kwargs...) -> nothing
    emit_message(algorithm_logger, problem::Problem, algorithm::Algorithm, state::State, context::Symbol; kwargs...) -> nothing

Use the current or the provided algorithm logger to handle the logging event of the given `context`.
The first signature should be favored as it correctly handles accessing the `logger` and respecting global toggles for enabling and disabling the logging system.

The second signature should be used exclusively in (very) hot loops, where the overhead of [`AlgorithmsInterface.algorithm_logger()`](@ref) is too large.
In this case, you can manually extract the `algorithm_logger()` once outside of the hot loop.
"""
emit_message(problem::Problem, algorithm::Algorithm, state::State, context::Symbol; kwargs...) =
    emit_message(algorithm_logger(), problem, algorithm, state, context; kwargs...)
emit_message(::Nothing, problem::Problem, algorithm::Algorithm, state::State, context::Symbol; kwargs...) =
    nothing
function emit_message(
        logger::AlgorithmLogger, problem::Problem, algorithm::Algorithm, state::State, context::Symbol;
        kwargs...
    )
    @noinline; @nospecialize
    action::LoggingAction = @something(logger[context], return nothing)

    # Try-catch around logging to avoid stopping the algorithm when a logging action fails
    # but still emit an error message
    try
        handle_message!(action, problem, algorithm, state; kwargs...)
    catch err
        bt = catch_backtrace()
        @error "Error during the handling of a logging action" action exception = (err, bt)
    end
    return nothing
end
