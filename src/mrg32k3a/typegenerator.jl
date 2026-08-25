# All integer types are derived from the native Float64 step: the pair (p1, p2)
# is combined exactly as for the float, but truncated to UInt16, then assembled
# into wider unsigned types by concatenating 16-bit chunks.

@inline rand(rng::MRG32k3a, ::Random.SamplerType{UInt16})::UInt16 =
    UInt64(let (p1, p2) = next_pair!(rng)
        p1 > p2 ? (p1 - p2) : (p1 + PMF.m1 - p2)
    end) % UInt16

@inline rand(rng::MRG32k3a, ::Random.SamplerType{UInt8})::UInt8 = rand(rng, UInt16) % UInt8

@inline rand(rng::MRG32k3a, ::Random.SamplerType{Bool})::Bool = rand(rng, UInt16) % Bool

@inline function rand(rng::MRG32k3a, ::Type{S}) where {S <: Union{UInt32, UInt64, UInt128}}
    result = zero(S)
    for _ in 1:(sizeof(S) >> 1)
        result = (result << 16) + rand(rng, UInt16)
    end
    return result
end

@inline rand(rng::MRG32k3a, ::Random.SamplerType{Int8})::Int8 = reinterpret(Int8, rand(rng, UInt8))
@inline rand(rng::MRG32k3a, ::Random.SamplerType{Int16})::Int16 = reinterpret(Int16, rand(rng, UInt16))
@inline rand(rng::MRG32k3a, ::Random.SamplerType{Int32})::Int32 = reinterpret(Int32, rand(rng, UInt32))
@inline rand(rng::MRG32k3a, ::Random.SamplerType{Int64})::Int64 = reinterpret(Int64, rand(rng, UInt64))
@inline rand(rng::MRG32k3a, ::Random.SamplerType{Int128})::Int128 = reinterpret(Int128, rand(rng, UInt128))

"""
Produces a raw random number with 32 bits of precision.
"""
@inline function rand(rng::MRG32k3a)::Float64
    p1, p2 = next_pair!(rng)
    return p1 > p2 ? (p1 - p2) * PMF.norm : (p1 + PMF.m1 - p2) * PMF.norm
end

rand(rng::MRG32k3a, ::Type{Float64}) = rand(rng)

"""
Hook required by Random's generic machinery for Float64-native generators:
produces a Float64 in [1, 2). Everything else (ints, arrays, shuffle...)
derives from this without further plumbing.
"""
rand(rng::MRG32k3a, ::Random.SamplerTrivial{Random.CloseOpen12_64}) = 1.0 + rand(rng)

# Full-width 64-bit channel assembled from two [1,2) draws (each carries 52
# random bits); enables BigFloat and anything else requiring has_fast_64.
Random.has_fast_64(::MRG32k3a) = true
rand(rng::MRG32k3a, ::Random.SamplerType{UInt64}) =
    (reinterpret(UInt64, rand(rng, Random.CloseOpen12_64())) << 12) ⊻
    (reinterpret(UInt64, rand(rng, Random.CloseOpen12_64())) >>> 40)

# MRG32k3a produces natively Float64
Random.rng_native_52(::MRG32k3a) = Float64
