using Documenter: Documenter
using MOSAiCAYiL: MOSAiCAYiL

Documenter.makedocs(;
    sitename = "MOSAiCAYiL.jl",
    modules = [MOSAiCAYiL],
    authors = "Jordan Benjamin",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        size_threshold = 500_000,
    ),
    pages = [
        "Home" => "index.md",
        "Guide" => [
            "The days and their files" => "data.md",
            "Reading a variable" => "reading.md",
            "The forcing of a day" => "forcing.md",
            "The 3D fields" => "fields3d.md",
            "Facts with no I/O" => "facts.md",
        ],
        "Physics" => [
            "Thermodynamics" => "thermodynamics.md",
            "The vertical grid" => "grid.md",
        ],
        "Extensions" => [
            "Zarr" => "zarr.md",
            "Parallel sweeps" => "parallel.md",
            "ClimaAtmos" => "climaatmos.md",
        ],
        "What the reference runs did" => "archive.md",
        "API" => "api.md",
    ],
    checkdocs = :exports,
    warnonly = [:missing_docs],
)