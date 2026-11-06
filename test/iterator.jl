using Test
using AlgorithmsInterface

struct CountProblem <: Problem end
struct CountAlgorithm <: Algorithm
    stopping_criterion::StoppingCriterion
end

AlgorithmsInterface.step!(::CountProblem, ::CountAlgorithm, state::DefaultState) =
    (state.iterate += 1; state)

const LOG = String[]
record(tag) = CallbackAction((p, a, s; kw...) -> push!(LOG, "$tag $(s.iteration)"))

@testset "eachstep yields the state once per step" begin
    iterations = Int[]
    for state in eachstep(CountProblem(), CountAlgorithm(StopAfterIteration(3)); iterate = 0)
        push!(iterations, state.iteration)
    end
    @test iterations == [1, 2, 3]
end

@testset "loop body can modify the state before the stopping check" begin
    iterator = eachstep(CountProblem(), CountAlgorithm(StopAfterIteration(5)); iterate = 0)
    for state in iterator
        state.iterate *= 2
    end
    @test finalize_state!(iterator) == 62
end

@testset "break keeps the iterator resumable; finalize emits :Stop once" begin
    empty!(LOG)
    with_algorithmlogger(:Start => record("start"), :Stop => record("stop")) do
        iterator = eachstep(CountProblem(), CountAlgorithm(StopAfterIteration(4)); iterate = 0)
        for state in iterator
            state.iteration == 2 && break
        end
        @test iterator.state.iteration == 2
        @test collect(s.iteration for s in iterator) == [3, 4]
        @test finalize_state!(iterator) == 4
        @test finalize_state!(iterator) == 4
    end
    @test LOG == ["start 0", "stop 4"]
end

@testset "solve and solve! agree with eachstep" begin
    alg = CountAlgorithm(StopAfterIteration(3))
    @test solve(CountProblem(), alg; iterate = 10) == 13
    state = initialize_state(CountProblem(), alg; iterate = 0)
    @test solve!(CountProblem(), alg, state; iterate = 1) == 4
end

@testset "initialize_state! prepares the iterator for another run" begin
    empty!(LOG)
    iterator = eachstep(CountProblem(), CountAlgorithm(StopAfterIteration(2)); iterate = 0)
    for _ in iterator
    end
    @test finalize_state!(iterator) == 2
    with_algorithmlogger(:Start => record("start"), :Stop => record("stop")) do
        @test initialize_state!(iterator; iterate = 10) === iterator
    end
    @test collect(s.iteration for s in iterator) == [1, 2]
    @test finalize_state!(iterator) == 12
    @test LOG == ["start 0", "stop 2"]
end

@testset "solve_loop! is deprecated" begin
    alg = CountAlgorithm(StopAfterIteration(3))
    state = initialize_state(CountProblem(), alg; iterate = 0)
    @test_deprecated solve_loop!(CountProblem(), alg, state)
    @test state.iterate == 3
end
