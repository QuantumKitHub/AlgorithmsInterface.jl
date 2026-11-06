# Changelog

All notable Changes to the Julia package `AlgorithmsInterface.jl` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] unreleased

### Added

- `is_active(stopping_criterion, stopping_criterion_state)`, the machine-readable counterpart of `get_reason`, reporting whether a criterion became active during the current run.
  It defaults to reading the state's `at_iteration` and is what the generic convergence reporting is now built on, rather than `!isnothing(get_reason(...))`.
- `get_active_stopping_criteria`, reporting which criteria became active.
  It recurses through nested combinations, so it separates stopping on a collapsed step size from stopping on an exhausted iteration budget — a distinction `indicates_convergence` is too coarse for.
- Convenience two-argument `get_reason(algorithm, state)`, and likewise for `is_active`, `indicates_convergence` and `get_active_stopping_criteria`, extracting the criterion and its state the way `is_finished` already did.
- `StopReasonAction`, a `LoggingAction` that reports `get_reason` at the `:Stop` context.
- Defaults for `get_reason` (`nothing`) and for the type-domain `indicates_convergence` (`false`), so a criterion that implements neither no longer hits a `MethodError` from the derived convergence reporting.
- Exports for `DefaultStoppingCriterionState`, `StopAfterTimePeriodState` and `GroupStoppingCriterionState`, which a downstream criterion is expected to reuse.
- `DefaultState`, a `State` with the `iterate`, `iteration` and `stopping_criterion_state` fields, and a `data` field for any additional data.
- Default `initialize_state` and `initialize_state!` methods using a `DefaultState`, so an algorithm only has to provide a `Problem`, an `Algorithm` and a `step!`.
- Default `initialize_state` and `initialize_state!` methods for any `StoppingCriterion`, using a `DefaultStoppingCriterionState`.
- `StopWhenBelow` and `StopWhenBelowState`, stopping once a quantity computed from the state is at most a threshold.

### Changed

- `indicates_convergence` without a state moved to the type domain: a new criterion implements `indicates_convergence(::Type{YourCriterion})`, and `indicates_convergence(criterion)` forwards to it.
  `StopWhenAll` and `StopWhenAny` combine their children in the type domain as well, so a criterion that only implements the variant taking an instance is no longer accounted for in a group.
- `StopAfterIteration` now uses the default `initialize_state` and `initialize_state!`.

### Fixed

- `indicates_convergence(::StoppingCriterion, ::StoppingCriterionState)` had its condition inverted, claiming convergence exactly when the criterion had *not* indicated to stop.
- `indicates_convergence` for `StopWhenAll` and `StopWhenAny` now consults the children that actually indicated to stop.
  Previously a `StopWhenAny` pairing a convergence criterion with a fallback such as `StopAfterIteration` could never report convergence, since the criteria-only variant is `all(indicates_convergence, criteria)`.
- `is_finished!` for `StopWhenAll` and `StopWhenAny` short-circuited, skipping the children after the deciding one.
  Stateful criteria were starved of the current iterate and their `at_iteration` left unset even when they did indicate to stop; every child is now updated once per iteration.
- `get_reason` for `StopWhenAll` and `StopWhenAny` rendered children that had not indicated to stop as the literal text `"nothing"`, and returned `""` when no child had a message at all.
  It now reports only the children that triggered, and `nothing` when there is nothing to report.
- The non-mutating `is_finished` for `StopWhenAll` and `StopWhenAny` reset `at_iteration` at iteration `0`, contradicting its contract and silently clearing a group's recorded stop.
- The non-mutating `is_finished` for `StopAfter` reported the elapsed time recorded by the last `is_finished!` rather than reading the clock, so it could answer "not finished" for a run long past its threshold.
- `get_reason` for `StopAfterIteration` was gated on `at_iteration >= max_iterations` while its `Base.summary` was gated on `at_iteration >= 0`, so the two could disagree.

## [0.1.0] 2026-05-01

Initial release.
