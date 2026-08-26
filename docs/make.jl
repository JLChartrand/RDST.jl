using RandomDataStreams
using Documenter

DocMeta.setdocmeta!(RandomDataStreams, :DocTestSetup, :(using RandomDataStreams); recursive = true)

makedocs(;
    sitename = "RandomDataStreams.jl",
    modules = [RandomDataStreams],
    checkdocs = :exports,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://jlchartrand.github.io/RandomDataStreams.jl",
        edit_link = "master",
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Streams & Substreams" => "streams.md",
        "API Reference" => "api.md",
        "Docstrings" => "docstrings.md",
        "Implementation Notes" => "implementation.md",
        "Generator Comparison" => "comparison.md",
        "FAQ" => "faq.md",
    ],
)

if get(ENV, "CI", nothing) == "true"
    deploydocs(;
        repo = "github.com/JLChartrand/RandomDataStreams.jl.git",
        devbranch = "master",
    )
end
