using Documenter, PhyloNetworks

# Weave the .jmd
include(Pkg.dir("PhyloNetworks","docs","src", "man", "src", "make_weave.jl"))

makedocs()

deploydocs(
    deps   = Deps.pip("pygments", "mkdocs", "mkdocs-material", "python-markdown-math"),
    repo = "github.com/crsl4/PhyloNetworks.jl.git",
    julia  = "0.6",
    osname = "linux"
)
