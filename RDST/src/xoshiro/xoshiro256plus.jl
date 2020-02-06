
using Random

import Base.rand

include("xos256p.jl")

"""
return a random Float64 in [0, 1)
"""
function rand(xos::Xoshiro256p)
    r = next(xos)
    return r/(UInt64(0)-1) # return a random UInt64 divided by the largest UInt64 possible (UInt64(0) - 1)
end


"""
Seeds a given random number generator with seed x.
"""    
function srand(rng::Xoshiro256p,seed::Vector{UInt64})
    for i = 1:6
        rng.Cg[i] = rng.Bg[i] = rng.Ig[i] = seed[i]     
    end
end

"""
Resets a given random number generator to the beginning of the current stream.
"""
function reset_stream!(rng::Xoshiro256p)
    for i = 1:4
        rng.Cg[i] = rng.Bg[i] = rng.Ig[i]
    end
end

function reset_substream!(rng::Xoshiro256p)
    for i = 1:4
        rng.Cg[i] = rng.Bg[i]
    end
end



function next_substream!(rng::Xoshiro256p)
    short_jump(rng)
end

mutable struct Xoshiro256plusGen <: AbstractRNGStream
    nextSeed::Vector{UInt64}
    function Xoshiro256plusGen(x::Vector{UInt64})
        new(copy(x))
    end
end

function show(io::IO,rng_gen::Xoshiro256plusGen)
    print(io, "Seed for next Xoshiro256plus generator:\n$(rng_gen.nextSeed)")
end

function show(io::IO,rng::Xoshiro256p)
    print(io,"Full state of Xoshiro256plus generator:\nCg = $(rng.Cg)\nBg = $(rng.Bg)\nIg = $(rng.Ig)")
end

#get_state(rng_gen::MRG32k3aGen) = copy(rng_gen.nextSeed)
#get_state(rng::MRG32k3a) = copy(rng.Cg)

"""
Reseeds the RNG generator object.
"""
function srand(rng_gen::Xoshiro256plusGen,seed::Vector{UInt64})
    for i = 1:4
        rng_gen.nextSeed[i] = seed[i]
    end
end

"""
Given an RNG generator object, returns the next RNG stream.
"""
function next_stream(rng_gen::Xoshiro256plusGen)
    rng = Xoshiro256p(copy(rng_gen.nextSeed))
    rng2 = Xoshiro256p(copy(rng_gen.nextSeed))
    long_jump(rng)
    rng_gen.nextSeed[:] = rng.Cg
    return rng2
end