"""
    TraitSubstitutionModel

Abstract type for discrete trait substitution models,
using a continous time Markov model on a phylogeny.
Adapted from the substitutionModels module in BioJulia.
The same Q and P function names are used for the transition rates and probabilities.
"""

abstract type TraitSubstitutionModel end
const SM = TraitSubstitutionModel
const Bmatrix = SMatrix{2, 2, Float64}

"""
    Q(model)

Substitution rate matrix for a given substitution model:
Q[i,j] is the rate of transitioning from state i to state j.
"""
Q(mod::TraitSubstitutionModel) = error("rate matrix Q not defined for $(typeof(mod)).")

"""
    showQ(model)

Print the Q matrix to the screen, with trait states as labels on rows and columns.
adapted from prettyprint function by mcreel, found 2017/10 at
https://discourse.julialang.org/t/display-of-arrays-with-row-and-column-names/1961/6
"""
function showQ(object::TraitSubstitutionModel)
    M = Q(object)
    pad = max(8,maximum(length.(object.label))+1)
    for i = 1:size(M,2) # print the header
        print(lpad(object.label[i],(i==1? 2*pad : pad), " "))
    end
    print("\n")
    for i = 1:size(M,1) # print one row per state
        if object.label != ""
            print(lpad(object.label[i],pad," "))
        end
        for j = 1:size(M,2)
            if j == i
                print(lpad("*",pad," "))
            else
                fmt = "%$(pad).4f"
                @eval(@printf($fmt,$(M[i,j])))
            end
        end
        print("\n")
    end
end

"""
    P(mod, t)

Probability transition matrix for a [`TraitSubstitutionModel`](@ref), of the form

    P[1,1] ... P[1,k]
       .          .
       .          .
    P[k,1] ... P[k,k]

where P[i,j] is the probability of ending in state j after time t,
given that the process started in state i.
"""
@inline function P(mod::SM, t::Float64)
    t >= 0.0 || error("t must be positive")
    return expm(Q(mod) * t)
end

"""
    P(mod, t::Array{Float64})

When applied to a general substitution model, matrix exponentiation is used.
The time argument `t` can be an array.
"""
function P(mod::SM, t::Array{Float64})
    all(t .>= 0.0) || error("t's must all be positive")
    try
        eig_vals, eig_vecs = eig(Q(mod)) # Only hermitian matrices are diagonalizable by
        # *StaticArrays*. Non-Hermitian matrices should be converted to `Array`first.
        return [eig_vecs * expm(diagm(eig_vals)*i) * eig_vecs' for i in t]
    catch
        eig_vals, eig_vecs = eig(Array(Q(mod)))
        k = nStates(mod)
        return [SMatrix{k,k}(eig_vecs * expm(diagm(eig_vals)*i) * inv(eig_vecs)) for i in t]
    end
end

"""
    BinaryTraitSubstitutionModel(α, β [, label])

[TraitSubstitutionModel](@ref) for binary traits (with 2 states).
Default labels are "0" and "1".
α is the rate of transition from "0" to "1", and β from "1" to "0".
"""
mutable struct BinaryTraitSubstitutionModel <: TraitSubstitutionModel
    rate::Vector{Float64}
    label::SVector{2, String}
    function BinaryTraitSubstitutionModel(α::Float64, β::Float64, label::SVector{2, String})
	    α >= 0. || error("parameter α must be non-negative")
	    β >= 0. || error("parameter β must be non-negative")
	    ab = α+β
        ab > 0. || error("α+β must be positive")
        new([α,β], label)
    end
end
const BTSM = BinaryTraitSubstitutionModel
BinaryTraitSubstitutionModel(α, β) = BinaryTraitSubstitutionModel(α, β, SVector("0", "1"))

"""
For a BinaryTraitSubstitutionModel, the rate matrix Q is of the form:

    -α  α
     β -β
"""
@inline function Q(mod::BTSM)
    return Bmatrix(-mod.rate[1], mod.rate[2], mod.rate[1], -mod.rate[2])
end

function show(io::IO, object::BinaryTraitSubstitutionModel)
    str = "Binary Trait Substitution Model:\n"
    str *= "rate $(object.label[1])→$(object.label[2]) α=$(object.rate[1])\n"
    str *= "rate $(object.label[2])→$(object.label[1]) β=$(object.rate[2])\n"
    print(io, str)
end

@inline function P(mod::BTSM, t::Float64)
    t >= 0.0 || error("t must be positive")
    ab = mod.rate[1] + mod.rate[2]
    e1 = exp(-ab*t)
    p0 = mod.rate[2]/ab # asymptotic frequency of state "0"
    p1 = mod.rate[1]/ab # asymptotic frequency of state "1"
    a0= p0 *e1
    a1= p1*e1
    return Bmatrix(p0+a1, p0-a0, p1-a1, p1+a0) # by columns
end

"""
    nStates(model)

Number of character states for a given trait evolution model.
"""
nStates(mod::TraitSubstitutionModel) = error("nStates not defined for $(typeof(mod)).")

"""
# Examples

```julia-repl
julia> m1 = BinaryTraitSubstitutionModel(1.0, 2.0)
julia> nStates(m1)
2
```
"""
function nStates(mod::BTSM)
    return 2::Int
end

"""
    TwoBinaryTraitSubstitutionModel(rate [, label])

[TraitSubstitutionModel](@ref) for two binary traits, possibly correlated.
Default labels are "x0", "x1" for trait 1, and "y0", "y1" for trait 2.
If provided, `label` should be a vector of size 4, listing labels for
trait 1 first then labels for trait 2.
`rate` should be a vector of substitution rates of size 8.
rate[1],...,rate[4] describe rates of changes in trait 1.
rate[5],...,rate[8] describe rates of changes in trait 2.

In the transition matrix, trait combinations are listed in the following order:
x0-y0, x0-y1, x1-y0, x1-y1.

try `plot(model)` to visualize states and rates.
"""
mutable struct TwoBinaryTraitSubstitutionModel <: TraitSubstitutionModel
    rate::Vector{Float64}
    label::Vector{String}
    function TwoBinaryTraitSubstitutionModel(α::AbstractVector{Float64}, label::AbstractVector{String})
	    all( x -> x >= 0., α) || error("rates must be non-negative")
        new(α, [string(label[1], "-", label[3]),
                string(label[1], "-", label[4]),
                string(label[2], "-", label[3]),
                string(label[2], "-", label[4])])
    end
end
const TBTSM = TwoBinaryTraitSubstitutionModel
TwoBinaryTraitSubstitutionModel(α) = TwoBinaryTraitSubstitutionModel(α, ["x0", "x1", "y0", "y1"])

function Q(mod::TwoBinaryTraitSubstitutionModel)
    M = fill(0.0,(4,4))
    a = mod.rate
    M[1,3] = a[1]
    M[3,1] = a[2]
    M[2,4] = a[3]
    M[4,2] = a[4]
    M[1,2] = a[5]
    M[2,1] = a[6]
    M[3,4] = a[7]
    M[4,3] = a[8]
    M[1,1] = -M[1,2] - M[1,3]
    M[2,2] = -M[2,1] - M[2,4]
    M[3,3] = -M[3,4] - M[3,1]
    M[4,4] = -M[4,3] - M[4,2]
    return M
end

plot(mod::TraitSubstitutionModel) = error("plot not defined for $(typeof(mod)).")

"""
    plot(mod::TwoBinaryTraitSubstitutionModel)

Output graph using `RCall` of substitution rates for a substitution model for two 
possibly dependent binary traits.
Adapted from fitPagel functions found in the `R` package `phytools`.

# Examples

```jldoctest
julia> m3 = TwoBinaryTraitSubstitutionModel([2.0,1.2,1.1,2.2,1.0,3.1,2.0,1.1],
                ["carnivory", "noncarnivory", "wet", "dry"])
Substitution model for 2 binary traits, with rate matrix:
                     carnivory-wet    carnivory-dry noncarnivory-wet noncarnivory-dry
    carnivory-wet                *           1.0000           2.0000           0.0000
    carnivory-dry           3.1000                *           0.0000           1.1000
 noncarnivory-wet           1.2000           0.0000                *           2.0000
 noncarnivory-dry           0.0000           2.2000           1.1000                *


julia> plot(m3)
```
"""
function plot(object::TwoBinaryTraitSubstitutionModel)
    R"""
    signif<-3
    plot.new()
    par(mar=c(1.1,2.1,3.1,2.1))
    plot.window(xlim=c(0,2),ylim=c(0,1),asp=1)
    """
    R"""
    mtext("Two Binary Trait Substitution Model",side=3,adj=0,line=1.2,cex=1.2)
    arrows(x0=0.15,y0=0.15,y1=0.85,lwd=2,length=0.1)
    arrows(x0=0.2,y0=0.85,y1=0.15,lwd=2,length=0.1)
    arrows(x0=1.6,y0=0.05,x1=0.4,lwd=2,length=0.1)
    arrows(x0=0.4,y0=0.1,x1=1.6,lwd=2,length=0.1)
    arrows(x0=1.8,y0=0.15,y1=0.85,lwd=2,length=0.1)
    arrows(x0=1.85,y0=0.85,y1=0.15,lwd=2,length=0.1)
    arrows(x0=1.6,y0=0.9,x1=0.4,lwd=2,length=0.1)
    arrows(x0=0.4,y0=0.95,x1=1.6,lwd=2,length=0.1)
    text(x=0.175,y=0.95,$(object.label[1]))
    text(x=1.825,y=0.95,$(object.label[2]))
    text(x=1.825,y=0.05,$(object.label[4]))
    text(x=0.175,y=0.05,$(object.label[3]))
    """
    R"""
    text(x=1,y=1,round($(object.rate[5]),signif),cex=0.8)
    """
    R"""
    text(x=1,y=0.85,round($(object.rate[6]),signif),cex=0.8)
    text(x=1.9,y=0.5,round($(object.rate[3]),signif),cex=0.8,srt=90)
    text(x=1.75,y=0.5,round($(object.rate[4]),signif),cex=0.8,srt=90)
    """
    R"""
    text(x=1,y=0,round($(object.rate[8]),signif),cex=0.8)
    text(x=1,y=0.15,round($(object.rate[7]),signif),cex=0.8)
    text(x=0.1,y=0.5,round($(object.rate[2]),signif),cex=0.8,srt=90)
    text(x=0.25,y=0.5,round($(object.rate[1]),signif),cex=0.8,srt=90)
    """
end

function show(io::IO, object::TwoBinaryTraitSubstitutionModel)
    print("Substitution model for 2 binary traits, with rate matrix:\n")
    showQ(object)
end

"""
    EqualRatesSubstitutionModel(numberStates, α, labels)

[TraitSubstitutionModel](@ref) for traits with any number of states
and equal substitution rates α between all states.
Default labels are "1","2",...
"""
mutable struct EqualRatesSubstitutionModel <: TraitSubstitutionModel
    k::Int
    α::Float64
    label::Vector{String}
    function EqualRatesSubstitutionModel(k::Int, α::Float64, label::Vector{String})
        k >= 2 || error("parameter k must be greater than or equal to 2")
        α > 0 || error("parameter α must be positive")
        length(label)==k || error("label vector of incorrect length")
        new(k, α, label)
    end
end
EqualRatesSubstitutionModel(k, α) = EqualRatesSubstitutionModel(k, α, string.(1:k))

function show(io::IO, object::EqualRatesSubstitutionModel)
    str = "Equal Rates Substitution Model with k=$(object.k),\n"
    str *= "all rates equal to α=$(object.α).\n"
    str *= "rate matrix Q:\n"
    print(io, str)
    showQ(object)
end

function nStates(mod::EqualRatesSubstitutionModel)
    return mod.k
end

function Q(mod::EqualRatesSubstitutionModel)
    M = fill(mod.α,(mod.k,mod.k))
    d = -(mod.k-1)*mod.α
    for i in 1:mod.k
        M[i,i] = d
    end
    return M
end

"""
    randomTrait(model, t, start)
    randomTrait!(end, model, t, start)

Simulate traits along one edge of length t.
`start` must be a vector of integers, each representing the starting value of one trait.
The bang version (ending with !) uses the vector `end` to store the simulated values.

# Examples
```julia-repl
julia> m1 = PhyloNetworks.BinaryTraitSubstitutionModel(1.0, 2.0) 
julia> srand(12345);
julia> randomTrait(m1, 0.2, [1,2,1,2,2])
 5-element Array{Int64,1}:
 1
 2
 1
 2
 2
```
"""
function randomTrait(mod::SM, t::Float64, start::AbstractVector{Int})
    res = Vector{Int}(length(start))
    randomTrait!(res, mod, t, start)
end

function randomTrait!(endTrait::AbstractVector{Int}, mod::SM, t::Float64, start::AbstractVector{Int})
    Pt = P(mod, t)
    k = size(Pt, 1) # number of states
    w = [aweights(Pt[i,:]) for i in 1:k]
    for i in 1:length(start)
        endTrait[i] =sample(1:k, w[start[i]])
    end
    return endTrait
end

"""
    randomTrait(mod, net; ntraits=1, keepInternal=true, checkPreorder=true)

Simulate evolution of discrete traits on a rooted evolutionary network based on
the supplied evolutionary model. Trait sampling is uniform at the root.

# Arguments
- ntraits: number of traits to be simulated (default: 1 trait).
- keepInternal: if true, export character states at all nodes, including
  internal nodes. if false, export character states at tips only.

# Output
- matrix of character states with one row per trait, one column per node
- array of node labels (for tips) or node numbers (for internal nodes)
  in the same order as columns in the character state matrix

# Examples
```julia-repl
julia> m1 = PhyloNetworks.BinaryTraitSubstitutionModel(1.0, 2.0) 
julia> net = readTopology("(A:1.0,(B:1.0,(C:1.0,D:1.0):1.0):1.0);")
julia> srand(12345);
julia> a,b = randomTrait(m1, net)
 ([1 2 … 1 2], String["-2", "-3", "-4", "D", "C", "B", "A"])
julia> a
 1×7 Array{Int64,2}:
 1  2  1  1  1  1  2
julia> b
 7-element Array{String,1}:
 "-2"
 "-3"
 "-4"
 "D"
 "C"
 "B"
 "A"
```
"""

function randomTrait(mod::SM, net::HybridNetwork;
    ntraits=1::Int, keepInternal=true::Bool, checkPreorder=true::Bool)
    net.isRooted || error("net needs to be rooted for preorder recursion")
    if(checkPreorder)
        preorder!(net)
    end
    nnodes = net.numNodes
    M = Matrix{Int}(ntraits, nnodes) # M[i,j]= trait i for node j
    randomTrait!(M,mod,net)
    if !keepInternal
        M = getTipSubmatrix(M, net, indexation=:cols) # subset columns only. rows=traits
        nodeLabels = [n.name for n in net.nodes_changed if n.leaf]
    else
        nodeLabels = [n.name == "" ? string(n.number) : n.name for n in net.nodes_changed]    
    end
    return M, nodeLabels
end

function randomTrait!(M::Matrix{Int}, mod::SM, net::HybridNetwork)
    recursionPreOrder!(net.nodes_changed, M, # updates M in place
            updateRootRandomTrait!,
            updateTreeRandomTrait!,
            updateHybridRandomTrait!,
            mod)
end

function updateRootRandomTrait!(V::AbstractArray, i::Int, mod)
    sample!(1:nStates(mod), view(V, :, i)) # uniform at the root
    return
end

function updateTreeRandomTrait!(V::Matrix,
    i::Int,parentIndex::Int,edge::PhyloNetworks.Edge,
    mod)
    randomTrait!(view(V, :, i), mod, edge.length, view(V, :, parentIndex))
end

function updateHybridRandomTrait!(V::Matrix,
        i::Int, parentIndex1::Int, parentIndex2::Int,
        edge1::PhyloNetworks.Edge, edge2::PhyloNetworks.Edge, mod)
    randomTrait!(view(V, :, i), mod, edge1.length, view(V, :, parentIndex1))
    tmp = randomTrait(mod, edge2.length, view(V, :, parentIndex2))
    for j in 1:size(V,1) # loop over traits
        if V[j,i] == tmp[j] # both parents of the hybrid node have the same trait
            continue # skip the rest: go to next trait
        end
        if rand() > edge1.gamma
            V[j,i] = tmp[j] # switch to inherit trait of parent 2
        end
    end
end
