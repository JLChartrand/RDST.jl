"""
Generates a `Float64` from a `Xoshiro256p` instance.
"""
function rand(rng::Xoshiro256p, ::Type{Float64})
    rand(rng)
end

"""
Generates a `Float32` from a `MRG32k3a` instance.
"""
function rand(rng::Xoshiro256p, ::Type{Float32})
    convert(Float32, rand(rng))
end

"""
Generates a `Float16` from a `MRG32k3a` instance.
"""
function rand(rng::Xoshiro256p, ::Type{Float16})
    convert(Float16, rand(rng))
end

"""
Generates a `Int64` in the given range from a `MRG32k3a` instance.
"""
function rand(rng::Xoshiro256p, r::UnitRange{Int64})
    r.start + convert(Int64, (r.stop - r.start) * rand(rng, Float64))
end