# 🧮 AlgorithmsInterface.jl

A small, composable interface for iterative algorithms in Julia.

[![docs][docs-dev-img]][docs-dev-url] [![CI][ci-img]][ci-url] [![runic][runic-img]][runic-url] [![codecov][codecov-img]][codecov-url] [![aqua][aqua-img]][aqua-url]


## Design

Iterative methods tend to share the same moving parts, which can lead to quite a bit of boilerplate and friction when trying to compose them.
This package aims to provide abstractions such as the main loop, stopping criteria, and a logging system shared by these methods.
It does not ship any concrete algorithms; the goal is to provide the tools to build on.
It does however ship with a useful set of stopping-criterion and logging primitives out of the box.

The surface is intentionally small.
The main design goal of the interface is to cleanly separate the implementation of the algorithm itself from the generic tools that surround it.
Those generic tools, such as stopping, logging and debugging, are written once and then work across every algorithm that adopts the interface.

See the [documentation][docs-dev-url] for the design walk-through, the API reference, and a worked example.
For background and discussion, see the [initial discussion](https://github.com/QuantumKitHub/AlgorithmsInterface.jl/discussions/1).

Note that this package is still in its design phase, and while SemVer is respected, (breaking) changes might still occur as the design takes shape.

[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://QuantumKitHub.github.io/AlgorithmsInterface.jl/dev/

[codecov-img]: https://codecov.io/gh/QuantumKitHub/AlgorithmsInterface.jl/graph/badge.svg?token=1OBDY03SUP
[codecov-url]: https://codecov.io/gh/QuantumKitHub/AlgorithmsInterface.jl

[ci-img]: https://github.com/QuantumKitHub/AlgorithmsInterface.jl/actions/workflows/ci.yml/badge.svg
[ci-url]: https://github.com/QuantumKitHub/AlgorithmsInterface.jl/actions/workflows/ci.yml

[runic-img]: https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black
[runic-url]: https://github.com/fredrikekre/Runic.jl

[aqua-img]: https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg
[aqua-url]: https://github.com/JuliaTesting/Aqua.jl
