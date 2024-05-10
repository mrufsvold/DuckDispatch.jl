using InterfaceDispatch
using Documenter

DocMeta.setdocmeta!(InterfaceDispatch, :DocTestSetup, :(using InterfaceDispatch); recursive=true)

makedocs(;
    modules=[InterfaceDispatch],
    authors="Micah Rufsvold",
    sitename="InterfaceDispatch.jl",
    format=Documenter.HTML(;
        canonical="https://mrufsvold.github.io/InterfaceDispatch.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mrufsvold/InterfaceDispatch.jl",
    devbranch="master",
)
