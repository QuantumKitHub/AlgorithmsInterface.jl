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
        with_algorithmlogger(:PostStep => iter_logger) do
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
        with_algorithmlogger(:PostStep => flaky_logger) do
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
        with_algorithmlogger(:PostStep => if_logger) do
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
        with_algorithmlogger(:PostStep => group_logger) do
            solve(problem, algorithm)
        end
    end
end

@testset "StopReasonAction reports why the algorithm stopped" begin
    problem = LogDummyProblem()
    algorithm = LogDummyAlgorithm(StopAfterIteration(3))

    io = IOBuffer()
    with_algorithmlogger(:Stop => StopReasonAction(io; prefix = "Stopped: ")) do
        solve(problem, algorithm)
    end
    reason = String(take!(io))
    @test startswith(reason, "Stopped: At iteration 3")

    # nothing is reported while no criterion has indicated to stop, so registering the action on
    # another context is harmless
    io = IOBuffer()
    with_algorithmlogger(:Start => StopReasonAction(io)) do
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
        with_algorithmlogger(:PostStep => iter_logger) do
            solve(problem, algorithm)
        end
    end

    # Re-enable logging
    AlgorithmsInterface.set_global_logging_state!(true)
    @test AlgorithmsInterface.get_global_logging_state() == true

    # Now logging should work again
    @test_logs (:info, "Iter 1") (:info, "Iter 2") (:info, "Iter 3") begin
        with_algorithmlogger(:PostStep => iter_logger) do
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

const LOG = String[]
record(tag) = CallbackAction((p, a, s; kw...) -> push!(LOG, "$tag $(s.iteration)"))

@testset "nested scopes merge, outer action first" begin
    empty!(LOG)
    with_algorithmlogger(:PostStep => record("outer")) do
        with_algorithmlogger(:PostStep => record("inner")) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        end
    end
    @test LOG == ["outer 1", "inner 1"]
end

@testset "NoLogging silences one context" begin
    empty!(LOG)
    with_algorithmlogger(:PostStep => record("post"), :Stop => record("stop")) do
        with_algorithmlogger(:PostStep => NoLogging()) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(2)); iterate = 0)
        end
    end
    @test LOG == ["stop 2"]
end

@testset "inherit = false discards outer scopes" begin
    empty!(LOG)
    with_algorithmlogger(:PostStep => record("outer")) do
        with_algorithmlogger(:Stop => record("inner"); inherit = false) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(2)); iterate = 0)
        end
    end
    @test LOG == ["inner 2"]
end

@testset "with_algorithmlogger accepts an AlgorithmLogger" begin
    logger = AlgorithmLogger(:PostStep => record("logger"))

    empty!(LOG)
    with_algorithmlogger(logger) do
        with_algorithmlogger(:PostStep => record("user")) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        end
    end
    @test LOG == ["logger 1", "user 1"]

    empty!(LOG)
    with_algorithmlogger(:PostStep => record("outer")) do
        with_algorithmlogger(logger; inherit = false) do
            solve(CountProblem(), CountAlgorithm(StopAfterIteration(1)); iterate = 0)
        end
    end
    @test LOG == ["logger 1"]
end
