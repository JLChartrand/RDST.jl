#This is a stupid but mathematicaly correct fix to generate some kind of Unsigned Int for the generator. It is more than likely 
#a really bad fix (to slow and only generate UInt16 meaning that to generate a UInt64, we must generate 4 UInt16...).
#I am not proud of this but I have to many projects and must move on.
#The code for generating float64 is reused but the before returning the Float64 by myltiplying by norm, the number is converted as UInt16
#all integer are created by taking parts or combining UInt16 bits.
@inline function rand(rng::MRG32k3a, ::Random.SamplerType{UInt16})::UInt16
    p1::Int64 = (PMF.a12 * rng.Cg[2] + PMF.a13 * rng.Cg[1]) % PMF.m1
    p1 += p1 < 0 ? PMF.m1 : 0

    rng.Cg[1] = rng.Cg[2]
    rng.Cg[2] = rng.Cg[3]
    rng.Cg[3] = p1

    p2::Int64 = (PMF.a21 * rng.Cg[6] + PMF.a23 * rng.Cg[4]) % PMF.m2
    p2 += p2 < 0 ? PMF.m2 : 0

    rng.Cg[4] = rng.Cg[5]
    rng.Cg[5] = rng.Cg[6]
    rng.Cg[6] = p2

    UInt64(p1 > p2 ? (p1 - p2) : (p1 + PMF.m1 - p2)) % UInt16
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerType{UInt8})::UInt8
    return rand(rng, UInt16) % UInt8
end

@inline function rand(rng::MRG32k3a, T::Random.SamplerType{Bool})::Bool
    return rand(rng, UInt16) % Bool
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerUnion(UInt32, UInt64, UInt128))
    S = T[]
    numberofUInt16 = div(sizeof(S), 2)
    result = zero(S)
    for _ in 1:numberofUInt16
        result = result << 16
        result += rand(rng, UInt16)
    end
    return result
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerType{Int8})::Int8
    return reinterpret(Int8, rand(rng, UInt8))
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerType{Int16})::Int16
    return reinterpret(Int16, rand(rng, UInt16))
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerType{Int32})::Int32
    return reinterpret(Int32, rand(rng, UInt32))
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerType{Int64})::Int64
    return reinterpret(Int64, rand(rng, UInt64))
end
@inline function rand(rng::MRG32k3a, T::Random.SamplerType{Int128})::Int128
    return reinterpret(Int128, rand(rng, UInt128))
end

"""
Produces a raw random number with 32 bits of precision.
"""
@inline  function rand(rng::MRG32k3a)::Float64

    p1::Int64 = (PMF.a12 * rng.Cg[2] + PMF.a13 * rng.Cg[1]) % PMF.m1
    p1 += p1 < 0 ? PMF.m1 : 0

    rng.Cg[1] = rng.Cg[2]
    rng.Cg[2] = rng.Cg[3]
    rng.Cg[3] = p1

    p2::Int64 = (PMF.a21 * rng.Cg[6] + PMF.a23 * rng.Cg[4]) % PMF.m2
    p2 += p2 < 0 ? PMF.m2 : 0

    rng.Cg[4] = rng.Cg[5]
    rng.Cg[5] = rng.Cg[6]
    rng.Cg[6] = p2

    u::Float64 = p1 > p2 ? (p1 - p2) * PMF.norm : (p1 + PMF.m1 - p2) * PMF.norm
end

# MRG32k3a produces natively Float64
Random.rng_native_52(::MRG32k3a) = Float64