# FAQ

## Why is an all-zero state forbidden?

For the xoshiro/xoroshiro families the all-zero state maps to itself: the
generator would output only zeros forever. MRG32k3a's two components have the
same degeneracy (an all-zero component stays zero). Constructors, `srand!`,
`set_state!` and `Random.seed!` all reject such a seed with an
`ArgumentError`, and `checkseed` is the predicate they use, so you can test a
seed yourself before handing it over. An integer seed never produces one.
PCG and the counter-based generators have no invalid seed at all.

## Are MRG32k3a integer outputs uniform over their full width?

No. MRG32k3a natively produces ~31 bits per draw (`p1 - p2`); wider integers
are assembled from 16-bit chunks of that value. They are fine for indices,
shuffling, flags and acceptance tests in simulations — not uniform over
2^64/2^128. Use a xoshiro variant when you need full-width raw words.

## Why doesn't `sample(v, k)` work with RandomDataStreams generators?

`sample` comes from StatsBase.jl, not from the Random standard library — even
Julia's own RNGs do not provide it without that package. Everything in
Random.jl works with RandomDataStreams generators.

## Where did `srand`, `next_stream`, `short_jump`, `long_jump` go?

They mutated their argument despite not ending in `!`; they are deprecated in
favour of:

| Deprecated | Replacement |
|---|---|
| `srand(rng/gen, seed)` | `srand!(rng/gen, seed)` |
| `next_stream(gen)` | `next_stream!(gen)` |
| `short_jump(rng)` | `short_jump!(rng)` |
| `long_jump(rng)` | `long_jump!(rng)` |

The old names still work but emit a deprecation warning.

## What does an integer seed mean?

The same thing for every generator: it is expanded through splitmix64 and
folded into whatever that family accepts as a state or key, so `T(12345)`,
`Gen(12345)` and `Random.seed!(T(), 12345)` all agree. A value in the family's
own representation — its seed vector, or a `UInt128` for PCG — is taken as the
state itself rather than hashed. See
[Streams & Substreams](streams.md) for the full table.

## How do I run truly parallel simulations?

Take the streams first, then parallelise over them:
`rngs = next_stream!(gen, nthreads())`. Streams share no state, so one per
thread needs no synchronisation.

Never call `next_stream!` on a shared generator object from inside a parallel
loop. The generator rewrites the seed of the next stream on every call, so
concurrent calls hand out overlapping streams and nothing reports it. For
separate processes the seeds have to travel instead; both patterns are in
[Streams & Substreams](streams.md).

## Which generator should I pick?

See [Generator Comparison](comparison.md). Short answer: `Xoshiro256pp` for
general use, `MRG32k3a` for L'Ecuyer-compatible stream semantics,
`Philox4x64RNG` when a draw must be addressable by index rather than reached
by replaying a state.

## What does "counter-based" buy me?

A counter-based generator computes its output as a keyed bijection of a
counter, so the draw at position `i` of substream `j` of stream `s` is a
*function* of `(s, j, i)`. Nothing has to be replayed to reach it. That makes
three things easy that are awkward otherwise: handing a stream identifier to a
worker or a GPU kernel that has no generator object, jumping to an arbitrary
position in constant time, and re-running one replicate of one stream without
re-running anything else. The cost is speed: on scalar draws Philox and
Threefry are several times slower than xoshiro, though filling arrays with
`rand!` recovers much of the gap.

## Philox or Threefry?

`Philox4x64RNG` is the faster of the two here and the one other libraries ship
(Random123, cuRAND, TensorFlow, Intel MKL), so prefer it unless you have a
reason not to. `Threefry4x64RNG` uses only additions, rotations and xors — no
multiplication — which makes it a better fit for hardware without a fast wide
multiply, and easier to audit.

## Is it safe to use 1, 2, 3, ... as counter-based stream keys?

For Philox and Threefry, yes: ten (resp. twenty) rounds of encoding absorb the
structure of consecutive small keys, as reported by Salmon et al. (2011) and
discussed by L'Ecuyer et al. (2021, Sec. 3). This is *not* a property of
counter-based generators in general — for the Squares generator, the key 0
gives an identically zero output — so a new family whose bijection is weak for
structured keys must override `stream_key` with a schedule that hashes the
seed. See [Implementation Notes](implementation.md).

## Can I reproduce a NumPy pipeline?

Partly. `PCG64` here produces exactly the same raw 64-bit outputs as
`numpy.random.default_rng()`'s bit generator for the same 128-bit state, and
`PCG64DXSM` matches NumPy's `PCG64DXSM`. What does *not* transfer is how NumPy
gets to that state: `SeedSequence` turns a user seed into the state through its
own hashing, and that specification is not implemented here. So you can
reproduce a NumPy stream if you carry the state across, not if you carry only
the seed.

The distributions differ too. `rand(rng)` and `numpy`'s `random()` consume the
same bits but not necessarily in the same way, and `randn` uses a different
algorithm from NumPy's ziggurat. Only the raw generator output is guaranteed
to agree.

## Why can't I choose PCG's increment to get more streams?

Because it does not give independent streams. Every odd increment gives a
full-period orbit, but for half of all pairs of odd increments the two orbits
are the same state sequence shifted by a constant — an adversarial pair can be
built whose outputs differ by an average of 2 bits out of 64. Most pairs are
harmless, but no published criterion separates them, so the package fixes the
increment and derives streams from jumps instead. The algebra is in the
[Implementation Notes](implementation.md). NumPy takes the same practical
position: its recommended way to parallelise is `SeedSequence.spawn()`, not the
increment.

## Does this package run on the GPU?

No. It assigns and navigates streams on the host. The counter-based bijections
are pure functions of `(counter, key)`, so a device kernel can reproduce any
draw the host assigned it from that pair alone; the generator objects
themselves stay on the CPU. See [Streams & Substreams](streams.md).
