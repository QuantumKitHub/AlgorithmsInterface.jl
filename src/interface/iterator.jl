@enum IteratorStatus Created Running Stopped

"""
    SolverIterator

Iterator over the steps of an [`Algorithm`](@ref) solving a [`Problem`](@ref), created by
[`eachstep`](@ref).

Every iteration checks [`is_finished!`](@ref), then emits `:PreStep`, calls [`increment!`](@ref)
and [`step!`](@ref), emits `:PostStep` and yields the (mutated, always the same) state.
`:Start` is emitted on the first iteration and `:Stop` once the stopping criterion is met.
Code in the loop body runs after `:PostStep` and before the next stopping check, so it may
modify the state.

Leaving the loop early with `break` keeps the iterator resumable: iterating again continues
from the current state. [`finalize_state!`](@ref)`(iterator)` emits `:Stop` if needed and
returns the result of the solve, and [`initialize_state!`](@ref)`(iterator; kwargs...)` prepares
it for another run.

The `status` field ensures `:Start` and `:Stop` are emitted once, and that the stopping
criterion is not checked again after it was met.
"""
mutable struct SolverIterator{P <: Problem, A <: Algorithm, S <: State}
    const problem::P
    const algorithm::A
    const state::S
    logger::Union{Nothing, AlgorithmLogger}
    status::IteratorStatus
end

SolverIterator(problem::Problem, algorithm::Algorithm, state::State) =
    SolverIterator(problem, algorithm, state, algorithm_logger(), Created)

"""
    eachstep(problem::Problem, algorithm::Algorithm; kwargs...) -> SolverIterator

Lazy counterpart of [`solve`](@ref): initialize the state, and return an iterator that performs
one step per iteration and yields the state.

```julia
iterator = eachstep(problem, algorithm; iterate = x0)
for state in iterator
    state.iteration % 10 == 0 && @info "checkpoint" state.iterate
end
result = finalize_state!(iterator)
```

The logger is retrieved when the iterator is created or reinitialized.
"""
eachstep(problem::Problem, algorithm::Algorithm; kwargs...) =
    SolverIterator(problem, algorithm, initialize_state(problem, algorithm; kwargs...))

"""
    initialize_state!(iterator::SolverIterator; kwargs...) -> SolverIterator

Prepare `iterator` for another run: reinitialize its state through
[`initialize_state!`](@ref)`(problem, algorithm, state; kwargs...)`, and retrieve the current
logger.
"""
function initialize_state!(iterator::SolverIterator; kwargs...)
    (; problem, algorithm, state) = iterator
    initialize_state!(problem, algorithm, state; kwargs...)
    iterator.logger = algorithm_logger()
    iterator.status = Created
    return iterator
end

Base.IteratorSize(::Type{<:SolverIterator}) = Base.SizeUnknown()
Base.eltype(::Type{<:SolverIterator{P, A, S}}) where {P, A, S} = S

function Base.iterate(iterator::SolverIterator, _ = nothing)
    (; problem, algorithm, state, logger) = iterator
    iterator.status == Stopped && return nothing
    if iterator.status == Created
        iterator.status = Running
        emit_message(logger, problem, algorithm, state, :Start)
    end
    if is_finished!(problem, algorithm, state)
        iterator.status = Stopped
        emit_message(logger, problem, algorithm, state, :Stop)
        return nothing
    end
    emit_message(logger, problem, algorithm, state, :PreStep)
    increment!(state)
    step!(problem, algorithm, state)
    emit_message(logger, problem, algorithm, state, :PostStep)
    return state, nothing
end

"""
    finalize_state!(iterator::SolverIterator)

Finish a run driven through [`eachstep`](@ref): emit `:Stop` if it was not emitted yet, and
return [`finalize_state!`](@ref)`(problem, algorithm, state)`.

To customize the result of an algorithm, specialize
[`finalize_state!`](@ref)`(problem, algorithm, state)` instead of this method.
"""
function finalize_state!(iterator::SolverIterator)
    (; problem, algorithm, state, logger) = iterator
    if iterator.status != Stopped
        iterator.status = Stopped
        emit_message(logger, problem, algorithm, state, :Stop)
    end
    return finalize_state!(problem, algorithm, state)
end
