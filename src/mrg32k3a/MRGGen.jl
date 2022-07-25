
"""
An object that generates independent random number streams.
"""
mutable struct MRG32k3aGen <: AbstractRNGStream
    seed::Vector{Int64}

    function MRG32k3aGen(x::Vector{Int} = PMF.DEFAULT_SEED)
        @assert(PMF.checkseed(x))
        new(copy(x))
    end
end
#show imported in RDST/src.jl
function show(io::IO,rng_gen::MRG32k3aGen)
    print(io,"Seed for next MRG32k3a generator:\n$(rng_gen.seed)")
end

"""
`get_state` return the seed used to generate non-overlaping MRGs
"""
get_state(rng_gen::MRG32k3aGen) = copy(rng_gen.seed)

"""
Given an RNG generator object, returns the next RNG stream.
"""
function next_stream(rng_gen::MRG32k3aGen)
    rng = MRG32k3a(copy(rng_gen.seed))

    rng_gen.seed[1:3] = PMF.MatVecModM(PMF.A1p127, rng_gen.seed[1:3], PMF.m1)
    rng_gen.seed[4:6] = PMF.MatVecModM(PMF.A2p127, rng_gen.seed[4:6], PMF.m2)

    return rng
end