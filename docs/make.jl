using RandomDataStream
using Documenter

DocMeta.setdocmeta!(RandomDataStream, :DocTestSetup, :(using RandomDataStream); recursive = true)

makedocs(;
    sitename = "RandomDataStream.jl",
    modules = [RandomDataStream],
    checkdocs = :exports,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://jlchartrand.github.io/RandomDataStream.jl",
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
        repo = "github.com/JLChartrand/RandomDataStream.jl.git",
        devbranch = "master",
    )
end
