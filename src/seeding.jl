# Standard `Random.seed!` interface for all generators ------------------------------

const _GOLDEN = 0x9E3779B97f4A7C15

"Expand an arbitrary integer seed into n well-distributed 64-bit words (splitmix64)."
function _splitmix_words(seed::UInt64, n::Int)
    out = Vector{UInt64}(undef, n)
    sm = seed
    for i in 1:n
        sm += _GOLDEN
        z = sm
        z = (z ⊻ (z >> 30)) * 0xBF58476D1CE4E5B9
        z = (z ⊻ (z >> 27)) * 0x94D049BB133111EB
        out[i] = z ⊻ (z >> 31)
    end
    return out
end

"""
    Random.seed!(rng::LinRNG, seed::Integer) -> rng
    Random.seed!(rng::LinRNG, seed::Vector{UInt64}) -> rng

Re-seed the generator with all three checkpoints equal. Integer seeds are
expanded through splitmix64 (Vigna's recommended initialization).
"""
function Random.seed!(rng::LinRNG{N}, seed::Integer) where {N}
    ws = _splitmix_words(UInt64(seed), N)
    all(iszero, ws) && (ws[1] = 0x9e3779b97f4a7c15)      # never an all-zero state
    rng.Cg = rng.Bg = rng.Ig = NTuple{N,UInt64}(ws)
    return rng
end

function Random.seed!(rng::LinRNG{N}, seed::Vector{<:Unsigned}) where {N}
    length(seed) == N || throw(ArgumentError("seed must have $N UInt64 elements"))
    rng.Cg = rng.Bg = rng.Ig = NTuple{N,UInt64}(seed)
    return rng
end

"""
    Random.seed!(rng::MRG32k3a, seed::Integer) -> rng
    Random.seed!(rng::MRG32k3a, seed::AbstractVector{<:Integer}) -> rng

Re-seed the generator with all three states equal. Integer seeds are expanded
through splitmix64 and folded into the valid MRG32k3a seed space; vector seeds
must satisfy `checkseed`.
"""
function Random.seed!(rng::MRG32k3a, seed::Integer)
    w = _splitmix_words(UInt64(seed), 6)
    v = Vector{Int}(undef, 6)
    for i in 1:3
        v[i] = Int(w[i] % PMF.m1)
    end
    for i in 4:6
        v[i] = Int(w[i] % PMF.m2)
    end
    all(iszero, view(v, 1:3)) && (v[1] = 1)
    all(iszero, view(v, 4:6)) && (v[4] = 1)
    rng.Cg[:] = rng.Bg[:] = rng.Ig[:] = v
    return rng
end

function Random.seed!(rng::MRG32k3a, seed::AbstractVector{<:Integer})
    s = Int.(collect(seed))
    checkseed(s) || throw(ArgumentError("invalid MRG32k3a seed"))
    rng.Cg[:] = rng.Bg[:] = rng.Ig[:] = s
    return rng
end

"""
    Random.seed!(rng::CBRNG, seed::Integer) -> rng
    Random.seed!(rng::CBRNG, seed::AbstractVector{<:Integer}) -> rng

Re-seed a counter-based stream: the seed selects the key and the counter is
rewound to the beginning of the stream. Integer seeds are expanded through
splitmix64; vector seeds must hold exactly the key words.
"""
function Random.seed!(rng::CBRNG{B,W,N,K}, seed::Integer) where {B,W,N,K}
    ws = _splitmix_words(UInt64(seed), K)
    return srand!(rng, NTuple{K,W}([w % W for w in ws]))
end

Random.seed!(rng::CBRNG, seed::AbstractVector{<:Integer}) = srand!(rng, seed)

"""
    Random.seed!(rng::PCGRNG, seed::Integer) -> rng
    Random.seed!(rng::PCGRNG, seed::AbstractVector{<:Integer}) -> rng

Re-seed the generator with all three checkpoints equal. Integer seeds are
expanded through splitmix64 into the 128-bit state. Every state is a valid LCG
state, so no seed is rejected.
"""
function Random.seed!(rng::PCGRNG, seed::Integer)
    ws = _splitmix_words(UInt64(seed), 2)
    return srand!(rng, (UInt128(ws[1]) << 64) | UInt128(ws[2]))
end

Random.seed!(rng::PCGRNG, seed::AbstractVector{<:Integer}) = srand!(rng, seed)
