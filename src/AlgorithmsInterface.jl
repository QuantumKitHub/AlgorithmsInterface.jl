@doc raw"""
🧮 AlgorithmsInterface.jl: an interface for iterative algorithms in Julia

* 📚 Documentation: [juliamanifolds.github.io/AlgorithmsInterface.jl/](https://juliamanifolds.github.io/AlgorithmsInterface.jl/)
* 📦 Repository: [github.com/JuliaManifolds/AlgorithmsInterface.jl](https://github.com/JuliaManifolds/AlgorithmsInterface.jl)
* 💬 Discussions: [github.com/JuliaManifolds/AlgorithmsInterface.jl/discussions](https://github.com/JuliaManifolds/AlgorithmsInterface.jl/discussions)
* 🎯 Issues: [github.com/JuliaManifolds/AlgorithmsInterface.jl/issues](https://github.com/JuliaManifolds/AlgorithmsInterface.jl/issues)
"""
module AlgorithmsInterface

using Dates: Millisecond, Nanosecond, Period, canonicalize, value
using Printf
using ScopedValues

include("interface/algorithm.jl")
include("interface/problem.jl")
include("interface/state.jl")
include("interface/interface.jl")

include("stopping_criterion.jl")
include("default_state.jl")
include("logging.jl")

include("test_suite.jl")

# general interface
export Algorithm, Problem, State
export DefaultState
export initialize_state, initialize_state!
export finalize_state!

export step!, solve, solve!, solve_loop!

# stopping criteria
export StoppingCriterion, StoppingCriterionState
export StopAfter, StopAfterIteration, StopWhenAll, StopWhenAny, StopWhenBelow
export DefaultStoppingCriterionState, StopAfterTimePeriodState, GroupStoppingCriterionState
export StopWhenBelowState

export is_finished, is_finished!, get_reason, is_active, indicates_convergence
export get_active_stopping_criteria

# Logging interface
export LoggingAction, CallbackAction, IfAction, ActionGroup, StopReasonAction, NoLogging
export AlgorithmLogger, with_algorithmlogger, emit_message

end # module AlgorithmsInterface
