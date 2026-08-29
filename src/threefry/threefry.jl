# Threefry counter-based generators (Salmon, Moraes, Dror & Shaw, SC 2011).
#
# Threefry is a non-cryptographic reduction of the Threefish block cipher used
# in Skein. Unlike Philox it uses no multiplication at all: each round is
# add / rotate / xor only, which makes it reproducible bit-for-bit on any
# architecture and the fastest of the family on CPUs without AES-NI. Salmon
# et al. recommend 20 rounds there (13 already pass Crush; 20 keeps a margin).
#
# The generic counter/key/stream machinery lives in cbrng/cbrng.jl; this file
# only supplies the bijection and the concrete aliases.

# Skein key-schedule parity constants.
const THREEFRY_PARITY32 = UInt32(0x1BD11BDA)
const THREEFRY_PARITY64 = UInt64(0x1BD11BDAA9FC1A22)

@inline _threefry_parity(::Type{UInt32}) = THREEFRY_PARITY32
@inline _threefry_parity(::Type{UInt64}) = THREEFRY_PARITY64

# Skein rotation constants, one pair per round, repeating with period 8.
const THREEFRY_ROT_4x32 = ((10, 26), (11, 21), (13, 27), (23, 5),
                           ( 6, 20), (17, 11), (25, 10), (18, 20))
const THREEFRY_ROT_4x64 = ((14, 16), (52, 57), (23, 40), ( 5, 37),
                           (25, 33), (46, 12), (58, 22), (32, 32))

@inline _threefry_rot(::Type{UInt32}) = THREEFRY_ROT_4x32
@inline _threefry_rot(::Type{UInt64}) = THREEFRY_ROT_4x64

@inline _rotl(x::W, k::Int) where {W<:Unsigned} = (x << k) | (x >>> (8 * sizeof(W) - k))

"""
Threefish key schedule: the four key words plus the parity word that makes
their sum invariant, used round-robin at each key injection.
"""
@inline function _threefry_ks(key::NTuple{4,W}) where {W}
    parity = key[1] ⊻ key[2] ⊻ key[3] ⊻ key[4] ⊻ _threefry_parity(W)
    return (key[1], key[2], key[3], key[4], parity)
end

"""
    threefry(C, K, Val(R) = Val(20)) -> NTuple{4,W}

`R` rounds of Threefry-4x over the counter block `C` under the key `K`: one
output block of `4 * sizeof(W)` bytes of random bits. Rounds alternate between
mixing `(x1, x2)`/`(x3, x4)` and `(x1, x4)`/`(x3, x2)`, with a key injection
after every fourth round.
"""
function threefry(C::NTuple{4,W}, K::NTuple{4,W}, ::Val{R} = Val(20)) where {W,R}
    ks = _threefry_ks(K)
    rot = _threefry_rot(W)

    x = (C[1] + ks[1], C[2] + ks[2], C[3] + ks[3], C[4] + ks[4])   # injection 0
    for r in 0:(R - 1)
        r0, r1 = rot[(r % 8) + 1]
        if iseven(r)
            x1 = x[1] + x[2]
            x2 = _rotl(x[2], r0) ⊻ x1
            x3 = x[3] + x[4]
            x4 = _rotl(x[4], r1) ⊻ x3
        else
            x1 = x[1] + x[4]
            x4 = _rotl(x[4], r0) ⊻ x1
            x3 = x[3] + x[2]
            x2 = _rotl(x[2], r1) ⊻ x3
        end
        x = (x1, x2, x3, x4)

        if r % 4 == 3                       # key injection number s = 1, 2, ...
            s = (r + 1) ÷ 4
            x = (x[1] + ks[(s + 0) % 5 + 1],
                 x[2] + ks[(s + 1) % 5 + 1],
                 x[3] + ks[(s + 2) % 5 + 1],
                 x[4] + ks[(s + 3) % 5 + 1] + W(s))
        end
    end
    return x
end

bijection(::Val{:threefry4x32_20}, ctr::NTuple{4,UInt32}, key::NTuple{4,UInt32}) =
    threefry(ctr, key, Val(20))

bijection(::Val{:threefry4x64_20}, ctr::NTuple{4,UInt64}, key::NTuple{4,UInt64}) =
    threefry(ctr, key, Val(20))

_variant_name(::Type{<:CBRNG{:threefry4x32_20}}) = "Threefry4x32-20"
_variant_name(::Type{<:CBRNG{:threefry4x64_20}}) = "Threefry4x64-20"

# Concrete variants -------------------------------------------------------------

"""
    Threefry4x64RNG([key, [ctr]])

Threefry4x64-20 counter-based stream, the variant Salmon et al. recommend on
CPUs without AES-NI. Four 64-bit key words identify the stream; substreams are
`2^64` blocks apart. Only the low 128 bits of its 256-bit counter space are
used, which still gives `2^130` draws per substream.
"""
const Threefry4x64RNG = CBRNG{:threefry4x64_20,UInt64,4,4}

"""
    Threefry4x64Gen([seed])

Hands out independent [`Threefry4x64RNG`](@ref) streams, one distinct key each.
"""
const Threefry4x64Gen = CBGen{:threefry4x64_20,UInt64,4,4}

"""
    Threefry4x32RNG([key, [ctr]])

Threefry4x32-20 counter-based stream: same construction as
[`Threefry4x64RNG`](@ref) with 32-bit words, for a 128-bit counter and a
128-bit key.
"""
const Threefry4x32RNG = CBRNG{:threefry4x32_20,UInt32,4,4}

"""
    Threefry4x32Gen([seed])

Hands out independent [`Threefry4x32RNG`](@ref) streams, one distinct key each.
"""
const Threefry4x32Gen = CBGen{:threefry4x32_20,UInt32,4,4}
