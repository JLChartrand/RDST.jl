# Philox4x32-10 counter-based generator (Salmon, Moraes, Dror & Shaw, SC 2011)
# Optimized implementation for native performance (Julia Random API)

import Random

const M0 = UInt32(0xD2511F53)   # Philox multipliers
const M1 = UInt32(0xCD9E8D57)
const W0 = UInt32(0x9E3779B9)   # odd part of phi * 2^32 (Weyl sequence step)
const W1 = UInt32(0xBB67AE85)
const ROUNDS = 10               # Philox4x32-10

# one Philox round: bijection on (x0,x1,x2,x3) with the current subkeys (k0,k1)
@inline function philox_round(x::NTuple{4,UInt32}, k::NTuple{2,UInt32})
    m0 = widemul(x[1], M0)
    m1 = widemul(x[3], M1)
    hi0, lo0 = (m0 >>> 32) % UInt32, m0 % UInt32
    hi1, lo1 = (m1 >>> 32) % UInt32, m1 % UInt32
    y = (hi1 ⊻ x[2] ⊻ k[1], lo1, hi0 ⊻ x[4] ⊻ k[2], lo0)
    return y, (k[1] + W0, k[2] + W1)
end

# Philox4x32-10: R = E_K(C), one 128-bit block of random bits
function philox(C::NTuple{4,UInt32}, K::NTuple{2,UInt32})
    x, k = C, K
    for _ in 1:ROUNDS
        x, k = philox_round(x, k)
    end
    return x
end

# Counter-based stream integrated into the Julia ecosystem (AbstractRNG).
# Optimized state:
# - ctr is a native UInt128 (incrementing is extremely fast without carry loops)
# - buffer stores the 4 generated values to avoid wasting bits.
"""
    PhiloxRNG

A RandomDataStreams compatible wrapper for the Philox4x32-10 Counter-Based RNG.
Each stream uses a distinct key. Substreams are formed by jumping the counter by `2^64`.
"""
mutable struct PhiloxRNG <: AbstractStreamableRNG
    ctr::UInt128
    key::NTuple{2,UInt32}
    buffer::NTuple{4,UInt32}
    idx::Int
end

# Default constructor
function PhiloxRNG(seed_key::NTuple{2,UInt32} = (UInt32(0), UInt32(0)), start_ctr::UInt128 = UInt128(0))
    # idx = 5 forces the generation of a block on the very first call to rand()
    PhiloxRNG(start_ctr, seed_key, (UInt32(0), UInt32(0), UInt32(0), UInt32(0)), 5)
end

# Extracts the 4 UInt32 from the 128-bit counter
@inline function _ctr_to_tuple(c::UInt128)
    return (
        (c & 0xFFFFFFFF) % UInt32,
        ((c >> 32) & 0xFFFFFFFF) % UInt32,
        ((c >> 64) & 0xFFFFFFFF) % UInt32,
        ((c >> 96) & 0xFFFFFFFF) % UInt32
    )
end

# Raw generator output ---------------------------------------------------------

"""
Raw 32-bit output of the generator: one word of the current 128-bit block,
refilling the block (and bumping the counter) once the four words are consumed.
"""
@inline function next32(rng::PhiloxRNG)
    if rng.idx > 4
        rng.buffer = philox(_ctr_to_tuple(rng.ctr), rng.key)
        rng.ctr += 1
        rng.idx = 1
    end
    val = rng.buffer[rng.idx]
    rng.idx += 1
    return val
end

"""
Raw 64-bit output of the generator, assembled from two consecutive 32-bit words.
"""
@inline function next(rng::PhiloxRNG)
    lo = next32(rng)
    hi = next32(rng)
    return (UInt64(hi) << 32) | UInt64(lo)
end

# Random API -------------------------------------------------------------------
# Signals to Julia that this generator can directly provide 52 high-quality bits
# (used for the fast Float64 path).

Random.rng_native_52(::PhiloxRNG) = UInt64

rand(rng::PhiloxRNG, ::Random.SamplerType{UInt32}) = next32(rng)
rand(rng::PhiloxRNG, ::Random.SamplerType{UInt64}) = next(rng)

"""
Return a random Float64 in [0, 1).
"""
rand(rng::PhiloxRNG) = Random.rand(rng, Random.CloseOpen01(Float64))

"""
Generates a `Float32` from the Philox generator.
"""
rand(rng::PhiloxRNG, ::Type{Float32}) = Float32(rand(rng))

"""
Generates a `Float16` from the Philox generator.
"""
rand(rng::PhiloxRNG, ::Type{Float16}) = Float16(rand(rng))

# Full Random-API coverage for integer and character types, mirroring the
# derivation used for the xoshiro families.

rand(rng::PhiloxRNG, ::Random.SamplerType{Bool}) = (next32(rng) >> 31) == 1

for T in (UInt8, UInt16)
    @eval rand(rng::PhiloxRNG, ::Random.SamplerType{$T}) = next32(rng) % $T
end

rand(rng::PhiloxRNG, ::Random.SamplerType{UInt128}) =
    (UInt128(next(rng)) << 64) | UInt128(next(rng))

for (S, U) in ((Int8, UInt8), (Int16, UInt16), (Int32, UInt32), (Int64, UInt64), (Int128, UInt128))
    @eval rand(rng::PhiloxRNG, ::Random.SamplerType{$S}) = reinterpret($S, rand(rng, $U))
end

rand(rng::PhiloxRNG, ::Random.SamplerType{Char}) = Char(rand(rng, 0x0000:0xd7ff))




"""
    PhiloxGen()

A stream generator for the Philox4x32-10 Counter-Based RNG.
Manages the non-overlapping keys used to initialize independent `PhiloxRNG` streams.
"""
mutable struct PhiloxGen <: AbstractRNGStream
    next_key_hi::UInt32
    next_key_lo::UInt32
end
PhiloxGen() = PhiloxGen(0, 0)

# Generate the next independent stream (new key)
function next_stream!(gen::PhiloxGen)
    key = (gen.next_key_hi, gen.next_key_lo)
    if gen.next_key_lo == typemax(UInt32)
        gen.next_key_lo = 0
        gen.next_key_hi += 1
    else
        gen.next_key_lo += 1
    end
    return PhiloxRNG(key, UInt128(0))
end

# In Philox, a substream can be defined by a large jump in the counter, e.g., 2^64
function next_substream!(rng::PhiloxRNG)
    sub_idx = (rng.ctr >> 64) + 1
    rng.ctr = UInt128(sub_idx) << 64
    rng.idx = 5 # force buffer flush
    return rng
end

function reset_substream!(rng::PhiloxRNG)
    sub_idx = (rng.ctr >> 64)
    rng.ctr = UInt128(sub_idx) << 64
    rng.idx = 5
    return rng
end

function reset_stream!(rng::PhiloxRNG)
    rng.ctr = 0
    rng.idx = 5
    return rng
end

"""
    get_state(rng::PhiloxRNG) -> (ctr, key, buffer, idx)

Full internal state of the stream: counter, key, buffered block and the index
of the next word to be consumed in that block.
"""
function get_state(rng::PhiloxRNG)
    return (rng.ctr, rng.key, rng.buffer, rng.idx)
end

# advance_state!(rng, e, c) jumps by 2^e + c if e > 0, -2^(-e) + c if e < 0, or c if e == 0
function advance_state!(rng::PhiloxRNG, e::Integer, c::Integer)
    n = if e == 0
        BigInt(c)
    elseif e > 0
        BigInt(2)^BigInt(e) + BigInt(c)
    else
        -BigInt(2)^BigInt(-e) + BigInt(c)
    end
    
    # Counter arithmetic modulo 2^128
    mask128 = (BigInt(1) << 128) - 1
    rng.ctr = UInt128((BigInt(rng.ctr) + n) & mask128)
    rng.idx = 5
    return rng
end

# Copy, display and seeding ----------------------------------------------------

copy(rng::PhiloxRNG) = PhiloxRNG(rng.ctr, rng.key, rng.buffer, rng.idx)

function show(io::IO, rng::PhiloxRNG)
    print(io, "Full state of Philox4x32-10 generator:\n",
          "key = ", collect(rng.key), "\n",
          "ctr = 0x", string(rng.ctr, base = 16, pad = 32), "\n",
          "idx = ", rng.idx)
end

function show(io::IO, gen::PhiloxGen)
    print(io, "Key for next Philox4x32-10 generator:\n",
          [gen.next_key_hi, gen.next_key_lo])
end

"""
    srand!(rng::PhiloxRNG, key) -> rng

Reseeds the stream with `key` (two 32-bit words, as a tuple or a vector) and
rewinds its counter to the start of the stream.
"""
function srand!(rng::PhiloxRNG, key::NTuple{2,UInt32})
    rng.key = key
    rng.ctr = UInt128(0)
    rng.idx = 5                          # force buffer flush
    return rng
end

srand!(rng::PhiloxRNG, key::AbstractVector{<:Integer}) = srand!(rng, _philox_key(key))

"""
    srand!(gen::PhiloxGen, key) -> gen

Resets the key that the next `next_stream!` call will hand out.
"""
function srand!(gen::PhiloxGen, key::NTuple{2,UInt32})
    gen.next_key_hi, gen.next_key_lo = key
    return gen
end

srand!(gen::PhiloxGen, key::AbstractVector{<:Integer}) = srand!(gen, _philox_key(key))

function _philox_key(key::AbstractVector{<:Integer})
    length(key) == 2 || throw(ArgumentError("a Philox key must have 2 UInt32 elements"))
    return (UInt32(key[1]), UInt32(key[2]))
end

"""
    get_state(gen::PhiloxGen) -> NTuple{2,UInt32}

Key that will be used by the next `next_stream!` call.
"""
get_state(gen::PhiloxGen) = (gen.next_key_hi, gen.next_key_lo)
