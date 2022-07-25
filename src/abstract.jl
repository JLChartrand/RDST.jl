"""
`AbstractRNGStream` is an abstraction for creating RNG objects with non-overlaping random numbers.
"""
abstract type AbstractRNGStream end
"""
`AbstractStreamableRNG` is a special kind of RNG where one can move between different stream of number that are known to be non-overlapping.
"""
abstract type AbstractStreamableRNG <: AbstractRNG end # object of subtype of AbstractStreamableRNG are StreamableRNG