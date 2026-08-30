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

## PCG

`PCGRNG{V}` runs a linear congruential recurrence on 128 bits,
`s <- a*s + c (mod 2^128)`, and permutes the state into 64 bits of output. Two
variants ship: `PCG64` with the XSL-RR permutation, which is what
`numpy.random.default_rng()` returns, and `PCG64DXSM` with the DXSM
permutation and the cheap 64-bit multiplier, which NumPy recommends for
large-scale parallel work. They differ in one more detail that matters for
bit-exactness: PCG64 steps the state and permutes the result, DXSM permutes the
state and then steps it. Both are pinned by known-answer vectors taken from
NumPy.

**Jumps are closed-form.** For an LCG,

```
s_n = a^n * s_0 + c * (a^n - 1)/(a - 1)   (mod 2^128),
```

which Brown's (1994) doubling recurrence evaluates in `O(log n)`
multiplications. `advance_state!` therefore costs the same at any distance, and
a backward jump of `n` is the forward jump of `2^128 - n`, so it costs the same
as a forward one. This is the cheapest arbitrary jump in the package: the
xoshiro families pay `O(deg^2)` GF(2) operations for the same operation, tens
to hundreds of milliseconds, and MRG32k3a a sequence of matrix products.
**The jump distances are odd, and that is not cosmetic.** The obvious choice —
2^64 between substreams, 2^96 between streams, mirroring the xoroshiro128
layout — is wrong for a linear congruential recurrence. By the
lifting-the-exponent lemma,

```
v2(a^n - 1) = v2(a - 1) + v2(a + 1) + v2(n) - 1 = 2 + v2(n)   (n even),
```

so a jump of `2^m` produces a jump multiplier congruent to `1` modulo
`2^(m+2)`. With `m = 96`, the states of successive streams agree in their low
98 bits up to an arithmetic progression. Each stream still passes SmallCrush on
its own; interleaving 64 of them round-robin fails it outright, with 14 of 15
p-values at 0. The package's inter-stream battery found this, which is the
argument for having one.

An odd distance has `v2(n) = 0`, leaving the jump multiplier as far from the
identity as the multiplier itself. Substreams are therefore `2^64 + 1` apart
and streams `2^32 * (2^64 + 1) + 1`, which is still 2^32 streams of 2^32
substreams of 2^64 draws and still non-overlapping — the last substream of a
stream ends two values below the next stream's start. With those distances the
interleaved battery passes. Both the parity of the distances and the 2-adic
distance of the resulting jump multipliers are asserted in the test suite.

**The increment is fixed, and that is deliberate.** PCG has its own notion of a
stream: every odd increment `c` gives a full-period orbit, and NumPy exposes it
as part of the state. Those orbits are not known to be independent. Writing
`t_n = s_n + h` and matching the two recurrences gives

```
h * (a - 1) = c1 - c2,
```

which has a solution whenever `4` divides `c1 - c2` — the full-period condition
forces `a = 1 (mod 4)`, and `v2(a - 1) = 2` for the PCG multipliers. For half
of all pairs of odd increments, then, the two "independent streams" are the
same state sequence translated by a constant. Taking `c2 = c1 - (a - 1)` makes
that constant `1`, and the two output sequences then differ by a mean Hamming
distance of 2 bits out of 64, against 32 for unrelated sequences, with 94% of
draws differing in at most 4 bits.

That is an adversarial pair; most pairs of increments are far less structured
and would show nothing. The objection is not that every pair is bad but that no
criterion is published for telling the good pairs from the bad ones, which is
exactly what L'Ecuyer et al. (2021, Sec. 3) argue against — the same objection
they raise against Squares. So the package fixes the increment to the reference
value for every PCG stream and derives streams from jumps, whose non-overlap is
a statement about distances along one orbit. The algebra above is locked in the
test suite.

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
Julia version and CPU it ran on. On a hybrid CPU (Intel 12th generation and
later), pin the process first — `taskset -c 0 julia -O3 …` — and say which core
type was used: otherwise the scheduler moves the run between performance and
efficiency cores and the minimum reflects whichever was fastest. Figures below are one run on a Skylake x86_64,
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
| `MRG32k3a` | 236 | 4.25 | 47 | 21.20 | 95 | 10.55 |
| `Xoroshiro128p` | 695 | 1.44 | 941 | 1.06 | 1090 | 0.92 |
| `Xoroshiro128ss` | 655 | 1.53 | 876 | 1.14 | 848 | 1.18 |
| `Xoroshiro128pp` | 599 | 1.67 | 819 | 1.22 | 927 | 1.08 |
| `Xoshiro256p` | 788 | 1.27 | 1168 | 0.86 | 1221 | 0.82 |
| `Xoshiro256ss` | 715 | 1.40 | 1058 | 0.95 | 933 | 1.07 |
| `Xoshiro256pp` | 670 | 1.49 | 1006 | 0.99 | 1054 | 0.95 |
| `Xoshiro512p` | 570 | 1.75 | 798 | 1.25 | 742 | 1.35 |
| `Xoshiro512ss` | 523 | 1.91 | 742 | 1.35 | 614 | 1.63 |
| `Xoshiro512pp` | 532 | 1.88 | 725 | 1.38 | 709 | 1.41 |
| `PCG64` | 504 | 1.98 | 599 | 1.67 | 600 | 1.67 |
| `PCG64DXSM` | 561 | 1.78 | 743 | 1.35 | 743 | 1.35 |
| `Philox4x32-10` | 93 | 10.76 | 109 | 9.20 | 272 | 3.68 |
| `Philox4x64-10` | 210 | 4.76 | 273 | 3.66 | 265 | 3.77 |
| `Threefry4x32-20` | 84 | 11.89 | 92 | 10.89 | 186 | 5.39 |
| `Threefry4x64-20` | 147 | 6.81 | 153 | 6.52 | 154 | 6.50 |

Array fill with `rand!`, millions of elements per second (nanoseconds per
element is `1000` over the figure):

| Generator | `Float64` | `UInt64` | `UInt32` |
|---|---|---|---|
| `MRG32k3a` | 159 | 46 | 92 |
| `Xoroshiro128p` | 554 | 581 | 576 |
| `Xoroshiro128ss` | 542 | 543 | 519 |
| `Xoroshiro128pp` | 499 | 511 | 510 |
| `Xoshiro256p` | 501 | 519 | 520 |
| `Xoshiro256ss` | 496 | 519 | 475 |
| `Xoshiro256pp` | 471 | 505 | 512 |
| `Xoshiro512p` | 377 | 394 | 426 |
| `Xoshiro512ss` | 361 | 384 | 389 |
| `Xoshiro512pp` | 373 | 379 | 408 |
| `PCG64` | 574 | 622 | 621 |
| `PCG64DXSM` | 632 | 735 | 735 |
| `Philox4x32-10` | 157 | 178 | 347 |
| `Philox4x64-10` | 359 | 339 | 257 |
| `Threefry4x32-20` | 100 | 106 | 204 |
| `Threefry4x64-20` | 207 | 177 | 152 |

What the tables say. Within each xoshiro family the ordering is the same and
the spread is small: `+` is fastest, then `**`, then `++`, within about 15% of
each other — the scrambler is a couple of instructions on top of a shared
transition. Across families, state size costs: 128 and 256 bits are close,
512 bits is a third slower. The counter-based generators sit an order of
magnitude below on `Float64`, which is what buying a keyed bijection per block
costs, and the two 32-bit ciphers are fastest in `UInt32`, where a draw is one
cipher word rather than two.

The two PCG variants land between the xoshiro families and MRG32k3a, at
roughly two thirds of `Xoshiro256p`: a 128-bit multiply per draw is more work
than a handful of shifts and xors. `PCG64DXSM` is the faster of the two despite
its extra output multiply, because its "cheap" 64-bit multiplier turns the
128x128 state multiplication into a 64x128 one. Both are the fastest generators
in the package under `rand!`, ahead of every xoshiro: the whole state is one
128-bit word, so the bulk loop touches far less memory per element than a
four- or eight-word state does.

The one outlier is `MRG32k3a` in `UInt64`, at 21.2 ns against 4.3 ns for its
`Float64`: a 64-bit word costs four MRG steps, because the modulus is not a
power of two and the word is assembled from 16-bit chunks. See the section on
its integer outputs.

The counter-based generators are the ones that gain from filling an array:
`rand!` produces whole blocks straight into it, so the counter, the block
buffer and the index are touched once per block instead of once per draw.
Philox4x64-10 goes from 210 to 359 million `Float64` per second, a factor of
1.7. The recurrence-based generators have no such block to exploit and are
*slower* in bulk than in the accumulator loop, by the cost of the stores.

Two combinations get no block path and fall back to the scalar loop: `UInt32`
from a 64-bit family, and any 64-bit draw taken while the generator sits
mid-block because the caller has been mixing widths.

Every generator draws with zero allocations, in both paths, as do `short_jump!`
and `long_jump!`.
