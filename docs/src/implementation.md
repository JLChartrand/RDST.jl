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

### Modular arithmetic without overflow, and without tests

The recurrence follows Vigna's testless formulation
(<https://github.com/vigna/MRG32k3a>). The two negative coefficients are
carried as positive numbers and subtracted, and a multiple of the modulus is
added, so the argument of `%` can never be negative and the residual needs no
correction afterwards; the combination `z = p1 - p2 mod m1` is done with an
arithmetic shift rather than a comparison. Worth about 15% here — 204 million
`Float64` per second before, 230 to 235 after depending on the run — and the
stream is unchanged bit for bit.

It is worth 15% and not the factor of two Vigna reports, because most of what
he removes by hand LLVM already removes for us: the previous formulation, with
its two residual corrections and its comparison, compiled to 72 instructions
with **no branch and no division** — the corrections had become conditional
moves and the constant moduli multiply-shift sequences. What is left to gain is
the fix-up a *signed* remainder needs, which disappears once the dividend is
known non-negative: 72 instructions become 68.

Two variants measured and rejected: keeping the state in six scalar fields
instead of a `Vector{Int64}` is *slower* (226 against 235) while breaking the
constructors and `Cg`; and computing the output from the current state before
the update, which needs the state kept one step ahead to preserve the stream,
gives 231 and changes what `get_state` and the jump matrices operate on.

### Modular arithmetic in the jump machinery

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
the 256 bits of each jump constant. RandomDataStreams.jl hoists the jump constants into
compile-time tuples and evaluates jumps allocation-free on immutable state
tuples.

RandomDataStreams semantics differ subtly from the reference C code: jumps are **anchored**
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
(deg = 64N). RandomDataStreams.jl implements a small GF(2) polynomial engine
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

## Counter-based generators

`CBRNG{B,W,N,K}` holds what every counter-based family shares — the counter,
the key, the block most recently produced and the index of the next word in it.
This is the state `(k, i, j)` of L'Ecuyer et al. (2021, Sec. 3), with
`f(k, i, j) = (k, i + I[j = d-1], (j + 1) mod d)` and `d = N`. A variant only
supplies `bijection(::Val{B}, ctr, key)`.

Two families are built on it. **Philox** keeps both halves of a fixed-constant
multiplication and xors the high halves into the other words, with a Weyl
sequence for the round key. **Threefry** is a reduction of the Threefish cipher
used in Skein and contains no multiplication at all — add, rotate, xor only —
so it is reproducible bit-for-bit on any architecture, including ones with no
fast integer multiply. Adding it required only its bijection and its aliases,
no stream machinery.

Its rounds are unrolled at compile time with a generated function. Each round
uses a different pair of Skein rotation constants, so a plain loop indexes the
constant table with a value LLVM cannot fold; unrolling is worth a factor of
5.8 on the bijection (7.7 → 44.8 Mblocks/s), which is the difference between
Threefry being unusable and being in the same class as Philox. The round count
is a parameter of the bijection, not of the type, so the faster 13-round
variant is three lines of user code.

**Streams** are keys. **Substreams** partition the counter, following the same
paper: "one can use the `c0 < c` most significant bits of the counter to
determine the substream, and the remaining `c1 = c - c0` bits for the position
within the substream". `_substream_shift` splits the counter in half, so
Philox4x32-10 has 2^64 substreams of 2^64 blocks each.

**Key schedules.** `CBGen` walks the seeds `0, 1, 2, ...` and maps each through
`stream_key`, a bijection that defaults to the identity. Consecutive small keys
are safe for Philox — the ten rounds of encoding absorb the structure, as
reported by Salmon et al. (2011) and discussed in L'Ecuyer et al. (2021,
Sec. 3) — but they are *not* safe for every counter-based construction, so a
family whose bijection is weak for structured keys must override `stream_key`
with a schedule that hashes the seed.

## Integer outputs of MRG32k3a

MRG32k3a returns `z = (x1 - x2) mod m1` with `m1 = 2^32 - 209`, prime, scaled to
`u = z / (m1 + 1)`. Its native output is a uniform integer over a range that is
**not** a power of two, carrying `log2(m1) = 32.0` bits. This is why the
reference literature — L'Ecuyer (1999), and the RNGStreams package of L'Ecuyer,
Simard, Chen & Kelton (2002) whose stream API this package follows — exposes
only `RandU01()` and `RandInt(i, j) = i + floor((j - i + 1) * RandU01())`, and
no native-word or raw-bit primitive: no exact uniform word comes out of one
draw without rejection.

Machine integers are therefore an extension beyond what that literature
specifies and validates, and they are built here by assembling 16-bit chunks of
`z`, one MRG step per chunk — four steps for a `UInt64`. Truncating `z` to 16
bits carries a relative bias of `2^-16`, since `2^16` does not divide `m1`;
taking the low bits is sound because the modulus is prime, so there is no
low-bit weakness of the kind a power-of-two LCG has.

The cheaper alternative — assembling a word from the mantissas of two `[1, 2)`
draws, two steps instead of four — was implemented here and removed. It assumes
52 random bits per double, and MRG32k3a supplies 32; the low mantissa bits are
a near-deterministic function of the high ones. The result passed every
`U(0,1)` battery and failed SmallCrush on its own bit stream with six p-values
at zero, bit 12 coming out set in two draws out of three. `test/test_bits.jl`
is the regression net.

Narrower types are truncations of one chunk. None of these integers is exactly
uniform over its full width — fine for indexing, shuffling and flags in a
simulation, not for cryptographic use.

## Testing strategy

Reference sequences were captured from the reference implementations
(L'Ecuyer's C code semantics for MRG32k3a; Vigna's constants for the xoshiro
jumps) and regression-checked after optimization: identical outputs are
produced for every supported type, plus reset/jump/state round-trips.

## Performance snapshot

Reproduce with `julia -O3 scripts/benchmarks/throughput.jl`, which prints the
Julia version and CPU it ran on. Figures below are one run on a Skylake x86_64,
Julia 1.12.5, single core; treat them as ratios and re-run on the machine that
matters to you.

**The measurement method is part of the result.** Naive loops disagree by
nearly a factor of two, so the script fixes one method and states it:
BenchmarkTools with the minimum sample; scalar draws accumulated with `xor` on
the raw bits, because a floating-point `+` chain has four cycles of latency —
longer than a draw from the fastest generators here, so it would measure the
adder; nothing written to memory in the scalar loop, because storing every draw
turns the benchmark into one of memory bandwidth (the same xoshiro reads
867 M/s with an accumulator and 481 M/s storing into an 8 MB vector); and
`rand!` measured into a 4096-element vector, small enough to stay in cache.

Scalar draws: millions per second, and nanoseconds per draw. Every generator
the package ships is listed, each scrambler variant separately. Run-to-run
variation is a few percent, so read differences below that as noise.

| Generator | `Float64` | ns | `UInt64` | ns | `UInt32` | ns |
|---|---|---|---|---|---|---|
| `MRG32k3a` | 230 | 4.36 | 46 | 21.73 | 92 | 10.82 |
| `Xoroshiro128p` | 690 | 1.45 | 917 | 1.09 | 1062 | 0.94 |
| `Xoroshiro128ss` | 653 | 1.53 | 854 | 1.17 | 827 | 1.21 |
| `Xoroshiro128pp` | 597 | 1.67 | 817 | 1.22 | 903 | 1.11 |
| `Xoshiro256p` | 768 | 1.30 | 1139 | 0.88 | 1191 | 0.84 |
| `Xoshiro256ss` | 697 | 1.43 | 1057 | 0.95 | 910 | 1.10 |
| `Xoshiro256pp` | 670 | 1.49 | 1006 | 0.99 | 1028 | 0.97 |
| `Xoshiro512p` | 556 | 1.80 | 778 | 1.29 | 724 | 1.38 |
| `Xoshiro512ss` | 523 | 1.91 | 742 | 1.35 | 599 | 1.67 |
| `Xoshiro512pp` | 519 | 1.93 | 707 | 1.41 | 707 | 1.42 |
| `Philox4x32-10` | 91 | 11.03 | 106 | 9.44 | 272 | 3.68 |
| `Philox4x64-10` | 208 | 4.81 | 272 | 3.67 | 258 | 3.88 |
| `Threefry4x32-20` | 82 | 12.18 | 90 | 11.08 | 178 | 5.62 |
| `Threefry4x64-20` | 145 | 6.90 | 150 | 6.68 | 150 | 6.66 |

Array fill with `rand!`, millions of elements per second (nanoseconds per
element is `1000` over the figure):

| Generator | `Float64` | `UInt64` | `UInt32` |
|---|---|---|---|
| `MRG32k3a` | 162 | 47 | 92 |
| `Xoroshiro128p` | 540 | 578 | 562 |
| `Xoroshiro128ss` | 516 | 529 | 509 |
| `Xoroshiro128pp` | 488 | 498 | 499 |
| `Xoshiro256p` | 488 | 507 | 508 |
| `Xoshiro256ss` | 483 | 516 | 466 |
| `Xoshiro256pp` | 459 | 499 | 500 |
| `Xoshiro512p` | 369 | 387 | 415 |
| `Xoshiro512ss` | 366 | 385 | 378 |
| `Xoshiro512pp` | 366 | 382 | 398 |
| `Philox4x32-10` | 154 | 172 | 340 |
| `Philox4x64-10` | 351 | 352 | 261 |
| `Threefry4x32-20` | 98 | 105 | 200 |
| `Threefry4x64-20` | 207 | 177 | 150 |

What the tables say. Within each xoshiro family the ordering is the same and
the spread is small: `+` is fastest, then `**`, then `++`, within about 15% of
each other — the scrambler is a couple of instructions on top of a shared
transition. Across families, state size costs: 128 and 256 bits are close,
512 bits is a third slower. The counter-based generators sit an order of
magnitude below on `Float64`, which is what buying a keyed bijection per block
costs, and the two 32-bit ciphers are fastest in `UInt32`, where a draw is one
cipher word rather than two.

The one outlier is `MRG32k3a` in `UInt64`, at 21.7 ns against 4.4 ns for its
`Float64`: a 64-bit word costs four MRG steps, because the modulus is not a
power of two and the word is assembled from 16-bit chunks. See the section on
its integer outputs.

The counter-based generators are the ones that gain from filling an array:
`rand!` produces whole blocks straight into it, so the counter, the block
buffer and the index are touched once per block instead of once per draw.
Philox4x64-10 goes from 208 to 351 million `Float64` per second, a factor of
1.7. The recurrence-based generators have no such block to exploit and are
*slower* in bulk than in the accumulator loop, by the cost of the stores.

Two combinations get no block path and fall back to the scalar loop: `UInt32`
from a 64-bit family, and any 64-bit draw taken while the generator sits
mid-block because the caller has been mixing widths.

Every generator draws with zero allocations, in both paths, as do `short_jump!`
and `long_jump!`.
