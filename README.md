# RandomDataStreams.jl

[![CI](https://github.com/JLChartrand/RandomDataStreams.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JLChartrand/RandomDataStreams.jl/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://jlchartrand.github.io/RandomDataStreams.jl/dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)

**Streamable pseudo-random number generators for Julia.**

RandomDataStreams (Random Data Streams) provides random number generators (RNGs) that support
**non-overlapping streams and substreams**, in the sense of L'Ecuyer et al. (2002).
This is a key requirement for stochastic simulation, parallel Monte Carlo, and
reproducible variance-reduction techniques such as common random numbers.

Two generator families are provided:

| Family | Variants | Period | Native output | Streams / substreams |
|-------------|---------------|------|----------------------|----------------|
| **MRG32k3a** | `MRG32k3a` | ≈ 2^191 | `Float64` | matrix jumps (L'Ecuyer) |
| **xoshiro/xoroshiro** | `Xoroshiro128p/ss/pp`, `Xoshiro256p/ss/pp`, `Xoshiro512p/ss/pp` | 2^128 – 2^512 | `UInt64` | Vigna's jump polynomials |

All xoshiro/xoroshiro variants are validated byte-for-byte against the
original C implementations from [xoshiro.di.unimi.it](http://xoshiro.di.unimi.it).
See the [documentation](docs/) for a detailed comparison with MRG32k3a.

## Features

- **Multiple independent streams**: obtain guaranteed non-overlapping sequences
  with `next_stream!(gen)` — ideal for parallel workers or replicated experiments.
- **Substreams** within each stream (`reset_substream!`, `next_substream!`),
  enabling common random numbers across scenarios — for *every* generator.
- **Full state control**: save/restore a generator with `get_state`,
  rewind with `reset_stream!`, and jump to any position — forward *or
  backward* — with `advance_state!(rng, e, c)` on **every** generator.
- **Standard `Random` API integration**: full drop-in substitutability with
  Julia's built-in RNGs — `rand`/`rand!` on scalars, arrays and ranges,
  `randn`, `randexp`, `shuffle`, `randperm`, `randsubseq`, `Random.seed!(rng,
  seed)` all work with every generator (details per generator in the docs).
- **Zero-allocation hot paths**: all generators produce numbers without heap
  allocation.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/JLChartrand/RandomDataStreams.jl.git")
```

Requires Julia ≥ 1.6. The only dependency is the Julia standard library `Random`.

## Quick start

### MRG32k3a

```julia
using RandomDataStreams

gen = MRG32k3aGen()          # stream generator (manages non-overlapping seeds)
rng = next_stream!(gen)       # a fresh, independent stream

rand(rng)                    # Float64 in [0, 1)
rand(rng, UInt64)            # raw 64-bit unsigned integer
rand(rng, Int32)
rand(rng, 1:10)              # not yet implemented for MRG32k3a; use Xoshiro256p
```

### Xoshiro256+

```julia
using RandomDataStreams

gen = Xoshiro256plusGen([0x01, 0x02, 0x03, 0x04])
rng = next_stream!(gen)

rand(rng)                    # Float64 in [0, 1)
rand(rng, 1:100)             # uniformly distributed Int64 in the range
```

### Streams and substreams

```julia
gen  = MRG32k3aGen()
rng1 = next_stream!(gen)     # stream 1
rng2 = next_stream!(gen)     # stream 2 — provably non-overlapping with stream 1

# Substreams inside rng1
u0 = rand(rng1)
next_substream!(rng1)        # move to the next substream
reset_substream!(rng1)       # back to the start of the current substream
reset_stream!(rng1)          # back to the very beginning of the stream
@assert rand(rng1) == u0
```

### Drop-in use with Julia's standard RNG API

```julia
using RandomDataStreams, Random

rng = next_stream!(MRG32k3aGen())   # any RandomDataStreams generator works as an AbstractRNG

rand(rng, 5)                        # Vector{Float64}
A = rand(rng, Float64, 2, 3)        # matrix
z = randn(rng)                      # standard normal
v = shuffle(rng, collect(1:8))
p = randperm(rng, 6)
buf = zeros(3); rand!(rng, buf)

Random.seed!(rng, 42)               # standard seeding, reproducible runs
```

### Saving and restoring state

```julia
rng = next_stream!(MRG32k3aGen())
state = get_state(rng)               # copy of the current state
xs = [rand(rng) for _ in 1:5]
rng2 = MRG32k3a(state, state, state) # restore into a new generator
@assert rand(rng2) == xs[1]          # continues exactly where the snapshot was taken
```

### Jumping within a stream (MRG32k3a)

```julia
rng = MRG32k3a()
advance_state!(rng, e, c)    # jumps n steps where n = 2^e + c (c may be negative)
```

## Documentation

Full documentation lives in [`docs/`](docs/) and as a PDF in
[`docs/RandomDataStreams.pdf`](docs/build/RandomDataStreams.pdf):

- [Getting started](docs/src/getting_started.md)
- [Streams & substreams](docs/src/streams.md)
- [API reference](docs/src/api.md)
- [Implementation notes](docs/src/implementation.md)

## References

- P. L'Ecuyer, R. Simard, E. J. Chen, W. D. Kelton (2002).
  *An Object-Oriented Random-Number Package with Many Long Streams and
  Substreams*. Operations Research 50(6), 1073–1075.
- Blackman, D., Vigna, S. (2019). *Scrambled Linear Pseudorandom Number
  Generators* (xoshiro256+).

## License

MIT — see [LICENSE.md](LICENSE.md).
