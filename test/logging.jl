using Test
using AlgorithmsInterface

# Dummy types for a minimal iterative algorithm
struct LogDummyProblem <: Problem end
struct LogDummyAlgorithm <: Algorithm
    stopping_criterion
end
mutable struct LogDummyState{S <: StoppingCriterionState} <: State
    iterate::Float64
    iteration::Int
    stopping_criterion_state::S
end

# State initialization for the dummy algorithm
function AlgorithmsInterface.initialize_state(problem::LogDummyProblem, algorithm::LogDummyAlgorithm; kwargs...)
    sc_state = initialize_state(problem, algorithm, algorithm.stopping_criterion; kwargs...)
    return LogDummyState(0.0, 0, sc_state)
end
function AlgorithmsInterface.initialize_state!(
        problem::LogDummyProblem,
        algorithm::LogDummyAlgorithm,
        state::LogDummyState;
        kwargs...
    )
    initialize_state!(problem, algorithm, algorithm.stopping_criterion, state.stopping_criterion_state; kwargs...)
    state.iterate = 0.0
    state.iteration = 0
    return state
end

# One trivial step per iteration (not relevant for the logging test)
function AlgorithmsInterface.step!(
        ::LogDummyProblem,
        ::LogDummyAlgorithm,
        state::LogDummyState,
    )
    state.iterate += 1.0
    return state
end

@testset "CallbackAction logs iteration on each step" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(3))

    # Action that logs the current iteration number at :PostStep
    iter_logger = CallbackAction() do problem, algorithm, state
        @info "Iter $(state.iteration)"
    end

    # Expect exactly three info logs for iterations 1, 2, 3
    @test_logs (:info, "Iter 1") (:info, "Iter 2") (:info, "Iter 3") begin
        with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:PostStep => iter_logger)) do
            solve(problem, algorithm)
        end
    end
end

@testset "Logging errors are caught and don't crash" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(3))

    # Action that throws on the second iteration
    flaky_logger = CallbackAction() do problem, algorithm, state
        if state.iteration == 2
            error("Boom")
        else
            @info "Iter $(state.iteration)"
        end
    end

    # We expect:
    #  - an error log emitted by the logging infrastructure on iter 2
    #  - info logs for iterations 1 and 3
    @test_logs (:info, "Iter 1") (:error, "Error during the handling of a logging action") (:info, "Iter 3") begin
        with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:PostStep => flaky_logger)) do
            solve(problem, algorithm)
        end
    end
end

@testset "IfAction only logs on even iterations" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(4))

    # Callback that logs the iteration
    iter_logger = CallbackAction() do problem, algorithm, state
        @info "Even Iter $(state.iteration)"
    end

    # Predicate: only log on even iterations
    even_predicate = (problem, algorithm, state; kwargs...) -> state.iteration % 2 == 0
    if_logger = IfAction(even_predicate, iter_logger)

    # Expect logs only for iterations 2 and 4
    @test_logs (:info, "Even Iter 2") (:info, "Even Iter 4") begin
        with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:PostStep => if_logger)) do
            solve(problem, algorithm)
        end
    end
end

@testset "ActionGroup logs multiple actions" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(2))

    # First logger
    logger1 = CallbackAction() do problem, algorithm, state
        @info "Logger1 Iter $(state.iteration)"
    end

    # Second logger
    logger2 = CallbackAction() do problem, algorithm, state
        @info "Logger2 Iter $(state.iteration)"
    end

    group_logger = ActionGroup(logger1, logger2)

    # Expect both loggers to log for each iteration
    @test_logs (:info, "Logger1 Iter 1") (:info, "Logger2 Iter 1") (:info, "Logger1 Iter 2") (:info, "Logger2 Iter 2") begin
        with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:PostStep => group_logger)) do
            solve(problem, algorithm)
        end
    end
end

@testset "StopReasonAction reports why the algorithm stopped" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(3))

    io = IOBuffer()
    with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:Stop => StopReasonAction(io; prefix = "Stopped: "))) do
        solve(problem, algorithm)
    end
    reason = String(take!(io))
    @test startswith(reason, "Stopped: At iteration 3")

    # nothing is reported while no criterion has indicated to stop, so registering the action on
    # another context is harmless
    io = IOBuffer()
    with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:Start => StopReasonAction(io))) do
        solve(problem, algorithm)
    end
    @test isempty(String(take!(io)))
end

@testset "Global logging toggle disables all logging" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(3))

    # Action that logs the current iteration number
    iter_logger = CallbackAction() do problem, algorithm, state
        @info "Iter $(state.iteration)"
    end

    # Save the current global logging state
    previous_state = AlgorithmsInterface.get_global_logging_state()
    @test previous_state == true  # logging should be enabled by default

    # Disable logging globally
    AlgorithmsInterface.set_global_logging_state!(false)
    @test AlgorithmsInterface.get_global_logging_state() == false

    # Even with a logger configured, no logs should be emitted
    @test_logs begin
        with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:PostStep => iter_logger)) do
            solve(problem, algorithm)
        end
    end

    # Re-enable logging
    AlgorithmsInterface.set_global_logging_state!(true)
    @test AlgorithmsInterface.get_global_logging_state() == true

    # Now logging should work again
    @test_logs (:info, "Iter 1") (:info, "Iter 2") (:info, "Iter 3") begin
        with_algorithmlogger(:LogDummyAlgorithm => AlgorithmLogger(:PostStep => iter_logger)) do
            solve(problem, algorithm)
        end
    end

    # Restore the original state (in case it was different)
    AlgorithmsInterface.set_global_logging_state!(previous_state)
end

struct CountProblem <: Problem end
struct CountAlgorithm <: Algorithm
    stopping_criterion::StoppingCriterion
end

AlgorithmsInterface.step!(::CountProblem, ::CountAlgorithm, state::DefaultState) =
    (state.iterate += 1; state)

record(log, tag) = CallbackAction((p, a, s; kw...) -> push!(log, "$tag $(s.iteration)"))

@testset "nested scopes merge, outer action first" begin
    log = String[]
    with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "outer"))) do
        with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "inner"))) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        end
    end
    @test log == ["outer 1", "inner 1"]
end

@testset "NoLogging silences one context" begin
    log = String[]
    with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "post"), :Stop => record(log, "stop"))) do
        with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => NoLogging())) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(2)); iterate = 0)
        end
    end
    @test log == ["stop 2"]
end

@testset "inherit = false discards outer scopes" begin
    log = String[]
    with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "outer"))) do
        with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:Stop => record(log, "inner")); inherit = false) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(2)); iterate = 0)
        end
    end
    @test log == ["inner 2"]
end

@testset "with_algorithmlogger accepts an AlgorithmLogger" begin
    log = String[]
    logger = AlgorithmLogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "logger")))

    with_algorithmlogger(logger) do
        with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "user"))) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        end
    end
    @test log == ["logger 1", "user 1"]

    empty!(log)
    with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:PostStep => record(log, "outer"))) do
        with_algorithmlogger(logger; inherit = false) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        end
    end
    @test log == ["logger 1"]
end

@testset "a solve uses the entry of its name" begin
    log = String[]
    with_algorithmlogger(:PostStep => record(log, "scope"), :CountAlgorithm => AlgorithmLogger(:Stop => record(log, "count"))) do
        solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); name = :other, iterate = 0)
        state = initialize_state(CountProblem(), CountAlgorithm(StopAfterIteration(2)); iterate = 0)
        solve!(CountProblem(), CountAlgorithm(StopAfterIteration(2)), state; iterate = 0)
    end
    @test log == ["count 1", "count 2"]
end

struct NestProblem <: Problem end
struct NestAlgorithm <: Algorithm
    stopping_criterion::StoppingCriterion
    inner::CountAlgorithm
end

function AlgorithmsInterface.step!(problem::NestProblem, algorithm::NestAlgorithm, state::DefaultState)
    emit_message(problem, algorithm, state, :Custom)
    solve(CountProblem(), algorithm.inner; name = :first, iterate = 0)
    solve(CountProblem(), algorithm.inner; name = :second, iterate = 0)
    state.iterate += 1
    return state
end

@testset "subsolvers descend one level by name" begin
    log = String[]
    nest = NestAlgorithm(StopAfterIteration(2), CountAlgorithm(StopAfterIteration(1)))
    logger = AlgorithmLogger(
        :NestAlgorithm => AlgorithmLogger(
            :PostStep => record(log, "nest"),
            :Custom => record(log, "custom"),
            :first => AlgorithmLogger(:Stop => record(log, "first")),
        ),
    )
    with_algorithmlogger(logger) do
        solve(NestProblem(), nest; iterate = 0)
    end
    @test log == ["custom 1", "first 1", "nest 1", "custom 2", "first 1", "nest 2"]

    empty!(log)
    with_algorithmlogger(:first => AlgorithmLogger(:Stop => record(log, "first"))) do
        solve(NestProblem(), nest; iterate = 0)
    end
    @test isempty(log)
end

struct ScopedNestAlgorithm <: Algorithm
    stopping_criterion::StoppingCriterion
    inner::CountAlgorithm
    inner_stop::LoggingAction
end

function AlgorithmsInterface.step!(::NestProblem, algorithm::ScopedNestAlgorithm, state::DefaultState)
    with_algorithmlogger(:CountAlgorithm => AlgorithmLogger(:Stop => algorithm.inner_stop)) do
        solve(CountProblem(), algorithm.inner; iterate = 0)
    end
    state.iterate += 1
    return state
end

@testset "scopes inside step! apply to subsolvers" begin
    log = String[]
    algorithm = ScopedNestAlgorithm(StopAfterIteration(2), CountAlgorithm(StopAfterIteration(1)), record(log, "author"))
    with_algorithmlogger(:ScopedNestAlgorithm => AlgorithmLogger(:Stop => record(log, "user"))) do
        solve(NestProblem(), algorithm; iterate = 0)
    end
    @test log == ["author 1", "author 1", "user 2"]
end

struct RenamedAlgorithm <: Algorithm
    stopping_criterion::StoppingCriterion
end
AlgorithmsInterface.step!(::CountProblem, ::RenamedAlgorithm, state::DefaultState) = state
AlgorithmsInterface.algorithm_name(::RenamedAlgorithm) = :renamed

@testset "algorithm_name sets the default name" begin
    log = String[]
    with_algorithmlogger(:renamed => AlgorithmLogger(:Stop => record(log, "renamed"))) do
        solve(CountProblem(), RenamedAlgorithm(StopAfterIteration(1)); iterate = 0)
    end
    @test log == ["renamed 1"]
end
