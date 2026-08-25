# Implementation Notes

## MRG32k3a

MRG32k3a is L'Ecuyer's combined multiple recursive generator of order 3. It
maintains two 3-component integer states updated by the recurrences

```
p1 = (1403580 · x2 − 810728 · x1) mod m1,      m1 = 2^32 − 209
p2 = (527612  · y2 − 1370589 · y0) mod m2,    m2 = 2^32 − 22853
u  = (p1 − p2) / m1   (with wrap-around) ∈ [0, 1)
```

The combined generator has period ≈ 2^191.

### Modular arithmetic without overflow

All state components stay below `m1 < 2^32`, so products fit in `Float64`
exactly (< 2^53). The helper `MultModM(a, s, c, m)` computes `(a·s + c) mod m`
using this fact and falls back to a split-by-2^17 computation when intermediate
values would exceed 2^53. Matrix helpers:

- `MatVecModM(A, s, m)` — matrix–vector product mod m
- `MatMatModM(A, B, m)` — matrix product mod m
- `MatTwoPowModM(A, e, m)` — A raised to the power 2^e
- `MatPowModM(A, n, m)` — A^n by binary exponentiation

### Streams, substreams, jumps

Moving a stream forward by k steps is a linear operation on its state, hence a
precomputed matrix power applied to the state vector:

| Operation | Matrix | Step |
|---|---|---|
| `next_stream!(gen)` | `A1p127`, `A2p127` | 2^127 values |
| `next_substream!(rng)` | `A1p76`, `A2p76` | 2^76 values |
| `advance_state!(rng, e, c)` | `MatTwoPowModM` / `InvA1`, `InvA2` | arbitrary (inverse matrices allow backward jumps) |

The RNG keeps three checkpoints: `Cg` (current), `Bg` (substream start),
`Ig` (stream start), which is what makes `reset_substream!` and
`reset_stream!` O(1).

## Xoshiro256+

xoshiro256+ (Blackman & Vigna, 2019) keeps four 64-bit words and produces one
word per step with only shifts, XORs and rotations:

```julia
result = s1 + s4
t = s2 << 17
s3 = xor(s3, s1);  s4 = xor(s4, s2);  s2 = xor(s2, s3);  s1 = xor(s1, s4);  s3 = xor(s3, t);  s4 = rotl(s4, 45)
```

The output word is the sum of two internal words (`+` variant): fastest of the
xoshiro family for float generation, though the low three bits of the raw
output have limited linear complexity — irrelevant once scaled to `Float64`
(53 bits used). Period: 2^256 − 1.

### Jumps

`short_jump!` and `long_jump!` use Vigna's published jump polynomials. They are
computed as XOR-linear combinations of states visited while stepping through
the 256 bits of each jump constant. RDST.jl hoists the jump constants into
compile-time tuples and evaluates jumps allocation-free on immutable state
tuples.

RDST semantics differ subtly from the reference C code: jumps are **anchored**
at stream boundaries. `short_jump!(rng)` first resets `Cg ← Bg`, then applies
the jump polynomial, and stores the result in both `Cg` and `Bg`;
`long_jump!(rng)` does the same with respect to `Ig`. This matches L'Ecuyer's
stream model (`next_substream!`/`reset_stream!`) and makes scenario replay
reproducible regardless of consumption inside the current substream.

### Families and scramblers

The package implements all 64-bit variants from xoshiro.di.unimi.it through a
single generic type `LinRNG{N,S}` (state words × scrambler):

- transition `_lin_step` for `NTuple{2}` (xoroshiro128: a=24, b=16, c=37),
  `NTuple{4}` (xoshiro256) and `NTuple{8}` (xoshiro512);
- scramblers `+`, `**` (`rotl(s2·5,7)·9`) and `++`
  (`rotl(s1+s4,23)+s1` for 256; family-specific constants);
- per-family jump constants shared by all scramblers.

Exported aliases: `Xoroshiro128p/ss/pp`, `Xoshiro256p/ss/pp`,
`Xoshiro512p/ss/pp` plus matching `*Gen` stream generators.

All nine variants are regression-tested against byte-exact outputs produced by
the original C implementations compiled with gcc (sequences, short jumps and
long jumps).

### Arbitrary forward/backward jumps

Because the transition is multiplication by x in GF(2)[x]/p(x) — with p the
family's characteristic polynomial, as published in Vigna's reference files —
one can jump any distance n in constant time by applying the polynomial
`x^n mod p` through the same accumulate-and-step loop as the fixed jumps.
Backward distances use the multiplicative order of x: `x^(-n) = x^(2^deg-1-n)`
(deg = 64N). RDST.jl implements a small GF(2) polynomial engine
(`_poly_mul_mod`, `_poly_pow_x`, BigInt exponents reduced modulo the period)
and exposes it as `advance_state!(rng, e, c)` with the exact distance
convention of MRG32k3a. Correctness is property-tested: fixed jumps coincide
with `short_jump!`, round trips (+k then -k) restore the state bit-for-bit,
and backward-jumped generators re-emit previously seen values.

### State representation

The state lives in `NTuple{4,UInt64}` fields. Immutable tuples let the JIT keep
the whole working set in registers inside `next`, eliminating bounds checks and
heap traffic that a `Vector{UInt64}` representation incurs. Measured
throughput: ≈ 10⁹ draws/s on a single core.

## Integer outputs of MRG32k3a

MRG32k3a natively yields ~31 bits per draw (the difference `p1 − p2`). Wider
unsigned types are assembled from 16-bit chunks of that value; narrower types
are truncations. Consequence: these integers are *not* uniform over their full
width — fine for indexing/shuffling/flags in simulations, not for cryptographic
use.

## Testing strategy

Reference sequences were captured from the reference implementations
(L'Ecuyer's C code semantics for MRG32k3a; Vigna's constants for the xoshiro
jumps) and regression-checked after optimization: identical outputs are
produced for every supported type, plus reset/jump/state round-trips.

## Performance snapshot

Single core, Julia 1.12 (indicative):

| Operation | Throughput |
|---|---|
| `rand(::MRG32k3a)` | ≈ 200 × 10⁶/s |
| `rand(::Xoroshiro128p)` | ≈ 1200 × 10⁶/s |
| `rand(::Xoshiro256p/ss/pp)` | ≈ 1340 × 10⁶/s |
| `rand(::Xoshiro512p/ss/pp)` | ≈ 1150 × 10⁶/s |
| `short_jump!` / `long_jump!` | 0 allocations |
