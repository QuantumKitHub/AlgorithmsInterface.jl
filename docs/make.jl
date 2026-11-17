#!/usr/bin/env julia
#
#

if "--help" ∈ ARGS
    println(
        """
        docs/make.jl

        Render the `AlgorithmsInterface.jl` documentation with optional arguments

        Arguments
        * `--help`              print this help and exit without rendering the documentation
        * `--prettyurls`        toggle the pretty urls part to true, which is always set on CI
        """
    )
    exit(0)
end

# if docs is not the current active environment, switch to it
# (from https://github.com/JuliaIO/HDF5.jl/pull/1020/) 
if Base.active_project() != joinpath(@__DIR__, "Project.toml")
    using Pkg
    Pkg.activate(@__DIR__)
    Pkg.instantiate()
end

#
# Load packages
using Documenter, DocumenterCitations, DocumenterInterLinks
using AlgorithmsInterface

run_on_CI = (get(ENV, "CI", nothing) == "true")

#
# Copy and reformat changelog

# (d) add contributing.md and changelog.md to the docs – and link to releases and issues
const base_repository = "github.com/QuantumKitHub/AlgorithmsInterface.jl"

function add_links(line::String, url::String = "https://$base_repository")
    # replace issues (#XXXX) -> ([#XXXX](url/issue/XXXX))
    while (m = match(r"\(\#([0-9]+)\)", line)) !== nothing
        id = m.captures[1]
        line = replace(line, m.match => "([#$id]($url/issues/$id))")
    end
    # replace ## [X.Y.Z] -> with a link to the release [X.Y.Z](url/releases/tag/vX.Y.Z)
    while (m = match(r"\#\# \[([0-9]+.[0-9]+.[0-9]+)\] (.*)", line)) !== nothing
        tag = m.captures[1]
        date = m.captures[2]
        line = replace(line, m.match => "## [$tag]($url/releases/tag/v$tag) ($date)")
    end
    return line
end

generated_path = joinpath(@__DIR__, "src")
base_url = "https://$base_repository/blob/main/"
isdir(generated_path) || mkdir(generated_path)
for (md_file, doc_file) in [("Changelog.md", "changelog.md")]
    open(joinpath(generated_path, doc_file), "w") do io
        # Point to source license file
        println(
            io,
            """
            ```@meta
            EditURL = "$(base_url)$(md_file)"
            ```
            """,
        )
        # Write the contents out below the meta block
        for line in eachline(joinpath(dirname(@__DIR__), md_file))
            println(io, add_links(line))
        end
    end
end

bib = CitationBibliography(joinpath(@__DIR__, "src", "references.bib"); style = :alpha)
links = InterLinks()
makedocs(;
    format = Documenter.HTML(;
        prettyurls = run_on_CI || ("--prettyurls" ∈ ARGS),
        assets = [
            #    "assets/favicon.ico",
            "assets/citations.css",
            "assets/link-icons.css",
        ],
    ),
    modules = [AlgorithmsInterface],
    authors = "Ronny Bergmann, Lukas Devos, and contributors.",
    sitename = "AlgorithmsInterface.jl",
    pages = [
        "Home" => "index.md",
        "Interface" => "interface.md",
        "Stopping criteria" => "stopping_criterion.md",
        "Logging" => "logging.md",
        "Miscellanea" => [
            "Internals" => "internals.md",
            "Notation" => "notation.md",
            "Changelog" => "changelog.md",
            "References" => "references.md",
        ],
    ],
    expandfirst = ["interface.md", "stopping_criterion.md"],
    plugins = [bib, links],
)
deploydocs(; repo = base_repository, push_preview = true)
#back to main env
Pkg.activate()
