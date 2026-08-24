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
