"""
    solve_loop!(problem::Problem, algorithm::Algorithm, state::State)

Run the main loop of the iterative `algorithm` from the given `state`, without emitting
`:Start` and `:Stop`.

!!! warning
    `solve_loop!` is deprecated, iterate over [`eachstep`](@ref) instead.
    [`solve`](@ref) no longer calls it, so methods added to it have no effect; specialize
    `Base.iterate` on [`SolverIterator`](@ref AlgorithmsInterface.SolverIterator) to change the main loop.
"""
function solve_loop!(problem::Problem, algorithm::Algorithm, state::State)
    Base.depwarn("`solve_loop!` is deprecated, iterate over `eachstep` instead.", :solve_loop!)
    logger = algorithm_logger()
    while !is_finished!(problem, algorithm, state)
        emit_message(logger, problem, algorithm, state, :PreStep)
        increment!(state)
        step!(problem, algorithm, state)
        emit_message(logger, problem, algorithm, state, :PostStep)
    end
    return state
end
