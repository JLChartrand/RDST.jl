

"""
`MRG32k3a()` will generate an instance of `MRG32k3a` with initial seeds `DEFAULT_SEED = [ 12345, 12345, 12345, 12345, 12345, 12345 ]`

`MRG32k3a(x::Vector{Int})` will generate an instance of `MRG32k3a` with initial seeds `x`

`MRG32k3a(x::Vector{Int}, y::Vector{Int}, z::Vector{Int})` will generate an instance of `MRG32k3a` with `Cg = x`, `Bg = y` and `Ig = z`
"""
mutable struct MRG32k3a <: AbstractStreamableRNG
    Cg::Vector{Int64}  # the current state of the RNG
    Bg::Vector{Int64}  # the start point of the current substream
    Ig::Vector{Int64}  # the start point of the current stream
    function MRG32k3a(x::Vector{Int} = DEFAULT_SEED)
        @assert(PMF.checkseed(x))
        new(copy(x),copy(x),copy(x))
    end
    function MRG32k3a(x::Vector{Int}, y::Vector{Int}, z::Vector{Int})
        @assert(PMF.checkseed(x))
        @assert(PMF.checkseed(y))
        @assert(PMF.checkseed(z))
        return new(copy(x),copy(y),copy(z))
    end
end
#copy imported in RDST.jl in src
function copy(m::MRG32k3a)
    MRG32k3a(copy(m.Cg), copy(m.Bg), copy(m.Ig))
end


"""
Resets a given random number generator to the beginning of the current stream.
"""
function reset_stream!(rng::MRG32k3a)::MRG32k3a
    rng.Cg[:] = rng.Ig
    rng.Bg[:] = rng.Ig
    return rng
end

"""
Resets a given random number generator to the beginning of the current substream.
"""
function reset_substream!(rng::MRG32k3a)::MRG32k3a
    rng.Cg[:] = rng.Bg
    return rng
end
"""
Takes a random number generator and shifts seed to next substream.
"""
function next_substream!(rng::MRG32k3a)::MRG32k3a
    rng.Bg[1:3] = PMF.MatVecModM(PMF.A1p76, rng.Bg[1:3], PMF.m1)
    rng.Bg[4:6] = PMF.MatVecModM(PMF.A2p76, rng.Bg[4:6], PMF.m2)
    for i = 1:6
        rng.Cg[i] = rng.Bg[i]
    end
    return rng
end
#show imported in RDST/src.jl
function show(io::IO,rng::MRG32k3a)
    print(io,"Full state of MRG32k3a generator:\nCg = $(rng.Cg)\nBg = $(rng.Bg)\nIg = $(rng.Ig)")
end

function get_state(rng::MRG32k3a)::Array{Int, 1}
    return copy(rng.Cg)
end


"""
Given a random number generator, jumps n steps forward if n > 0
(or -n steps backwards if n < 0), where

if e > 0, let n = 2^e + c;
if e < 0, let n = -2^(-e) + c;
if e = 0, let n = c.
"""
function advance_state!(rng::MRG32k3a, e::Int64, c::Int64)
    if c >= 0
        C1 = PMF.MatPowModM(PMF.A1p0, c, PMF.m1)
        C2 = PMF.MatPowModM(PMF.A2p0, c, PMF.m2)
    else
        C1 = PMF.MatPowModM(PMF.InvA1,-c, PMF.m1)
        C2 = PMF.MatPowModM(PMF.InvA2,-c, PMF.m2)
    end

    if e > 0
        B1 = PMF.MatTwoPowModM(PMF.A1p0, e, PMF.m1)
        B2 = PMF.MatTwoPowModM(PMF.A2p0, e, PMF.m2)
    elseif e < 0
        B1 = PMF.MatTwoPowModM(PMF.InvA1,-e, PMF.m1)
        B2 = PMF.MatTwoPowModM(PMF.InvA2,-e, PMF.m2)
    end

    if ~(e == 0)
        C1 = PMF.MatMatModM(B1, C1, PMF.m1)
        C2 = PMF.MatMatModM(B2, C2, PMF.m2)
    end

    rng.Cg[1:3] = PMF.MatVecModM(C1, rng.Cg[1:3], PMF.m1)
    rng.Cg[4:6] = PMF.MatVecModM(C2, rng.Cg[4:6], PMF.m2)
end
