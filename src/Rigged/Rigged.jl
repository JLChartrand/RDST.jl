mutable struct Rigged{N} <: AbstractStreamableRNG
    values::Vector
    index::Int64
    function Rigged(values::Vector)
        @assert(reduce(&, (x -> (0 <x < 1)).(values)))
        index = 1
        N = length(values)
        return new{N}(values, index)
    end
end

function reset_stream!(r::Rigged{N}) where N
    r.index = 1
end
    
reset_substream!(r::Rigged{N}) where {N} = reset_stream!(r::Rigged{N})


function rand_inbounds(r::Rigged{N}, ::Random.CloseOpen12_64) where N
    if r.index > N
        r.index = 1
    end
    val = r.values[r.index] + 1.0
    r.index += 1
    return val
end

function rand_inbounds(r::Rigged{N}, ::Random.CloseOpen01_64=Random.CloseOpen01()) where N
    if r.index > N
        r.index = 1
    end
    val = r.values[r.index]
    r.index += 1
    return val
end

############################
rand_inbounds(r::Rigged, ::Random.UInt52Raw{T}) where {T<:Random.BitInteger} = reinterpret(UInt64, rand_inbounds(r, Random.CloseOpen12())) % T


function rand(r::Rigged, x::Random.SamplerTrivial{Random.UInt52Raw{UInt64}})
    rand_inbounds(r, x[])
end

function rand(r::Rigged, ::Random.SamplerTrivial{Random.UInt2x52Raw{UInt128}})
    rand_inbounds(r, Random.UInt52Raw(UInt128)) << 64 | rand_inbounds(r, Random.UInt52Raw(UInt128))
end

function rand(r::Rigged, ::Random.SamplerTrivial{Random.UInt104Raw{UInt128}})
    reserve(r, 2)
	xor(rand_inbounds(r, Random.UInt52Raw(UInt128)) << 52, rand_inbounds(r, Random.UInt52Raw(UInt128)))
end

#### floats

rand(r::Rigged, sp::Random.SamplerTrivial{Random.CloseOpen12_64}) = rand_inbounds(r, sp[])
