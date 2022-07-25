"""
Generates a `Union{Float16, Float32}` from a `MRG32k3a` instance.
"""
function rand(rng::MRG32k3a, ::Type{T})::T where {T <: Union{Float16, Float32}}
    convert(T, rand(rng) )
end
"""
Generates a `Int64` in the given range from a `MRG32k3a` instance.
"""
function rand(rng::MRG32k3a, r::UnitRange{Int64})
    r.start + convert(Int64, (r.stop - r.start) * rand(rng, Float64))
end

