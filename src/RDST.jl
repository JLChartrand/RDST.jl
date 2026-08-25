"""
Streamable Random Number Generator, see `AbstractStreamableRNG`
"""

module RDST

using Random

import Base: rand, show, copy

export AbstractRNGStream, AbstractStreamableRNG
export checkseed, MRG32k3a, rand, srand!, reset_stream!, reset_substream!, next_substream!, MRG32k3aGen, show, get_state, next_stream!
export Xoshiro256p, Xoshiro256plusGen, short_jump!, long_jump!, advance_state!
# deprecated names kept for compatibility (warn on use)
export srand, short_jump, long_jump, next_stream



###mrg32k3a
include("abstract.jl")
include("mrg32k3a/main.jl")

###xoshiro / xoroshiro families (Blackman & Vigna)
include("xoshiro/xos256p.jl")
include("xoshiro/xoshiro256plus_types.jl")

export Xoroshiro128p, Xoroshiro128ss, Xoroshiro128pp,
       Xoshiro256p, Xoshiro256ss, Xoshiro256pp,
       Xoshiro512p, Xoshiro512ss, Xoshiro512pp,
       Xoroshiro128pGen, Xoroshiro128ssGen, Xoroshiro128ppGen,
       Xoshiro256plusGen, Xoshiro256ssGen, Xoshiro256ppGen,
       Xoshiro512pGen, Xoshiro512ssGen, Xoshiro512ppGen

end # module
