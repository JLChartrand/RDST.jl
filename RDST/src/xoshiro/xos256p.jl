mutable struct Xoshiro256p <: AbstractStreamableRNG
    Cg::Vector{UInt64}  # the current state of the RNG
    Bg::Vector{UInt64}  # the start point of the current substream
    Ig::Vector{UInt64}  # the start point of the current stream
    
    function Xoshiro256p(x::Vector{UInt})
        new(copy(x),copy(x),copy(x))
    end
    function Xoshiro256p(x::Vector{UInt}, y::Vector{UInt}, z::Vector{UInt})
        new(copy(x),copy(y),copy(z))
    end
end    
rolt(x::UInt64, k::Int64) = (x<<k) | (x >> (64 - k))

function copy(Xos::Xoshiro256p)
    return Xoshiro256p(Xos.Cg, Xos.Bg, Xos.Ig)
end

function next(xos::Xoshiro256p)
    result_plus = xos.Cg[1] +xos.Cg[4]    
    
    t = xos.Cg[2] << 17
    
    
    xos.Cg[3] = xor(xos.Cg[3], xos.Cg[1])
    xos.Cg[4] = xor(xos.Cg[4], xos.Cg[2])
    xos.Cg[2] = xor(xos.Cg[2], xos.Cg[3])
    xos.Cg[1] = xor(xos.Cg[1], xos.Cg[4])
    
    xos.Cg[3] = xor(xos.Cg[3], t)
    
    xos.Cg[4] = rolt(xos.Cg[4], 45)
    
    return result_plus    
end

function short_jump(xos::Xoshiro256p)
    JUMP = [0x180ec6d33cfd0aba, 0xd5a61266f0c9392c, 0xa9582618e03fc9aa, 0x39abdc4529b1661c]
    xos.Cg[:] = xos.Bg[:]
    
    s = [UInt64(0) for i in 1:4]
    for i in 1:4
        for b in 0:63
            if (JUMP[i] & (UInt64(1) << b)) != 0
                #println("-")
                s[:] = xor.(s[:], xos.Cg[:])
            end
            next(xos)
        end
    end
    xos.Cg[:] = s[:]
    xos.Bg[:] = s[:]
end


function long_jump(xos::Xoshiro256p)
    LONG_JUMP = [0x76e15d3efefdcbbf, 0xc5004e441c522fb3, 0x77710069854ee241, 0x39109bb02acbe635]
    xos.Cg[:] = xos.Ig[:]
    s = [UInt64(0) for i in 1:4]
    for i in 1:4
        for b in 0:63
            if (LONG_JUMP[i] & (UInt64(1) << b)) != 0
                s[:] = xor.(s[:], xos.Cg[:])
            end
            next(xos)
        end
    end
    xos.Cg[:] = s[:]
    xos.Bg[:] = s[:]
    xos.Ig[:] = s[:]
end
