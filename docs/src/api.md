# API Reference

All names below are exported by the `RDST` module unless marked *(internal)*.

## Types

**`AbstractRNGStream`** — supertype of stream *generators* (objects that mint
new independent streams): `MRG32k3aGen`, `Xoshiro256plusGen`.

**`AbstractStreamableRNG <: Random.AbstractRNG`** — supertype of usable RNGs
that can navigate streams and substreams: `MRG32k3a`, `Xoshiro256p`.

---

## MRG32k3a

### Constructors

| Signature | Description |
|---|---|
| `MRG32k3a()` | default seed `[12345, 12345, 12345, 12345, 12345, 12345]` |
| `MRG32k3a(x::Vector{Int})` | seed all three states (`Cg = Bg = Ig = x`) |
| `MRG32k3a(x, y, z::Vector{Int})` | explicit current/substream/stream starts |

Seeds are validated with `checkseed`; invalid seeds throw an `AssertionError`.

### Functions

**`rand(rng::MRG32k3a) -> Float64`**
Uniform in [0, 1) with ~32 bits of resolution. This is the native output.

**`rand(rng::MRG32k3a, T)`**
Supported `T`: `Float64`, `Float32`, `Float16`, `UInt8…UInt128`,
`Int8…Int128`, `Bool`, and any `UnitRange` (e.g. `rand(rng, 1:10)`).

**`reset_stream!(rng) -> rng`**
Set the current state (`Cg`) *and* the substream start (`Bg`) back to the
stream start (`Ig`).

**`reset_substream!(rng) -> rng`**
Set `Cg` back to `Bg`.

**`next_substream!(rng) -> rng`**
Advance `Bg` to the next substream boundary (jump of ≈ 2^76 steps) and set
`Cg = Bg`.

**`advance_state!(rng, e::Integer, c::Integer)`**
Jump forward/backward inside the current substream by `n` steps where
`n = 2^e + c`. Negative `e` or `c` move backwards. Cost is O(max(|e|, log |c|))
matrix operations.

**`get_state(rng) -> Vector{Int}`**
Return a copy of `Cg`.

**`checkseed(x) -> Bool`**
`true` iff `x` has length 6, all entries ≥ 0, entries 1–3 are < m1 and not all
zero, entries 4–6 are < m2 and not all zero.

**`DEFAULT_SEED`**
The constant seed vector used by `MRG32k3a()` and `MRG32k3aGen()`.

**`copy(m::MRG32k3a) -> MRG32k3a`**
Independent deep copy of the generator (all three state vectors).

### Stream generation

| Signature | Description |
|---|---|
| `MRG32k3aGen()`, `MRG32k3aGen(seed)` | create a stream generator |
| `next_stream!(gen) -> MRG32k3a` | return a new stream; internal seed leaps 2^127 values ahead |
| `get_state(gen) -> Vector{Int}` | seed that will be used by the next `next_stream!` call |

---

## Xoshiro256+

### Constructors

| Signature | Description |
|---|---|
| `Xoshiro256p(s::NTuple{4,UInt64})` / `Xoshiro256p(v::Vector{<:Unsigned})` | `Cg = Bg = Ig = s` |
| `Xoshiro256p(x, y, z)` | explicit current/substream/stream states |

### Functions

**`rand(rng::Xoshiro256p) -> Float64`**
Uniform in [0, 1), built from a full 64-bit draw.

**`rand(rng::Xoshiro256p, T)`**
Supported `T`: `Float64`, `Float32`, `Float16`, `UInt64`, and
`UnitRange{Int64}` (uniform, unbiased modulo sampling).

**`srand!(rng, seed::Vector{UInt64}) -> rng`**
Re-seed an existing generator (first 4 words are used).

**`reset_stream!(rng) -> rng`**, **`reset_substream!(rng) -> rng`**,
**`next_substream!(rng) -> rng`**
Same semantics as for MRG32k3a; `next_substream!` performs a `short_jump!`
(leap of ≈ 2^96 values).

**`short_jump!(rng) -> rng`**
Jump to the beginning of the next 2^96-value block (Vigna's short jump).

**`long_jump!(rng) -> rng`**
Leap ≈ 2^192 values ahead — used to delimit streams.

**`get_state(rng) -> Vector{UInt64}`**
Copy of the current state `Cg`.

**`copy(rng) -> Xoshiro256p`**
Independent copy.

*(internal)* **`next(rng) -> UInt64`**: raw 64-bit output; also available as
`rand(rng, UInt64)`.

### Stream generation

| Signature | Description |
|---|---|
| `Xoshiro256plusGen(seed::Vector{UInt64})` | create a stream generator (seed must have exactly 4 words) |
| `next_stream!(gen) -> Xoshiro256p` | new independent stream (`long_jump!` from the stored seed) |
| `srand!(gen, seed::Vector{UInt64}) -> gen` | reset the stored seed |
| `get_state(gen) -> Vector{UInt64}` | seed that will be used by the next `next_stream!` call |

---

## Xoshiro / xoroshiro families

All variants share one implementation (`LinRNG{N,S}` internally, `N` = state
words, `S` = scrambler) and expose the same API as [Xoshiro256+](#xoshiro256)
above. Exported types:

| RNGs | Stream generators |
|---|---|
| `Xoroshiro128p`, `Xoroshiro128ss`, `Xoroshiro128pp` | `Xoroshiro128pGen`, `Xoroshiro128ssGen`, `Xoroshiro128ppGen` |
| `Xoshiro256p`, `Xoshiro256ss`, `Xoshiro256pp` | `Xoshiro256plusGen`, `Xoshiro256ssGen`, `Xoshiro256ppGen` |
| `Xoshiro512p`, `Xoshiro512ss`, `Xoshiro512pp` | `Xoshiro512pGen`, `Xoshiro512ssGen`, `Xoshiro512ppGen` |

Constructors accept an `NTuple{N,UInt64}` or a `Vector{<:Unsigned}` of length
`N` (1 or 3 arguments). Available functions: `rand` (Float64/Float32/Float16,
UInt64, ranges), `srand!`, `reset_stream!`, `reset_substream!`,
`next_substream!`, `short_jump!`, `long_jump!`, `get_state`, `copy`.

**`advance_state!(rng, e::Integer, c::Integer) -> rng`**
Jump forward by `n` steps (`n = 2^e + c` if `e > 0`, `n = -2^(-e) + c` if
`e < 0`, `n = c` if `e = 0`) or backward if `n < 0`. Implemented by computing
the jump polynomial `x^n mod p(x)` over GF(2) (p = the family's characteristic
polynomial) and applying it to the current state; distances are reduced
modulo the period. Only `Cg` moves — stream/substream boundaries are kept.
Cost is O((64N)²) GF(2) operations (≈ 10–500 ms depending on family); for the
standard distances prefer `short_jump!`/`long_jump!`, which use precomputed
constants and are allocation-free.

Jump semantics (all xoshiro-family generators):

- `short_jump!(rng)` — jump anchored at the current **substream start** (`Bg`);
  lands at the next substream boundary (2^64 values for xoroshiro128, 2^128
  for xoshiro256, 2^256 for xoshiro512).
- `long_jump!(rng)` — jump anchored at the **stream start** (`Ig`); delimits
  independent streams.
- `next_stream!(gen)` applies the long-jump polynomial to the stored seed.

All jump constants are the official ones from
[xoshiro.di.unimi.it](http://xoshiro.di.unimi.it) and outputs are validated
byte-for-byte against the original C implementations.

---

## Method index

| Function | MRG32k3a | Xoshiro256p |
|---|:---:|:---:|
| `rand` (Float64) | yes | yes |
| `rand` (other floats/ints/bool) | yes | partial |
| `rand` (range) | yes | yes (`UnitRange{Int64}`) |
| `reset_stream!` | yes | yes |
| `reset_substream!` | yes | yes |
| `next_substream!` | yes | yes |
| `advance_state!` | yes | — |
| `srand!` | — | yes |
| `get_state` | yes | yes |
| `next_stream!` (via Gen) | yes | yes |
