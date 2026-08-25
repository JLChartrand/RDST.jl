using RDST
using Documenter

DocMeta.setdocmeta!(RDST, :DocTestSetup, :(using RDST); recursive = true)

makedocs(;
    sitename = "RDST.jl",
    modules = [RDST],
    checkdocs = :exports,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://jlchartrand.github.io/RDST.jl",
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
        repo = "github.com/JLChartrand/RDST.jl.git",
        devbranch = "master",
    )
end
