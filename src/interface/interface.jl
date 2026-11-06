_doc_init_state = """
    state = initialize_state(problem::Problem, algorithm::Algorithm; kwargs...)
    state = initialize_state!(problem::Problem, algorithm::Algorithm, state::State; kwargs...)

Initialize a [`State`](@ref) based on a [`Problem`](@ref) and an [`Algorithm`](@ref).
The `kwargs...` should allow to initialize for example the initial point.
This can be done in-place for `state`, then only values that did change have to be provided.

By default, both work with a [`DefaultState`](@ref), and also accept positional arguments:

    state = initialize_state(problem, algorithm, iterate, state_data; kwargs...)
    state = initialize_state!(problem, algorithm, state, iterate, state_data; kwargs...)

Here `state_data` is stored in the `data` field, and defaults to `nothing` when allocating and to `state.data` when resetting.
The remaining `kwargs...` are passed on to the initialization of the [`StoppingCriterion`](@ref).

Custom states should implement the keyword form, to avoid ambiguities with
`initialize_state(problem, algorithm, stopping_criterion)`.
"""

function initialize_state end

@doc "$(_doc_init_state)"
initialize_state(::Problem, ::Algorithm; kwargs...)

function initialize_state! end

@doc "$(_doc_init_state)"
initialize_state!(::Problem, ::Algorithm, ::State; kwargs...)

"""
    output = finalize_state!(problem::Problem, algorithm::Algorithm, state::State)

Finalize the solver and decide what values get returned from the [`solve!`](@ref) call.
By default, this is a no-op and returns the `state.iterate`, but this allows for further
customization in other cases, for example to clean up used resources or output other data.
"""
finalize_state!(problem::Problem, algorithm::Algorithm, state::State) = state.iterate

# has to be defined before used in solve but is documented alphabetically after

@doc """
    solve(problem::Problem, algorithm::Algorithm; kwargs...)

Solve the [`Problem`](@ref) using an [`Algorithm`](@ref).
The keyword arguments `kwargs...` have to provide enough details such that
the corresponding state initialisation [`initialize_state`](@ref)`(problem, algorithm)`
returns a state.

This runs [`eachstep`](@ref) to completion and returns [`finalize_state!`](@ref).
"""
function solve(problem::Problem, algorithm::Algorithm; kwargs...)
    iterator = eachstep(problem, algorithm; kwargs...)
    for _ in iterator end
    return finalize_state!(iterator)
end

@doc """
    solve!(problem::Problem, algorithm::Algorithm, state::State; kwargs...)

Solve the [`Problem`](@ref) using an [`Algorithm`](@ref), starting from a given [`State`](@ref).
The state is modified in-place.

All keyword arguments are passed to the [`initialize_state!`](@ref)`(problem, algorithm, state)` function.
This runs the iterator of [`eachstep`](@ref) to completion and returns [`finalize_state!`](@ref).
"""
function solve!(problem::Problem, algorithm::Algorithm, state::State; kwargs...)
    initialize_state!(problem, algorithm, state; kwargs...)
    iterator = SolverIterator(problem, algorithm, state)
    for _ in iterator end
    return finalize_state!(iterator)
end

function step! end
@doc """
    step!(problem::Problem, algorithm::Algorithm, state::State)

Perform the current step of an [`Algorithm`](@ref) solving a [`Problem`](@ref)
modifying the algorithm's [`State`](@ref).
"""
step!(problem::Problem, algorithm::Algorithm, state::State)
