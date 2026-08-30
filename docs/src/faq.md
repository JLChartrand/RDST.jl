# FAQ

## Why is an all-zero state forbidden?

For the xoshiro/xoroshiro families the all-zero state maps to itself: the
generator would output only zeros forever. MRG32k3a's two components have the
same degeneracy (an all-zero component stays zero). Constructors and
`checkseed` reject such seeds; `Random.seed!(rng, ::Integer)` never produces
one.

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

## How do I run truly parallel simulations?

Never share one generator object across tasks/workers. Give each worker its
own stream *starting seed* (see [Streams & Substreams](streams.md)); streams
produced by successive `next_stream!` calls are guaranteed non-overlapping.

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

## Does this package run on the GPU?

No. It assigns and navigates streams on the host. The counter-based bijections
are pure functions of `(counter, key)`, so a device kernel can reproduce any
draw the host assigned it from that pair alone; the generator objects
themselves stay on the CPU. See [Streams & Substreams](streams.md).
