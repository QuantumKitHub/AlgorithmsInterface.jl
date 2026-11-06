using Test
using AlgorithmsInterface
using AlgorithmsInterface: Test as AIT
using Dates

problem = AIT.DummyProblem()

# Helper criteria
# ---------------
# `StopAfterIteration` and `StopAfter` both have `indicates_convergence == false`, so neither can
# exercise the convergence-versus-fallback logic. This one does.
# It also leaves its state to the default, so it exercises the `initialize_state` fallbacks.
struct StopWhenConverged <: StoppingCriterion
    at::Int
end
function AlgorithmsInterface.is_finished(
        ::Problem, ::Algorithm, state::State,
        stop_when_converged::StopWhenConverged, ::DefaultStoppingCriterionState,
    )
    return state.iteration >= stop_when_converged.at
end
function AlgorithmsInterface.is_finished!(
        ::Problem, ::Algorithm, state::State,
        stop_when_converged::StopWhenConverged,
        stopping_criterion_state::DefaultStoppingCriterionState,
    )
    k = state.iteration
    (k == 0) && (stopping_criterion_state.at_iteration = -1)
    if k >= stop_when_converged.at
        stopping_criterion_state.at_iteration = k
        return true
    end
    return false
end
function AlgorithmsInterface.get_reason(
        ::StopWhenConverged, stopping_criterion_state::DefaultStoppingCriterionState,
    )
    stopping_criterion_state.at_iteration < 0 && return nothing
    return "Converged at iteration $(stopping_criterion_state.at_iteration).\n"
end
AlgorithmsInterface.indicates_convergence(::Type{StopWhenConverged}) = true

# Never indicates to stop, but records how many times it was asked, so that short-circuiting
# inside the meta criteria becomes observable.
struct CountingCriterion <: StoppingCriterion end
mutable struct CountingCriterionState <: StoppingCriterionState
    at_iteration::Int
    calls::Int
end
AlgorithmsInterface.initialize_state(::Problem, ::Algorithm, ::CountingCriterion; kwargs...) =
    CountingCriterionState(-1, 0)
function AlgorithmsInterface.initialize_state!(
        ::Problem, ::Algorithm, ::CountingCriterion,
        stopping_criterion_state::CountingCriterionState; kwargs...,
    )
    stopping_criterion_state.at_iteration = -1
    stopping_criterion_state.calls = 0
    return stopping_criterion_state
end
AlgorithmsInterface.is_finished(
    ::Problem, ::Algorithm, ::State, ::CountingCriterion, ::CountingCriterionState
) = false
function AlgorithmsInterface.is_finished!(
        ::Problem, ::Algorithm, ::State, ::CountingCriterion,
        stopping_criterion_state::CountingCriterionState,
    )
    stopping_criterion_state.calls += 1
    return false
end
AlgorithmsInterface.get_reason(::CountingCriterion, ::CountingCriterionState) = nothing
AlgorithmsInterface.indicates_convergence(::Type{CountingCriterion}) = false

# Indicates to stop immediately, but implements nothing beyond the bare minimum: no `get_reason`,
# no `indicates_convergence` and no state of its own, so it exercises the fallbacks for all three.
struct SilentCriterion <: StoppingCriterion end
AlgorithmsInterface.is_finished(
    ::Problem, ::Algorithm, ::State, ::SilentCriterion, ::DefaultStoppingCriterionState
) = true
function AlgorithmsInterface.is_finished!(
        ::Problem, ::Algorithm, state::State, ::SilentCriterion,
        stopping_criterion_state::DefaultStoppingCriterionState,
    )
    stopping_criterion_state.at_iteration = state.iteration
    return true
end

# Records its status somewhere other than `at_iteration`, so it has to override
# `is_active` rather than rely on the default.
struct UnconventionalCriterion <: StoppingCriterion end
mutable struct UnconventionalCriterionState <: StoppingCriterionState
    stopped::Bool
end
AlgorithmsInterface.initialize_state(::Problem, ::Algorithm, ::UnconventionalCriterion; kwargs...) =
    UnconventionalCriterionState(false)
function AlgorithmsInterface.initialize_state!(
        ::Problem, ::Algorithm, ::UnconventionalCriterion,
        stopping_criterion_state::UnconventionalCriterionState; kwargs...,
    )
    stopping_criterion_state.stopped = false
    return stopping_criterion_state
end
AlgorithmsInterface.is_active(
    ::UnconventionalCriterion, stopping_criterion_state::UnconventionalCriterionState
) = stopping_criterion_state.stopped
AlgorithmsInterface.indicates_convergence(::Type{UnconventionalCriterion}) = true

@testset "DefaultStoppingCriterionState" begin
    scs = DefaultStoppingCriterionState()
    @test scs isa StoppingCriterionState
    @test scs.at_iteration == -1
end

@testset "a criterion without a state of its own falls back to the default" begin
    # `SilentCriterion` provides neither `initialize_state` nor `initialize_state!`
    silent = SilentCriterion()
    algorithm = AIT.DummyAlgorithm(silent)

    scs = initialize_state(problem, algorithm, silent)
    @test scs isa DefaultStoppingCriterionState
    @test scs.at_iteration == -1

    scs.at_iteration = 3
    @test initialize_state!(problem, algorithm, silent, scs) === scs
    @test scs.at_iteration == -1

    # a criterion that does provide them keeps its own state type
    counting = CountingCriterion()
    @test initialize_state(
        problem, AIT.DummyAlgorithm(counting), counting,
    ) isa CountingCriterionState
end

@testset "StopAfterIteration" begin
    s1 = StopAfterIteration(2)
    @test s1 isa StoppingCriterion
    @test repr(s1; context = :module => @__MODULE__) == "StopAfterIteration(2)"
    @test !indicates_convergence(s1)
    algorithm = AIT.DummyAlgorithm(s1)
    s1_state = initialize_state(problem, algorithm, s1)
    @test !indicates_convergence(s1, s1_state)
    state_finished = AIT.DummyState(nothing, s1_state, 2)
    alg_state = AIT.DummyState(nothing, s1_state, 1)
    @test is_finished(problem, algorithm, state_finished)
    @test !is_finished(problem, algorithm, alg_state)
    # Fake a stop:
    s1_state.at_iteration = 2
    @test startswith(get_reason(s1, s1_state), "At iteration 2")
    @test endswith(summary(s1, s1_state), ": reached")

    # `get_reason` and `summary` are both gated on `is_active`, so they agree even for
    # an `at_iteration` below `max_iterations`
    s2 = StopAfterIteration(10)
    s2_state = initialize_state(problem, AIT.DummyAlgorithm(s2), s2)
    @test isnothing(get_reason(s2, s2_state))
    @test endswith(summary(s2, s2_state), ": not reached")
    s2_state.at_iteration = 3
    @test !isnothing(get_reason(s2, s2_state))
    @test endswith(summary(s2, s2_state), ": reached")
end

@testset "StopAfter" begin
    s1 = StopAfter(Nanosecond(7))
    @test s1 isa StoppingCriterion
    @test sprint(show, s1; context = :module => @__MODULE__) == "StopAfter(Nanosecond(7))"
    @test_throws ArgumentError StopAfter(Second(-1))

    algorithm = AIT.DummyAlgorithm(s1)
    s1_state = initialize_state(problem, algorithm, s1)
    alg_state = AIT.DummyState(nothing, s1_state, 0)
    # Iteration 0: Start timer
    @test !is_finished!(problem, algorithm, alg_state)
    @test !is_finished(problem, algorithm, alg_state)
    @test isnothing(get_reason(s1, s1_state))
    # The threshold is small enough that any real elapsed time exceeds it
    alg_state.iteration = 2
    @test is_finished!(problem, algorithm, alg_state)
    @test is_finished(problem, algorithm, alg_state)
    @test startswith(get_reason(s1, s1_state), "After iteration 2")
    @test endswith(summary(s1, s1_state), ": reached")

    # The non-mutating variant reads the clock rather than the `time` recorded by the last
    # `is_finished!`, so a stale recording does not make it report "not finished"
    s1_state.time = Nanosecond(0)
    @test is_finished(problem, algorithm, alg_state)
    # but it may not (re)start the timer either, so it stays quiet before the first iteration
    alg_state.iteration = 0
    @test !is_finished(problem, algorithm, alg_state)
end

@testset "StopWhenAll" begin
    c1 = StopAfterIteration(2)
    c2 = StopAfter(Nanosecond(2))
    c3 = StopAfterIteration(3)
    s1 = c1 & c2
    s1b = StopWhenAll([c1, c2])
    @test s1 == s1b
    @test s1 isa StoppingCriterion
    @test sprint((io, x) -> show(io, MIME"text/plain"(), x), s1; context = :module => @__MODULE__) ==
        "StopWhenAll with the Stopping Criteria:\n\tStopAfterIteration(2)\n\tStopAfter(Nanosecond(2))"
    algorithm = AIT.DummyAlgorithm(s1)
    s1_state = initialize_state(problem, algorithm, s1)

    s1_str = summary(s1, s1_state)
    @test contains(s1_str, "Stop when _all_ ")
    @test contains(s1_str, "Overall: not reached")

    @test isnothing(AlgorithmsInterface.get_reason(s1, s1_state))
    alg_state = AIT.DummyState(nothing, s1_state, 1)
    @test !is_finished(problem, algorithm, alg_state)
    # Fake start timer
    s1_state.criteria_states[2].start = Nanosecond(time_ns())
    s1_state.criteria_states[2].time = Nanosecond(7)
    # just time is not enough
    @test !is_finished!(problem, algorithm, alg_state)
    @test !is_finished(problem, algorithm, alg_state)
    alg_state.iteration = 2
    # but now both are
    @test is_finished!(problem, algorithm, alg_state)
    @test !indicates_convergence(s1)
    # check that reset works (a) check with modification
    @test is_finished!(problem, algorithm, alg_state)
    @test is_finished(problem, algorithm, alg_state)
    @test startswith(get_reason(s1, s1_state), "At iteration 2")
    @test alg_state.stopping_criterion_state.at_iteration > 0
    AlgorithmsInterface.initialize_state!(problem, algorithm, s1, s1_state)
    @test s1_state.criteria_states[1].at_iteration == -1
    # Different constructors
    s2 = c1 & c2 & c3
    @test s1 & c3 == s2
    @test c1 & (c2 & c3) == s2
    @test s1 & s2 isa StopWhenAll
end

@testset "StopWhenAny" begin
    c1 = StopAfterIteration(2)
    c2 = StopAfter(Second(1))
    c3 = StopAfterIteration(3)

    s1 = c1 | c2
    @test s1 isa StoppingCriterion
    @test s1 == StopWhenAny([c1, c2])
    @test sprint((io, x) -> show(io, MIME"text/plain"(), x), s1; context = :module => @__MODULE__) ==
        "StopWhenAny with the Stopping Criteria:\n\tStopAfterIteration(2)\n\tStopAfter(Second(1))"
    @test !indicates_convergence(s1)

    algorithm = AIT.DummyAlgorithm(s1)
    s1_state = initialize_state(problem, algorithm, s1)

    s1_str = summary(s1, s1_state)
    @test contains(s1_str, "Stop when _one_ ")
    @test contains(s1_str, "Overall: not reached")

    @test isnothing(AlgorithmsInterface.get_reason(s1, s1_state))
    alg_state = AIT.DummyState(nothing, s1_state, 1)
    @test !is_finished!(problem, algorithm, alg_state)
    @test !is_finished(problem, algorithm, alg_state)
    # Fake two seconds of elapsed time by moving the recorded start into the past -- the
    # non-mutating variant derives the elapsed time from the clock, not from `time`
    s1_state.criteria_states[2].start = Nanosecond(time_ns()) - Nanosecond(Second(2))
    @test is_finished(problem, algorithm, alg_state)
    alg_state.iteration = 2
    @test is_finished(problem, algorithm, alg_state)
    # check that reset works (a) check with modification
    @test is_finished!(problem, algorithm, alg_state)
    @test alg_state.stopping_criterion_state.at_iteration > 0
    AlgorithmsInterface.initialize_state!(problem, algorithm, s1, s1_state)
    @test s1_state.criteria_states[1].at_iteration == -1
    # Different constructors
    s2 = c1 | c2 | c3
    @test s1 | c3 == s2
    @test c1 | (c2 | c3) == s2
    @test s1 | s2 isa StopWhenAny
end

@testset "indicates_convergence with a state" begin
    converging = StopWhenConverged(2)
    fallback = StopAfterIteration(5)

    # A criterion that has not indicated to stop has not converged, whatever it would report
    # once it does.
    algorithm = AIT.DummyAlgorithm(converging)
    scs = initialize_state(problem, algorithm, converging)
    @test indicates_convergence(converging)
    @test !indicates_convergence(converging, scs)
    state = AIT.DummyState(nothing, scs, 1)
    @test !is_finished!(problem, algorithm, state)
    @test !indicates_convergence(converging, scs)
    state.iteration = 2
    @test is_finished!(problem, algorithm, state)
    @test indicates_convergence(converging, scs)

    # `tol | maxiter`: the criteria-only variant is unconditionally `false`, because
    # `indicates_convergence(::Type{<:StopWhenAny}) = all(...)` and the fallback never converges.
    # The state-aware variant has to distinguish the two ways of stopping.
    stop_when = converging | fallback
    @test !indicates_convergence(stop_when)

    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 0)
    @test !is_finished!(problem, algorithm, state)
    @test !indicates_convergence(stop_when, scs)

    state.iteration = 2
    @test is_finished!(problem, algorithm, state)
    @test indicates_convergence(stop_when, scs)
    @test indicates_convergence(converging, scs.criteria_states[1])
    @test !indicates_convergence(fallback, scs.criteria_states[2])

    # only the fallback triggers -> stopped, but not converged
    stop_when = StopWhenConverged(100) | fallback
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 0)
    @test !is_finished!(problem, algorithm, state)
    state.iteration = 5
    @test is_finished!(problem, algorithm, state)
    @test !indicates_convergence(stop_when, scs)

    # and the reason mentions the fallback only -- children that returned `nothing` must not be
    # rendered as the literal text "nothing"
    reason = get_reason(stop_when, scs)
    @test startswith(reason, "At iteration 5")
    @test !contains(reason, "nothing")
end

@testset "is_finished! does not short-circuit" begin
    counter = CountingCriterion()

    # `StopWhenAny`: the first child already indicates to stop
    stop_when = StopAfterIteration(1) | counter
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 1)
    @test is_finished!(problem, algorithm, state)
    @test scs.criteria_states[2].calls == 1

    # `StopWhenAll`: the first child already indicates *not* to stop
    stop_when = counter & StopAfterIteration(1)
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 1)
    @test !is_finished!(problem, algorithm, state)
    @test scs.criteria_states[1].calls == 1
    @test !is_finished!(problem, algorithm, state)
    @test scs.criteria_states[1].calls == 2

    # a reset clears the tally again
    initialize_state!(problem, algorithm, stop_when, scs)
    @test scs.criteria_states[1].calls == 0
end

@testset "is_active" begin
    converging = StopWhenConverged(2)
    algorithm = AIT.DummyAlgorithm(converging)
    scs = initialize_state(problem, algorithm, converging)
    state = AIT.DummyState(nothing, scs, 1)

    @test !is_active(converging, scs)
    @test !is_finished!(problem, algorithm, state)
    @test !is_active(converging, scs)
    state.iteration = 2
    @test is_finished!(problem, algorithm, state)
    @test is_active(converging, scs)
    # a reset clears the record again
    initialize_state!(problem, algorithm, converging, scs)
    @test !is_active(converging, scs)

    # `at_iteration == 0` counts as having indicated to stop, a negative number does not
    scs.at_iteration = 0
    @test is_active(converging, scs)
    scs.at_iteration = -1
    @test !is_active(converging, scs)

    # a state that records its status differently overrides the default
    unconventional = UnconventionalCriterion()
    algorithm = AIT.DummyAlgorithm(unconventional)
    ucs = initialize_state(problem, algorithm, unconventional)
    @test !is_active(unconventional, ucs)
    @test !indicates_convergence(unconventional, ucs)
    ucs.stopped = true
    @test is_active(unconventional, ucs)
    @test indicates_convergence(unconventional, ucs)
end

@testset "fallbacks for a minimal criterion" begin
    silent = SilentCriterion()
    algorithm = AIT.DummyAlgorithm(silent)
    scs = initialize_state(problem, algorithm, silent)
    state = AIT.DummyState(nothing, scs, 1)

    @test is_finished!(problem, algorithm, state)
    @test is_active(silent, scs)
    # neither `get_reason` nor `indicates_convergence` is implemented, and both fall back
    # conservatively instead of throwing a `MethodError`
    @test isnothing(get_reason(silent, scs))
    @test !indicates_convergence(silent)
    @test !indicates_convergence(silent, scs)
end

@testset "group get_reason without any message" begin
    # A group that indicated to stop, but whose only active child has no message, must report
    # `nothing`: the empty string would read as a message to any consumer.
    stop_when = StopWhenAny(SilentCriterion())
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 1)

    @test is_finished!(problem, algorithm, state)
    @test is_active(stop_when, scs)
    @test isnothing(get_reason(stop_when, scs))
    @test !indicates_convergence(stop_when, scs)

    # mixing in a child with a message reports that message only
    stop_when = SilentCriterion() | StopWhenConverged(1)
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 1)
    @test is_finished!(problem, algorithm, state)
    @test get_reason(stop_when, scs) == "Converged at iteration 1.\n"
end

@testset "is_finished does not mutate" begin
    # The non-mutating variant only inspects, so a recorded stop has to survive it -- including
    # at iteration 0, where the mutating variant does reset.
    stop_when = StopWhenConverged(2) | StopAfterIteration(5)
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 2)

    @test is_finished!(problem, algorithm, state)
    at_iteration = scs.at_iteration
    child_at_iterations = map(cs -> cs.at_iteration, scs.criteria_states)
    @test at_iteration == 2

    state.iteration = 0
    is_finished(problem, algorithm, state)
    @test scs.at_iteration == at_iteration
    @test map(cs -> cs.at_iteration, scs.criteria_states) == child_at_iterations
    @test indicates_convergence(stop_when, scs)
end

@testset "get_active_stopping_criteria" begin
    converging = StopWhenConverged(2)
    budget = StopAfterIteration(2)
    # a threshold this small is exceeded by any real elapsed time, so the timer triggers on the
    # first iteration after it was started
    timer = StopAfter(Nanosecond(1))

    # `&` and `|` flatten, but a mixed combination genuinely nests, and the recursion has to
    # report the active leaves rather than the groups
    stop_when = (converging | budget) & timer
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 0)

    @test isempty(get_active_stopping_criteria(algorithm, state))
    # iteration 0 starts the timer
    @test !is_finished!(problem, algorithm, state)
    state.iteration = 2
    @test is_finished!(problem, algorithm, state)

    active = get_active_stopping_criteria(algorithm, state)
    @test map(first, active) == [converging, budget, timer]
    @test all(((c, cs),) -> is_active(c, cs), active)
    # the groups themselves are recursed into, not reported
    @test !any(c -> c isa Union{StopWhenAll, StopWhenAny}, map(first, active))

    # only the criteria that did indicate to stop are listed
    stop_when = StopWhenConverged(100) | budget
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 2)
    @test is_finished!(problem, algorithm, state)
    @test map(first, get_active_stopping_criteria(algorithm, state)) == [budget]
end

@testset "convenience accessors" begin
    stop_when = StopWhenConverged(2) | StopAfterIteration(5)
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(nothing, scs, 2)
    @test is_finished!(problem, algorithm, state)

    @test get_reason(algorithm, state) == get_reason(stop_when, scs)
    @test is_active(algorithm, state) == is_active(stop_when, scs)
    @test indicates_convergence(algorithm, state) == indicates_convergence(stop_when, scs)
    @test get_active_stopping_criteria(algorithm, state) ==
        get_active_stopping_criteria(stop_when, scs)
end

@testset "StopWhenBelow" begin
    residual(problem, algorithm, state) = state.iterate
    stop_when = StopWhenBelow(residual, 0.1)
    @test indicates_convergence(stop_when)
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    @test scs isa StopWhenBelowState{Float64}
    state = AIT.DummyState(1.0, scs, 0)
    @test !is_finished!(problem, algorithm, state)
    @test scs.value == 1.0
    @test isnothing(get_reason(algorithm, state))
    @test summary(stop_when, scs) == "residual ≤ 0.1: not reached"

    state.iterate = 0.0625
    state.iteration = 4
    @test is_finished(problem, algorithm, state)
    @test is_finished!(problem, algorithm, state)
    @test indicates_convergence(algorithm, state)
    @test get_reason(algorithm, state) ==
        "At iteration 4 the residual (0.0625) reached the threshold (0.1).\n"
    @test summary(stop_when, scs) == "residual ≤ 0.1: reached"

    initialize_state!(problem, algorithm, stop_when, scs)
    @test !is_active(stop_when, scs)
    @test isnan(scs.value)

    stop_when = StopWhenBelow((problem, algorithm, state) -> state.iterate, 0.0f0)
    @test initialize_state(problem, algorithm, stop_when) isa StopWhenBelowState{Float32}
    @test AlgorithmsInterface._quantity_name(stop_when) == "value"
    @test AlgorithmsInterface._quantity_name(StopWhenBelow(StopAfterIteration(1), 0.0)) == "value"
    stop_when = stop_when | StopAfterIteration(3)
    algorithm = AIT.DummyAlgorithm(stop_when)
    scs = initialize_state(problem, algorithm, stop_when)
    state = AIT.DummyState(1.0f0, scs, 3)
    @test is_finished!(problem, algorithm, state)
    @test !indicates_convergence(algorithm, state)
    @test isnothing(get_reason(stop_when.criteria[1], scs.criteria_states[1]))
end
