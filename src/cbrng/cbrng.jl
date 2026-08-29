using Random

import Base.rand

# ---------------------------------------------------------------------------
# Counter-based random number generators (CBRNGs).
#
# A CBRNG produces its output block as a keyed bijection of a counter,
# `R = b_K(C)`, instead of iterating a state transition. Every family in this
# file shares that skeleton: a counter, a key, the block of words most recently
# produced, and the position of the next unconsumed word in that block. Only
# the bijection `bijection(Val(B), ctr, key)` differs between variants, so a
# new family (Philox4x64, Threefry, ARS, ...) only has to supply that one
# method plus its `_variant_name`.
# ---------------------------------------------------------------------------

"""
    CBRNG{B,W,N,K}

Counter-based generator, where `B` names the bijection, `W` is the word type,
`N` the number of words in an output block and `K` the number of key words.
Concrete aliases (`PhiloxRNG`, `Philox4x64RNG`, ...) are what user code
normally names.

Streams are indexed by the key, substreams by the high half of the counter;
see [`next_stream!`](@ref) and [`next_substream!`](@ref).
"""
mutable struct CBRNG{B,W,N,K} <: AbstractStreamableRNG
    ctr::UInt128            # index of the *next* block to produce
    key::NTuple{K,W}        # stream identifier
    buffer::NTuple{N,W}     # block most recently produced
    idx::Int                # position of the next word in `buffer`

    CBRNG{B,W,N,K}(ctr::UInt128, key::NTuple{K,W}, buffer::NTuple{N,W}, idx::Int) where {B,W,N,K} =
        new{B,W,N,K}(ctr, key, buffer, idx)
end

# `idx = N + 1` marks an exhausted buffer: the first draw then produces a block.
CBRNG{B,W,N,K}(key::NTuple{K,W}, ctr::UInt128 = UInt128(0)) where {B,W,N,K} =
    CBRNG{B,W,N,K}(ctr, key, ntuple(_ -> zero(W), Val(N)), N + 1)

CBRNG{B,W,N,K}(key::AbstractVector{<:Integer}, ctr::UInt128 = UInt128(0)) where {B,W,N,K} =
    CBRNG{B,W,N,K}(_key_tuple(CBRNG{B,W,N,K}, key), ctr)

CBRNG{B,W,N,K}() where {B,W,N,K} = CBRNG{B,W,N,K}(ntuple(_ -> zero(W), Val(K)))

copy(rng::CBRNG{B,W,N,K}) where {B,W,N,K} =
    CBRNG{B,W,N,K}(rng.ctr, rng.key, rng.buffer, rng.idx)

function _key_tuple(::Type{<:CBRNG{B,W,N,K}}, key::AbstractVector{<:Integer}) where {B,W,N,K}
    length(key) == K ||
        throw(ArgumentError("a $(_variant_name(CBRNG{B,W,N,K})) key must have $K $W elements"))
    return NTuple{K,W}(W.(key))
end

# Counter geometry -------------------------------------------------------------
# The counter is kept as a native UInt128: incrementing it costs one add, with
# no carry loop. A block of N words of type W addresses N*8*sizeof(W) counter
# bits; anything wider than 128 bits is simply left at zero.

@inline _ctr_bits(::Type{W}, ::Val{N}) where {W,N} = min(128, N * 8 * sizeof(W))

@inline function _ctr_mask(::Type{W}, ::Val{N}) where {W,N}
    b = _ctr_bits(W, Val(N))
    return b >= 128 ? typemax(UInt128) : (UInt128(1) << b) - UInt128(1)
end

# Substreams split the counter in half: the high bits index the substream.
@inline _substream_shift(::Type{W}, ::Val{N}) where {W,N} = _ctr_bits(W, Val(N)) ÷ 2

@inline _ctr_words(::Type{W}, ::Val{N}, c::UInt128) where {W,N} =
    ntuple(i -> (c >> ((i - 1) * 8 * sizeof(W))) % W, Val(N))

# Raw generator output ---------------------------------------------------------

"""
Raw output of one word of the generator: the next unconsumed word of the
current block, producing a new block (and bumping the counter) once the block
is exhausted.
"""
@inline function next_word(rng::CBRNG{B,W,N,K}) where {B,W,N,K}
    if rng.idx > N
        rng.buffer = bijection(Val(B), _ctr_words(W, Val(N), rng.ctr), rng.key)
        rng.ctr = (rng.ctr + UInt128(1)) & _ctr_mask(W, Val(N))
        rng.idx = 1
    end
    val = @inbounds rng.buffer[rng.idx]      # refill above guarantees 1 <= idx <= N
    rng.idx += 1
    return val
end

"""
Raw 64-bit output of the generator. Families with 32-bit words pair two
consecutive words, low word first; 64-bit families return one word.
"""
@inline next(rng::CBRNG{B,UInt64}) where {B} = next_word(rng)

@inline function next(rng::CBRNG{B,UInt32}) where {B}
    lo = next_word(rng)
    hi = next_word(rng)
    return (UInt64(hi) << 32) | UInt64(lo)
end

@inline _next32(rng::CBRNG{B,UInt32}) where {B} = next_word(rng)
@inline _next32(rng::CBRNG{B,UInt64}) where {B} = next_word(rng) % UInt32

# Random API -------------------------------------------------------------------
# `rng_native_52` tells Julia the generator can hand out 52 good bits directly,
# which selects the fast Float64 path.

Random.rng_native_52(::CBRNG) = UInt64

rand(rng::CBRNG, ::Random.SamplerType{UInt32}) = _next32(rng)
rand(rng::CBRNG, ::Random.SamplerType{UInt64}) = next(rng)

"""
Return a random Float64 in [0, 1).
"""
rand(rng::CBRNG) = Random.rand(rng, Random.CloseOpen01(Float64))

"""
Generates a `Float32` from any counter-based generator.
"""
rand(rng::CBRNG, ::Type{Float32}) = Float32(rand(rng))

"""
Generates a `Float16` from any counter-based generator.
"""
rand(rng::CBRNG, ::Type{Float16}) = Float16(rand(rng))

# Full Random-API coverage for integer and character types, mirroring the
# derivation used for the xoshiro families.

rand(rng::CBRNG, ::Random.SamplerType{Bool}) = (_next32(rng) >> 31) == 1

for T in (UInt8, UInt16)
    @eval rand(rng::CBRNG, ::Random.SamplerType{$T}) = _next32(rng) % $T
end

rand(rng::CBRNG, ::Random.SamplerType{UInt128}) =
    (UInt128(next(rng)) << 64) | UInt128(next(rng))

for (S, U) in ((Int8, UInt8), (Int16, UInt16), (Int32, UInt32), (Int64, UInt64), (Int128, UInt128))
    @eval rand(rng::CBRNG, ::Random.SamplerType{$S}) = reinterpret($S, rand(rng, $U))
end

rand(rng::CBRNG, ::Random.SamplerType{Char}) = Char(rand(rng, 0x0000:0xd7ff))

# Streams and substreams -------------------------------------------------------
# A stream is a key; a substream is a slice of the counter space of that key.

@inline function _seek_substream!(rng::CBRNG{B,W,N,K}, s::Integer) where {B,W,N,K}
    rng.ctr = (UInt128(s) << _substream_shift(W, Val(N))) & _ctr_mask(W, Val(N))
    rng.idx = N + 1                      # discard whatever is left of the block
    return rng
end

@inline _substream_index(rng::CBRNG{B,W,N,K}) where {B,W,N,K} =
    rng.ctr >> _substream_shift(W, Val(N))

"""
    next_substream!(rng) -> rng

Move the generator to the start of the next substream: a jump of
`2^(_substream_shift)` blocks in the counter (2^64 blocks for Philox4x32-10).
"""
next_substream!(rng::CBRNG) = _seek_substream!(rng, _substream_index(rng) + 1)

"""
    reset_substream!(rng) -> rng

Rewind the generator to the beginning of its current substream.
"""
reset_substream!(rng::CBRNG) = _seek_substream!(rng, _substream_index(rng))

"""
    reset_stream!(rng) -> rng

Rewind the generator to the very beginning of its current stream (counter 0).
"""
reset_stream!(rng::CBRNG) = _seek_substream!(rng, 0)

"""
    get_state(rng::CBRNG) -> (ctr, key, buffer, idx)

Full internal state: the index of the next block to produce, the key, the block
most recently produced and the position of the next word to consume in it.
"""
get_state(rng::CBRNG) = (rng.ctr, rng.key, rng.buffer, rng.idx)

"""
    set_state!(rng::CBRNG, state) -> rng

Restores the current position of the stream from a `get_state(rng)` value: the
counter, the key, the buffered block and the index within it.
"""
function set_state!(rng::CBRNG{B,W,N,K}, state) where {B,W,N,K}
    ctr, key, buffer, idx = state
    rng.ctr = UInt128(ctr)
    rng.key = NTuple{K,W}(key)
    rng.buffer = NTuple{N,W}(buffer)
    rng.idx = Int(idx)
    return rng
end

"""
    srand!(rng::CBRNG, key) -> rng

Reseeds the stream with `key` (a tuple or a vector of key words) and rewinds
its counter to the start of the stream.
"""
function srand!(rng::CBRNG{B,W,N,K}, key::NTuple{K,W}) where {B,W,N,K}
    rng.key = key
    return reset_stream!(rng)
end

srand!(rng::CBRNG{B,W,N,K}, key::AbstractVector{<:Integer}) where {B,W,N,K} =
    srand!(rng, _key_tuple(typeof(rng), key))

"""
Given a random number generator, jumps n words forward if n > 0 (or -n words
backwards if n < 0), where

if e > 0, let n = 2^e + c;
if e < 0, let n = -2^(-e) + c;
if e = 0, let n = c.

The unit is one `rand(rng)` draw, the same as for every other generator of the
package. A draw takes 64 bits, so it consumes two words of a 32-bit family and
one word of a 64-bit one. The distance is reduced modulo the counter space, so
any magnitude is accepted. The stream and substream boundaries are not
affected, only the current position.
"""
function advance_state!(rng::CBRNG{B,W,N,K}, e::Integer, c::Integer) where {B,W,N,K}
    n = if e == 0
        BigInt(c)
    elseif e > 0
        BigInt(2)^BigInt(e) + BigInt(c)
    else
        -BigInt(2)^BigInt(-e) + BigInt(c)
    end

    n *= 8 ÷ sizeof(W)                   # draws -> words: 64 bits per draw

    # `ctr` points at the next block, so a loaded buffer sits one block behind.
    pos = rng.idx > N ? BigInt(rng.ctr) * N : (BigInt(rng.ctr) - 1) * N + (rng.idx - 1)
    span = (BigInt(_ctr_mask(W, Val(N))) + 1) * N          # words in the counter space
    blk, off = divrem(mod(pos + n, span), N)

    rng.ctr = UInt128(blk)
    rng.idx = N + 1
    for _ in 1:off                       # re-enter the block at the right word
        next_word(rng)
    end
    return rng
end

function show(io::IO, rng::CBRNG{B,W,N,K}) where {B,W,N,K}
    print(io, "Full state of ", _variant_name(typeof(rng)), " generator:\n",
          "key = ", collect(rng.key), "\n",
          "ctr = 0x", string(rng.ctr, base = 16, pad = 32), "\n",
          "idx = ", rng.idx)
end

# Stream generators ------------------------------------------------------------

"""
    CBGen{B,W,N,K}

Hands out independent [`CBRNG`](@ref) streams, each with its own key. Concrete
aliases (`PhiloxGen`, `Philox4x64Gen`, ...) are what user code normally names.

The generator walks an odometer over the *seeds* `0, 1, 2, ...` and maps each
one through the family's key schedule [`stream_key`](@ref) to obtain the actual
key; see that function for why the two are not the same thing.
"""
mutable struct CBGen{B,W,N,K} <: AbstractRNGStream
    nextSeed::NTuple{K,W}
end

CBGen{B,W,N,K}() where {B,W,N,K} = CBGen{B,W,N,K}(ntuple(_ -> zero(W), Val(K)))
CBGen{B,W,N,K}(seed::AbstractVector{<:Integer}) where {B,W,N,K} =
    CBGen{B,W,N,K}(_key_tuple(CBRNG{B,W,N,K}, seed))

"""
    stream_key(::Val{B}, seed) -> key

Key schedule of the family `B`: the bijection mapping the seed of a stream —
the position `0, 1, 2, ...` walked by [`CBGen`](@ref), or a value the user
supplied through `srand!` — to the key the bijection is actually keyed with.

The default is the identity, which is what Philox uses: L'Ecuyer et al. (2021,
Sec. 3) report that consecutive small keys are safe there, on the strength of
the statistical testing of Salmon et al. (2011) and the ten rounds of encoding.

A family whose bijection is weak for structured keys **must** override this
method with a schedule that hashes the seed. The paper's worked example is
Squares (Widynski 2020): key `0` makes the output identically zero, and a small
key `k` makes roughly the first `2^16 / k` outputs zero, so handing out the
seeds `1, 2, ..., s` as keys "will be very bad unless the keys are hashed to
random-looking values by another mechanism".
"""
stream_key(::Val, seed::NTuple{K,W}) where {K,W} = seed

"""
    next_stream!(gen) -> rng

Returns the next independent stream and moves the generator on to the following
seed. Seeds are walked in lexicographic order and mapped through
[`stream_key`](@ref), a bijection, so distinct streams never share a key and
their counter spaces cannot overlap.
"""
function next_stream!(gen::CBGen{B,W,N,K}) where {B,W,N,K}
    seed = gen.nextSeed
    gen.nextSeed = _increment_seed(seed)
    return CBRNG{B,W,N,K}(stream_key(Val(B), seed))
end

# Odometer increment over the seed words, least significant word last.
@inline function _increment_seed(seed::NTuple{K,W}) where {K,W}
    words = collect(seed)
    for i in K:-1:1
        words[i] += one(W)
        words[i] == zero(W) || break     # no carry out of this word
    end
    return NTuple{K,W}(words)
end

"""
    get_state(gen::CBGen) -> NTuple{K,W}

Seed that the next `next_stream!` call will use. This is the position in the
key schedule, not the key itself; the two coincide only when
[`stream_key`](@ref) is the identity.
"""
get_state(gen::CBGen) = gen.nextSeed

"""
    srand!(gen::CBGen, seed) -> gen

Resets the seed that the next `next_stream!` call will use.
"""
function srand!(gen::CBGen{B,W,N,K}, seed::NTuple{K,W}) where {B,W,N,K}
    gen.nextSeed = seed
    return gen
end

srand!(gen::CBGen{B,W,N,K}, seed::AbstractVector{<:Integer}) where {B,W,N,K} =
    srand!(gen, _key_tuple(CBRNG{B,W,N,K}, seed))

"""
    set_state!(gen::CBGen, seed) -> gen

Restores the seed of the next stream, as returned by `get_state(gen)`.
"""
set_state!(gen::CBGen, seed) = srand!(gen, seed)

function show(io::IO, gen::CBGen{B,W,N,K}) where {B,W,N,K}
    print(io, "Seed for next ", _variant_name(CBRNG{B,W,N,K}), " generator:\n",
          collect(gen.nextSeed))
end
