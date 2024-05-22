using DuckDispatch
using Documenter

DocMeta.setdocmeta!(DuckDispatch, :DocTestSetup, :(using DuckDispatch); recursive=true)

makedocs(;
    modules=[DuckDispatch],
    authors="Micah Rufsvold",
    sitename="DuckDispatch.jl",
    format=Documenter.HTML(;
        canonical="https://mrufsvold.github.io/DuckDispatch.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mrufsvold/DuckDispatch.jl",
    devbranch="master",
)
