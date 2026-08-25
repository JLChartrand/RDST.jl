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

## Why doesn't `sample(v, k)` work with RDST generators?

`sample` comes from StatsBase.jl, not from the Random standard library — even
Julia's own RNGs do not provide it without that package. Everything in
Random.jl works with RDST generators.

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
general use, `MRG32k3a` for L'Ecuyer-compatible stream semantics.
