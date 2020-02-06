rand_inbounds(r::MRG32k3a, ::Random.CloseOpen12_64) = rand(r)+1.0
rand_inbounds(r::MRG32k3a, ::Random.CloseOpen01_64=Random.CloseOpen01()) = rand(r)


############################
rand_inbounds(r::MRG32k3a, ::Random.UInt52Raw{T}) where {T<:Random.BitInteger} = reinterpret(UInt64, rand_inbounds(r, Random.CloseOpen12())) % T


function rand(r::MRG32k3a, x::Random.SamplerTrivial{Random.UInt52Raw{UInt64}})
    rand_inbounds(r, x[])
end

function rand(r::MRG32k3a, ::Random.SamplerTrivial{Random.UInt2x52Raw{UInt128}})
    rand_inbounds(r, Random.UInt52Raw(UInt128)) << 64 | rand_inbounds(r, Random.UInt52Raw(UInt128))
end

function rand(r::MRG32k3a, ::Random.SamplerTrivial{Random.UInt104Raw{UInt128}})
    reserve(r, 2)
	xor(rand_inbounds(r, Random.UInt52Raw(UInt128)) << 52, rand_inbounds(r, Random.UInt52Raw(UInt128)))
end

#### floats

rand(r::MRG32k3a, sp::Random.SamplerTrivial{Random.CloseOpen12_64}) = rand_inbounds(r, sp[])
