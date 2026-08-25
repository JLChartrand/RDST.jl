"""
Generates a `Float32` from any xoshiro/xoroshiro generator.
"""
rand(rng::LinRNG, ::Type{Float32}) = Float32(rand(rng))

"""
Generates a `Float16` from any xoshiro/xoroshiro generator.
"""
rand(rng::LinRNG, ::Type{Float16}) = Float16(rand(rng))

"""
Generates an `Int64` uniformly distributed in the given range.
"""
function rand(rng::LinRNG, r::UnitRange{Int64})
    n = UInt64(length(r))
    return r.start + reinterpret(Int64, rand(rng, UInt64) % n)
end

# Full Random-API coverage for integer and character types, mirroring the
# derivation used by the standard library's Xoshiro.

rand(rng::LinRNG, ::Random.SamplerType{Bool}) = (next(rng) >> 63) == 1

for T in (UInt8, UInt16, UInt32)
    @eval rand(rng::LinRNG, ::Random.SamplerType{$T}) = next(rng) % $T
end

rand(rng::LinRNG, ::Random.SamplerType{UInt128}) =
    (UInt128(next(rng)) << 64) | UInt128(next(rng))

for (S, U) in ((Int8, UInt8), (Int16, UInt16), (Int32, UInt32), (Int64, UInt64), (Int128, UInt128))
    @eval rand(rng::LinRNG, ::Random.SamplerType{$S}) = reinterpret($S, rand(rng, $U))
end

rand(rng::LinRNG, ::Random.SamplerType{Char}) = Char(rand(rng, 0x0000:0xd7ff))
