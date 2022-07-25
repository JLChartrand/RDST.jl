"""
Streamable Random Number Generator, see `AbstractStreamableRNG`
"""

module RDST

using Random

import Base: rand, show, copy

export AbstractRNGStream, AbstractStreamableRNG
export checkseed, MRG32k3a, rand, srand, reset_stream!, reset_substream!, next_substream!, MRG32k3aGen, show, get_state, next_stream



###mrg32k3a
include("abstract.jl")
include("mrg32k3a/main.jl")

end # module
