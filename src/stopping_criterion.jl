@doc """
    StoppingCriterion

An abstract type to represent a stopping criterion of an [`Algorithm`](@ref).

It should usually implement

* [`is_finished!`](@ref)`(problem, algorithm, state, stopping_criterion, stopping_criterion_state)`
* [`is_finished`](@ref)`(problem, algorithm, state, stopping_criterion, stopping_criterion_state)`
* [`get_reason`](@ref)`(stopping_criterion, stopping_criterion_state)`
* [`indicates_convergence`](@ref)`(::Type{<:StoppingCriterion})`

By default, its [`StoppingCriterionState`](@ref) is a [`DefaultStoppingCriterionState`](@ref).
A criterion that needs more should implement
[`initialize_state(problem::Problem, algorithm::Algorithm, stopping_criterion::StoppingCriterion; kwargs...)`](@ref)
to create its own [`StoppingCriterionState`](@ref), as well as the mutating variant to reset it.

Note that only [`indicates_convergence`](@ref) has to be implemented:
it answers whether meeting this criterion *would* mean convergence, which is a static property of the criterion type alone.
Both the variant taking a criterion and the one that additionally takes a [`StoppingCriterionState`](@ref), answering whether it *did* happen are derived from it.
"""
abstract type StoppingCriterion end

@doc """
    StoppingCriterionState

An abstract type to represent a stopping criterion state within a [`State`](@ref).
It represents the concrete state a [`StoppingCriterion`](@ref) is in.

## Properties

In order for the generic convergence reporting to work, the state should contain the following
property, and provide corresponding `getproperty` and `setproperty!` methods.

* `at_iteration` – the iteration at which the accompanying [`StoppingCriterion`](@ref) indicated
  to stop, where `0` means it already indicated to stop at the start and any negative number
  means that it has not (yet) indicated to stop.

A state that records its status differently can instead implement
[`is_active`](@ref)`(stopping_criterion, stopping_criterion_state)`.
"""
abstract type StoppingCriterionState end

@doc """
    get_reason(stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)
    get_reason(algorithm::Algorithm, state::State)

Provide a reason in human readable text as to why a [`StoppingCriterion`](@ref) with [`StoppingCriterionState`](@ref) indicated to stop.
If it does not indicate to stop, this should return `nothing`.
The second variant extracts the criterion and its state from `algorithm` and `state`.

Providing the iteration at which this indicated to stop in the reason would be preferable.
Reasons are concatenated when several criteria are combined and are printed verbatim, so they
should end in a newline.

This is meant for human consumption only. To decide programmatically whether a criterion
indicated to stop, use [`is_active`](@ref) instead.
The default returns `nothing`, so a criterion that has no message to provide does not have to implement this.
"""
get_reason(::StoppingCriterion, ::StoppingCriterionState) = nothing

get_reason(algorithm::Algorithm, state::State) =
    get_reason(algorithm.stopping_criterion, state.stopping_criterion_state)

@doc """
    is_active(stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)
    is_active(algorithm::Algorithm, state::State)

Return whether a [`StoppingCriterion`](@ref) in the given [`StoppingCriterionState`](@ref) is
active, that is whether it has indicated to stop during the current run.
The second variant extracts the criterion and its state from `algorithm` and `state`.

This is the machine-readable counterpart of [`get_reason`](@ref) and the predicate the generic convergence reporting is built on.
The default implementation reads the `at_iteration` property of the state, see [`StoppingCriterionState`](@ref),
so it only has to be implemented for a state that records its status differently.
"""
is_active(
    ::StoppingCriterion, stopping_criterion_state::StoppingCriterionState
) = stopping_criterion_state.at_iteration >= 0

is_active(algorithm::Algorithm, state::State) =
    is_active(algorithm.stopping_criterion, state.stopping_criterion_state)

@doc """
    indicates_convergence(::Type{<:StoppingCriterion})
    indicates_convergence(stopping_criterion::StoppingCriterion)

Return whether or not a [`StoppingCriterion`](@ref) indicates convergence.

This is a static property of the criterion itself and independent of any run:
it answers whether meeting this criterion *would* allow to conclude that the algorithm converged.
Since it does not depend on the values a criterion is configured with, it is answered in the type domain, and a new criterion should implement the variant taking the type.
The default is `false`, which is the conservative answer for a criterion that makes no such promise,
for example a budget such as [`StopAfterIteration`](@ref).
"""
indicates_convergence(::Type{<:StoppingCriterion}) = false

indicates_convergence(stopping_criterion::StoppingCriterion) = indicates_convergence(typeof(stopping_criterion))

@doc """
    indicates_convergence(stopping_criterion::StoppingCriterion, ::StoppingCriterionState)
    indicates_convergence(algorithm::Algorithm, state::State)

Return whether or not a [`StoppingCriterion`](@ref) indicates convergence when it is in [`StoppingCriterionState`](@ref),
i.e. also check whether the state indicates that the criterion has been active.
The second variant extracts the criterion and its state from `algorithm` and `state`.

If so it returns whether `stopping_criterion` itself indicates convergence, otherwise it returns `false`,
since the algorithm has then not yet stopped.
"""
function indicates_convergence(
        stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState,
    )
    return is_active(stopping_criterion, stopping_criterion_state) &&
        indicates_convergence(stopping_criterion)
end

indicates_convergence(algorithm::Algorithm, state::State) =
    indicates_convergence(algorithm.stopping_criterion, state.stopping_criterion_state)

_doc_is_finished = """
    is_finished(problem::Problem, algorithm::Algorithm, state::State)
    is_finished(problem::Problem, algorithm::Algorithm, state::State, stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)
    is_finished!(problem::Problem, algorithm::Algorithm, state::State)
    is_finished!(problem::Problem, algorithm::Algorithm, state::State, stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)

Indicate whether an [`Algorithm`](@ref) solving [`Problem`](@ref) is finished having reached a certain [`State`](@ref).
The variant with three arguments by default extracts the [`StoppingCriterion`](@ref) and its [`StoppingCriterionState`](@ref)
and their actual checks are performed in the implementation with five arguments.

The mutating variant alters the `stopping_criterion_state` and is only called once per iteration,
the other one merely inspects the current status without mutation.
"""

@doc "$(_doc_is_finished)"
function is_finished(problem::Problem, algorithm::Algorithm, state::State)
    return is_finished(
        problem, algorithm, state,
        algorithm.stopping_criterion, state.stopping_criterion_state,
    )
end

@doc "$(_doc_is_finished)"
is_finished(::Problem, ::Algorithm, ::State, ::StoppingCriterion, ::StoppingCriterionState)

@doc "$(_doc_is_finished)"
function is_finished!(problem::Problem, algorithm::Algorithm, state::State)
    return is_finished!(
        problem, algorithm, state,
        algorithm.stopping_criterion, state.stopping_criterion_state,
    )
end

@doc "$(_doc_is_finished)"
is_finished!(::Problem, ::Algorithm, ::State, ::StoppingCriterion, ::StoppingCriterionState)

@doc """
    summary(io::IO, stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)
    summary(stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)

Provide a summary of the status of a stopping criterion – its parameters and whether
it currently indicates to stop. The first variant prints the summary to `io`,
the second returns it as a string.

# Example

For the [`StopAfterIteration`](@ref) criterion, the summary looks like

```
Max Iterations (15): not reached
```
"""
Base.summary(io::IO, ::StoppingCriterion, ::StoppingCriterionState)

function Base.summary(
        stopping_criterion::StoppingCriterion,
        stopping_criterion_state::StoppingCriterionState
    )
    io = IOBuffer()
    summary(io, stopping_criterion, stopping_criterion_state)
    return String(take!(io))
end

@doc """
    get_active_stopping_criteria(stopping_criterion::StoppingCriterion, stopping_criterion_state::StoppingCriterionState)
    get_active_stopping_criteria(algorithm::Algorithm, state::State)

Return all `(stopping_criterion, stopping_criterion_state)` pairs for which the criterion
[`is_active`](@ref), as a vector.
The variant with two arguments extracts the criterion and its state from `algorithm` and `state`.

Meta criteria such as [`StopWhenAll`](@ref) and [`StopWhenAny`](@ref) are recursed into and do not
appear themselves, so the result only contains the criteria that actually became active.
This lets a caller distinguish *why* an algorithm stopped, which is more fine grained than
[`indicates_convergence`](@ref): stopping because a step size collapsed and stopping because an
iteration budget ran out both fail to indicate convergence, but usually warrant different action.

The default treats a criterion as a leaf, so a new criterion that itself combines others has to
implement this to be recursed into.
"""
function get_active_stopping_criteria(
        stopping_criterion::StoppingCriterion,
        stopping_criterion_state::StoppingCriterionState,
    )
    pairs = Tuple{StoppingCriterion, StoppingCriterionState}[]
    is_active(stopping_criterion, stopping_criterion_state) &&
        push!(pairs, (stopping_criterion, stopping_criterion_state))
    return pairs
end

get_active_stopping_criteria(algorithm::Algorithm, state::State) =
    get_active_stopping_criteria(algorithm.stopping_criterion, state.stopping_criterion_state)

#
#
# Meta StoppingCriteria
@doc raw"""
    StopWhenAll <: StoppingCriterion

Store a tuple of [`StoppingCriterion`](@ref)s and indicate to stop
when _all_ of them indicate to stop.

# Constructor

    StopWhenAll(c::AbstractVector{<:StoppingCriterion})
    StopWhenAll(c::StoppingCriterion...)
"""
struct StopWhenAll{TCriteria <: Tuple} <: StoppingCriterion
    criteria::TCriteria
    StopWhenAll(c::StoppingCriterion...) = new{typeof(c)}(c)
end
StopWhenAll(c::AbstractVector{<:StoppingCriterion}) = StopWhenAll(c...)

@doc """
    indicates_convergence(::Type{<:StopWhenAll})

A [`StopWhenAll`](@ref) indicates convergence whenever *one* of its criteria does.

Since it can only indicate to stop once every one of its criteria does, a single criterion that
allows to conclude convergence is enough to conclude it for the group as a whole.
Note how this is the opposite quantifier from [`StopWhenAny`](@ref).
"""
function indicates_convergence(::Type{StopWhenAll{TCriteria}}) where {TCriteria <: Tuple}
    return any(indicates_convergence, fieldtypes(TCriteria))
end

function Base.show(io::IO, ::MIME"text/plain", stop_when_all::StopWhenAll)
    print(io, "StopWhenAll with the Stopping Criteria:")
    for stopping_criterion in stop_when_all.criteria
        print(io, "\n\t")
        replace(io, sprint(show, stopping_criterion; context = io), "\n" => "\n\t") # increase indent
    end
    return nothing
end

"""
    &(s1,s2)
    s1 & s2

Combine two [`StoppingCriterion`](@ref) within an [`StopWhenAll`](@ref).
If either `s1` (or `s2`) is already an [`StopWhenAll`](@ref), then `s2` (or `s1`) is
appended to the list of [`StoppingCriterion`](@ref) within `s1` (or `s2`).

# Example
    a = StopAfterIteration(200) & StopAfter(Minute(1))

Is the same as

    a = StopWhenAll(StopAfterIteration(200), StopAfter(Minute(1)))
"""
Base.:&(s1::StoppingCriterion, s2::StoppingCriterion) = StopWhenAll(s1, s2)
Base.:&(s1::StoppingCriterion, s2::StopWhenAll) = StopWhenAll(s1, s2.criteria...)
Base.:&(s1::StopWhenAll, s2::StoppingCriterion) = StopWhenAll(s1.criteria..., s2)
Base.:&(s1::StopWhenAll, s2::StopWhenAll) = StopWhenAll(s1.criteria..., s2.criteria...)

@doc raw"""
    StopWhenAny <: StoppingCriterion

Store a tuple of [`StoppingCriterion`](@ref) elements and indicate to stop
when _any_ single one indicates to stop. The `reason` is given by the
concatenation of all reasons (assuming that all non-indicating ones return `nothing`).

# Constructors

    StopWhenAny(c::AbstractVector{<:StoppingCriterion})
    StopWhenAny(c::StoppingCriterion...)
"""
struct StopWhenAny{TCriteria <: Tuple} <: StoppingCriterion
    criteria::TCriteria
    StopWhenAny(c::StoppingCriterion...) = new{typeof(c)}(c)
end
StopWhenAny(c::AbstractVector{<:StoppingCriterion}) = StopWhenAny(c...)

@doc """
    indicates_convergence(::Type{<:StopWhenAny})

A [`StopWhenAny`](@ref) indicates convergence only when *all* of its criteria do.

Since any single one of its criteria can make it indicate to stop, the group offers no guarantee
unless every criterion it is composed of allows to conclude convergence on its own.
Note how this is the opposite quantifier from [`StopWhenAll`](@ref).

This is deliberately pessimistic, and is why a `tolerance | budget` combination is never
convergent as a criterion. To ask whether a *particular run* stopped because the convergence
criterion is what triggered, pass the accompanying [`GroupStoppingCriterionState`](@ref) as well.
"""
function indicates_convergence(::Type{StopWhenAny{TCriteria}}) where {TCriteria <: Tuple}
    return all(indicates_convergence, fieldtypes(TCriteria))
end

function Base.show(io::IO, ::MIME"text/plain", stop_when_any::StopWhenAny)
    print(io, "StopWhenAny with the Stopping Criteria:")
    for stopping_criterion in stop_when_any.criteria
        print(io, "\n\t")
        replace(io, sprint(show, stopping_criterion; context = io), "\n" => "\n\t") # increase indent
    end
    return nothing
end

"""
    |(s1,s2)
    s1 | s2

Combine two [`StoppingCriterion`](@ref) within an [`StopWhenAny`](@ref).
If either `s1` (or `s2`) is already an [`StopWhenAny`](@ref), then `s2` (or `s1`) is
appended to the list of [`StoppingCriterion`](@ref) within `s1` (or `s2`)

# Example
    a = StopAfterIteration(200) | StopAfter(Minute(1))

Is the same as

    a = StopWhenAny(StopAfterIteration(200), StopAfter(Minute(1)))
"""
Base.:|(s1::StoppingCriterion, s2::StoppingCriterion) = StopWhenAny(s1, s2)
Base.:|(s1::StoppingCriterion, s2::StopWhenAny) = StopWhenAny(s1, s2.criteria...)
Base.:|(s1::StopWhenAny, s2::StoppingCriterion) = StopWhenAny(s1.criteria..., s2)
Base.:|(s1::StopWhenAny, s2::StopWhenAny) = StopWhenAny(s1.criteria..., s2.criteria...)

# A common state for stopping criteria working on tuples of stopping criteria
"""
    GroupStoppingCriterionState <: StoppingCriterionState

A [`StoppingCriterionState`](@ref) that groups multiple [`StoppingCriterionState`](@ref)s
internally as a tuple.
This is for example used in combination with [`StopWhenAny`](@ref) and [`StopWhenAll`](@ref).

# Constructor

    GroupStoppingCriterionState(c::StoppingCriterionState...)
"""
mutable struct GroupStoppingCriterionState{TCriteriaStates <: Tuple} <: StoppingCriterionState
    criteria_states::TCriteriaStates
    at_iteration::Int
    GroupStoppingCriterionState(c::StoppingCriterionState...) = new{typeof(c)}(c, -1)
end

function get_reason(
        stop_when::Union{StopWhenAll, StopWhenAny},
        stopping_criterion_states::GroupStoppingCriterionState,
    )
    is_active(stop_when, stopping_criterion_states) || return nothing
    # only the children that did indicate to stop have anything to report, and of those the ones
    # without a message return `nothing`, which `join` would render as the literal text "nothing"
    reasons = (
        get_reason(stopping_criterion, stopping_criterion_state) for
            (stopping_criterion, stopping_criterion_state) in
            zip(stop_when.criteria, stopping_criterion_states.criteria_states)
            if is_active(stopping_criterion, stopping_criterion_state)
    )
    reason = join(Iterators.filter(!isnothing, reasons))
    # a group that indicated to stop but collected no message at all has nothing to say either,
    # and must not report the empty string, which would read as a message to any consumer
    return isempty(reason) ? nothing : reason
end

@doc """
    indicates_convergence(stop_when::Union{StopWhenAll, StopWhenAny}, ::GroupStoppingCriterionState)

Return whether a group of stopping criteria stopped because of convergence.

Unlike the variant without a state, which can only reason about the criteria types themselves, this
consults the accompanying [`StoppingCriterionState`](@ref)s and therefore only takes the
children that actually indicated to stop into account. A group indicates convergence as soon as
*one* of those children does, so a [`StopWhenAny`](@ref) combining a convergence criterion with a
fallback such as [`StopAfterIteration`](@ref) still reports convergence whenever the convergence
criterion is what triggered.
"""
function indicates_convergence(
        stop_when::Union{StopWhenAll, StopWhenAny},
        stopping_criterion_states::GroupStoppingCriterionState,
    )
    is_active(stop_when, stopping_criterion_states) || return false
    return any(
        st -> indicates_convergence(st[1], st[2]),
        zip(stop_when.criteria, stopping_criterion_states.criteria_states),
    )
end

function get_active_stopping_criteria(
        stop_when::Union{StopWhenAll, StopWhenAny},
        stopping_criterion_states::GroupStoppingCriterionState,
    )
    pairs = Tuple{StoppingCriterion, StoppingCriterionState}[]
    # recurse rather than report the group itself: `&` and `|` flatten, but a mixed combination
    # such as `(c1 | c2) & c3` genuinely nests
    for (stopping_criterion, stopping_criterion_state) in
        zip(stop_when.criteria, stopping_criterion_states.criteria_states)
        append!(
            pairs,
            get_active_stopping_criteria(stopping_criterion, stopping_criterion_state),
        )
    end
    return pairs
end

function initialize_state(
        problem::Problem, algorithm::Algorithm, stop_when::Union{StopWhenAll, StopWhenAny};
        kwargs...,
    )
    return GroupStoppingCriterionState(
        (
            initialize_state(problem, algorithm, stopping_criterion; kwargs...) for
                stopping_criterion in stop_when.criteria
        )...,
    )
end
function initialize_state!(
        problem::Problem, algorithm::Algorithm, stop_when::Union{StopWhenAll, StopWhenAny},
        stopping_criterion_states::GroupStoppingCriterionState;
        kwargs...,
    )
    for (stopping_criterion_state, stopping_criterion) in
        zip(stopping_criterion_states.criteria_states, stop_when.criteria)
        initialize_state!(
            problem, algorithm, stopping_criterion, stopping_criterion_state;
            kwargs...,
        )
    end
    stopping_criterion_states.at_iteration = -1
    return stopping_criterion_states
end

function is_finished(
        problem::Problem, algorithm::Algorithm, state::State,
        stop_when_all::StopWhenAll, stopping_criterion_states::GroupStoppingCriterionState,
    )
    # short-circuiting is fine here: unlike `is_finished!`, this may not mutate, so there is no
    # child left starved of an update by not being asked
    return all(
        st -> is_finished(problem, algorithm, state, st[1], st[2]),
        zip(stop_when_all.criteria, stopping_criterion_states.criteria_states),
    )
end
function is_finished!(
        problem::Problem, algorithm::Algorithm, state::State,
        stop_when_all::StopWhenAll, stopping_criterion_states::GroupStoppingCriterionState,
    )
    k = state.iteration
    (k == 0) && (stopping_criterion_states.at_iteration = -1) # reset on init
    # `map` rather than `all`, so that every child is updated exactly once per iteration:
    # `all` would short-circuit and starve stateful criteria of the current iterate
    finished = map(
        stop_when_all.criteria, stopping_criterion_states.criteria_states
    ) do stopping_criterion, stopping_criterion_state
        is_finished!(problem, algorithm, state, stopping_criterion, stopping_criterion_state)
    end
    if all(finished)
        stopping_criterion_states.at_iteration = k
        return true
    end
    return false
end

function is_finished(
        problem::Problem, algorithm::Algorithm, state::State,
        stop_when_any::StopWhenAny, stopping_criterion_states::GroupStoppingCriterionState,
    )
    # short-circuiting is fine here: unlike `is_finished!`, this may not mutate, so there is no
    # child left starved of an update by not being asked
    return any(
        st -> is_finished(problem, algorithm, state, st[1], st[2]),
        zip(stop_when_any.criteria, stopping_criterion_states.criteria_states),
    )
end
function is_finished!(
        problem::Problem, algorithm::Algorithm, state::State,
        stop_when_any::StopWhenAny, stopping_criterion_states::GroupStoppingCriterionState,
    )
    k = state.iteration
    (k == 0) && (stopping_criterion_states.at_iteration = -1) # reset on init
    # `map` rather than `any`, so that every child is updated exactly once per iteration:
    # `any` would short-circuit and starve stateful criteria of the current iterate, and
    # leave their `at_iteration` unset even though they did indicate to stop
    finished = map(
        stop_when_any.criteria, stopping_criterion_states.criteria_states
    ) do stopping_criterion, stopping_criterion_state
        is_finished!(problem, algorithm, state, stopping_criterion, stopping_criterion_state)
    end
    if any(finished)
        stopping_criterion_states.at_iteration = k
        return true
    end
    return false
end

function Base.summary(
        io::IO,
        stop_when_any::StopWhenAny, stopping_criterion_states::GroupStoppingCriterionState,
    )
    has_stopped = is_active(stop_when_any, stopping_criterion_states)
    s = has_stopped ? "reached" : "not reached"
    r = "Stop when _one_ of the following are fulfilled:\n"
    for (stopping_criterion, stopping_criterion_state) in
        zip(stop_when_any.criteria, stopping_criterion_states.criteria_states)
        t = replace(summary(stopping_criterion, stopping_criterion_state), "\n" => "\n\t")
        r = "$(r)\t$(t)\n"
    end
    return print(io, "$(r)Overall: $(s)")
end
function Base.summary(
        io::IO,
        stop_when_all::StopWhenAll, stopping_criterion_states::GroupStoppingCriterionState,
    )
    has_stopped = is_active(stop_when_all, stopping_criterion_states)
    s = has_stopped ? "reached" : "not reached"
    r = "Stop when _all_ of the following are fulfilled:\n"
    for (stopping_criterion, stopping_criterion_state) in
        zip(stop_when_all.criteria, stopping_criterion_states.criteria_states)
        t = replace(summary(stopping_criterion, stopping_criterion_state), "\n" => "\n\t")
        r = "$(r)\t$(t)\n"
    end
    return print(io, "$(r)Overall: $(s)")
end

#
#
# Concrete Stopping Criteria

@doc raw"""
    StopAfterIteration <: StoppingCriterion

A simple stopping criterion to stop after a maximal number of iterations.

# Fields

* `max_iterations` stores the iteration number at which to stop.

# Constructor

    StopAfterIteration(max_iterations)

Initialize the criterion to indicate stopping after `max_iterations` iterations.
"""
struct StopAfterIteration <: StoppingCriterion
    max_iterations::Int
end

"""
    DefaultStoppingCriterionState <: StoppingCriterionState

A [`StoppingCriterionState`](@ref) that does not require any information besides
storing the iteration number at which it (last) indicated to stop.

It is also the default return value for [`initialize_state`](@ref) for a [`StoppingCriterion`](@ref).

# Fields

* `at_iteration::Int` stores the iteration number at which this state indicated to stop.
  * `0` means it already indicated to stop at the start.
  * any negative number means that it has not yet indicated to stop.
"""
mutable struct DefaultStoppingCriterionState <: StoppingCriterionState
    at_iteration::Int
    DefaultStoppingCriterionState() = new(-1)
end

# Fallbacks for criteria without a state of their own
initialize_state(::Problem, ::Algorithm, ::StoppingCriterion; kwargs...) =
    DefaultStoppingCriterionState()
function initialize_state!(
        ::Problem, ::Algorithm, ::StoppingCriterion,
        stopping_criterion_state::DefaultStoppingCriterionState;
        kwargs...,
    )
    stopping_criterion_state.at_iteration = -1
    return stopping_criterion_state
end

function is_finished(
        ::Problem, ::Algorithm, state::State,
        stop_after_iteration::StopAfterIteration,
        stopping_criterion_state::DefaultStoppingCriterionState,
    )
    return state.iteration >= stop_after_iteration.max_iterations
end
function is_finished!(
        ::Problem, ::Algorithm, state::State,
        stop_after_iteration::StopAfterIteration,
        stopping_criterion_state::DefaultStoppingCriterionState,
    )
    k = state.iteration
    (k == 0) && (stopping_criterion_state.at_iteration = -1)
    if k >= stop_after_iteration.max_iterations
        stopping_criterion_state.at_iteration = k
        return true
    end
    return false
end
function get_reason(
        stop_after_iteration::StopAfterIteration,
        stopping_criterion_state::DefaultStoppingCriterionState,
    )
    if is_active(stop_after_iteration, stopping_criterion_state)
        return "At iteration $(stopping_criterion_state.at_iteration) the algorithm reached its maximal number of iterations ($(stop_after_iteration.max_iterations)).\n"
    end
    return nothing
end
function Base.summary(
        io::IO,
        stop_after_iteration::StopAfterIteration,
        stopping_criterion_state::DefaultStoppingCriterionState,
    )
    has_stopped = is_active(stop_after_iteration, stopping_criterion_state)
    s = has_stopped ? "reached" : "not reached"
    return print(io, "Max Iterations ($(stop_after_iteration.max_iterations)): $s")
end

"""
    StopAfter <: StoppingCriterion

Stores a threshold for stopping based on the total runtime. It uses
`time_ns()` to measure the time, and you provide a `Period` as the time limit,
for example `Minute(15)`.

# Fields

* `threshold` stores the `Period` after which to stop.

# Constructor

    StopAfter(t::Period)

Initialize the stopping criterion to stop after the `Period` `t` has elapsed.
"""
struct StopAfter <: StoppingCriterion
    threshold::Period
    function StopAfter(t::Period)
        if value(t) < 0
            throw(ArgumentError("You must provide a positive time period"))
        else
            s = new(t)
        end
        return s
    end
end

@doc """
    StopAfterTimePeriodState <: StoppingCriterionState

A state for stopping criteria that are based on time measurements,
for example [`StopAfter`](@ref).

# Fields

* `start` stores the starting time, recorded when the algorithm is started (the call with `k=0`).
* `time` stores the elapsed time.
* `at_iteration` indicates at which iteration (including `k=0`) the stopping criterion
  was fulfilled, and is `-1` while it is not fulfilled.
"""
mutable struct StopAfterTimePeriodState <: StoppingCriterionState
    start::Nanosecond
    time::Nanosecond
    at_iteration::Int
    function StopAfterTimePeriodState()
        return new(Nanosecond(0), Nanosecond(0), -1)
    end
end

initialize_state(::Problem, ::Algorithm, ::StopAfter; kwargs...) =
    StopAfterTimePeriodState()

function initialize_state!(
        ::Problem, ::Algorithm, ::StopAfter,
        stopping_criterion_state::StopAfterTimePeriodState;
        kwargs...,
    )
    stopping_criterion_state.start = Nanosecond(0)
    stopping_criterion_state.time = Nanosecond(0)
    stopping_criterion_state.at_iteration = -1
    return stopping_criterion_state
end

function is_finished(
        ::Problem, ::Algorithm, state::State,
        stop_after::StopAfter, stop_after_state::StopAfterTimePeriodState,
    )
    k = state.iteration
    # Read the clock rather than the `time` recorded by the last `is_finished!`, so that this
    # reports on the time elapsed *now*. Only the timer itself may not be (re)started here.
    (k <= 0 || value(stop_after_state.start) == 0) && return false
    return (Nanosecond(time_ns()) - stop_after_state.start) > Nanosecond(stop_after.threshold)
end
function is_finished!(
        ::Problem, ::Algorithm, state::State,
        stop_after::StopAfter, stop_after_state::StopAfterTimePeriodState,
    )
    k = state.iteration
    if value(stop_after_state.start) == 0 || k <= 0 # (re)start timer
        stop_after_state.at_iteration = -1
        stop_after_state.start = Nanosecond(time_ns())
        stop_after_state.time = Nanosecond(0)
    else
        stop_after_state.time = Nanosecond(time_ns()) - stop_after_state.start
        if k > 0 && (stop_after_state.time > Nanosecond(stop_after.threshold))
            stop_after_state.at_iteration = k
            return true
        end
    end
    return false
end
function get_reason(
        stop_after::StopAfter,
        stopping_criterion_state::StopAfterTimePeriodState,
    )
    if is_active(stop_after, stopping_criterion_state)
        return "After iteration $(stopping_criterion_state.at_iteration) the algorithm ran for $(floor(stopping_criterion_state.time, typeof(stop_after.threshold))) (threshold: $(stop_after.threshold)).\n"
    end
    return nothing
end
function Base.summary(
        io::IO,
        stop_after::StopAfter, stopping_criterion_state::StopAfterTimePeriodState,
    )
    has_stopped = is_active(stop_after, stopping_criterion_state)
    s = has_stopped ? "reached" : "not reached"
    return print(io, "stopped after $(stop_after.threshold): $s")
end

@doc raw"""
    StopWhenBelow <: StoppingCriterion

Stop as soon as a quantity computed from the [`State`](@ref) is at most a threshold.
This indicates convergence.

# Fields

* `quantity` is a function `(problem, algorithm, state) -> value`.
* `threshold` is the value below which to stop.

[`get_reason`](@ref) and `summary` refer to the quantity by `nameof(quantity)`, or as
"value" for an anonymous function or a callable object.

# Example

```julia
gradient_norm(problem, algorithm, state) = norm(state.gradient)
StopWhenBelow(gradient_norm, 1e-8) | StopAfterIteration(100)
```
"""
struct StopWhenBelow{F, T <: Real} <: StoppingCriterion
    quantity::F
    threshold::T
end

_quantity_name(stop_when_below::StopWhenBelow) = _quantity_name(stop_when_below.quantity)
_quantity_name(quantity) = "value"
function _quantity_name(quantity::Function)
    name = string(nameof(quantity))
    return startswith(name, '#') ? "value" : name
end

indicates_convergence(::Type{<:StopWhenBelow}) = true

@doc """
    StopWhenBelowState{T} <: StoppingCriterionState

The state of a [`StopWhenBelow`](@ref) criterion, where `T` is the floating point type of its
threshold.

# Fields

* `value` stores the quantity at the last check, `NaN` before the first one.
* `at_iteration` indicates at which iteration the criterion was fulfilled,
  and is `-1` while it is not fulfilled.
"""
mutable struct StopWhenBelowState{T <: Real} <: StoppingCriterionState
    value::T
    at_iteration::Int
end

initialize_state(::Problem, ::Algorithm, stop_when_below::StopWhenBelow; kwargs...) =
    StopWhenBelowState{float(typeof(stop_when_below.threshold))}(NaN, -1)

function initialize_state!(
        ::Problem, ::Algorithm, ::StopWhenBelow,
        stopping_criterion_state::StopWhenBelowState;
        kwargs...,
    )
    stopping_criterion_state.value = NaN
    stopping_criterion_state.at_iteration = -1
    return stopping_criterion_state
end

function is_finished(
        problem::Problem, algorithm::Algorithm, state::State,
        stop_when_below::StopWhenBelow, ::StopWhenBelowState,
    )
    return stop_when_below.quantity(problem, algorithm, state) <= stop_when_below.threshold
end
function is_finished!(
        problem::Problem, algorithm::Algorithm, state::State,
        stop_when_below::StopWhenBelow, stopping_criterion_state::StopWhenBelowState,
    )
    k = state.iteration
    (k == 0) && (stopping_criterion_state.at_iteration = -1)
    value = stop_when_below.quantity(problem, algorithm, state)
    stopping_criterion_state.value = value
    if value <= stop_when_below.threshold
        stopping_criterion_state.at_iteration = k
        return true
    end
    return false
end
function get_reason(
        stop_when_below::StopWhenBelow,
        stopping_criterion_state::StopWhenBelowState,
    )
    if is_active(stop_when_below, stopping_criterion_state)
        return "At iteration $(stopping_criterion_state.at_iteration) the $(_quantity_name(stop_when_below)) ($(stopping_criterion_state.value)) reached the threshold ($(stop_when_below.threshold)).\n"
    end
    return nothing
end
function Base.summary(
        io::IO,
        stop_when_below::StopWhenBelow, stopping_criterion_state::StopWhenBelowState,
    )
    has_stopped = is_active(stop_when_below, stopping_criterion_state)
    s = has_stopped ? "reached" : "not reached"
    return print(io, "$(_quantity_name(stop_when_below)) ≤ $(stop_when_below.threshold): $s")
end
