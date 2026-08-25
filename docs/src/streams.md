# Streams & Substreams

The central abstraction of RDST.jl is the *stream*: a long, non-overlapping
subsequence of a generator's period. Streams can themselves be split into
*substreams*. This is the architecture recommended by L'Ecuyer et al. (2002)
for parallel and replicated stochastic simulation:

- **Streams** are handed to independent replications or parallel workers;
  their outputs never overlap, so replications are statistically independent.
- **Substreams** delimit scenarios *within* one replication; rewinding a
  substream while keeping the scenario structure enables techniques such as
  common random numbers.

## The two object families

1. **Stream generators** (`<: AbstractRNGStream`) hold the seed of the
   *next* stream to be produced:
   - `MRG32k3aGen`
   - `Xoshiro256plusGen`
2. **RNGs** (`<: AbstractStreamableRNG`) actually produce numbers and can move
   along streams/substreams:
   - `MRG32k3a`
   - `Xoshiro256p`

## Producing independent streams

```julia
using RDST

gen = MRG32k3aGen()             # or Xoshiro256plusGen(UInt64[...])

worker1 = next_stream!(gen)       # stream 1
worker2 = next_stream!(gen)       # stream 2 — guaranteed disjoint from stream 1
worker3 = next_stream!(gen)       # stream 3 — ...
```

Each call to `next_stream!` advances the generator's internal seed by a huge
leap (2^127 values for MRG32k3a, a full `long_jump!` for Xoshiro256+), which is
what guarantees non-overlap.

```julia
# Typical parallel loop
using Distributed
gen = MRG32k3aGen()
@distributed (+) for _ in 1:nworkers()
    rng = next_stream!(gen)      # note: ship seeds explicitly in real code,
    sum(rand(rng) for _ in 1:10^6)
end
```

## Navigating substreams

Within a single RNG, three functions move along the stream/substream
hierarchy (all return the modified RNG):

| Function | Effect |
|---|---|
| `reset_stream!(rng)` | jump to the very beginning of the current stream |
| `reset_substream!(rng)` | jump to the beginning of the current substream |
| `next_substream!(rng)` | advance to the next substream |

Example — common random numbers across two scenarios:

```julia
rng = next_stream!(MRG32k3aGen())

rand(rng)                 # consume some variates of substream 1...
rand(rng)

next_substream!(rng)      # switch to substream 2 for scenario B
uB = rand(rng)

reset_stream!(rng)        # replay substream 1 from scratch for scenario A
uA = rand(rng)            # same underlying uniforms as the first draw
```

For Xoshiro256+, `next_substream!` is implemented as a `short_jump!`
(2^96-value leap) and `reset_stream!`/`next_substream!` manipulate the saved
`Bg`/`Ig` checkpoints.

## Saving, restoring, jumping

```julia
state = get_state(rng)     # a copy; safe to store
# ... consume numbers ...
```

To restore an MRG32k3a state, rebuild the generator with the triple
constructor (`Cg`, `Bg`, `Ig` all set to the snapshot):

```julia
snapshot = get_state(rng)
xs = [rand(rng) for _ in 1:5]
clone = MRG32k3a(snapshot, snapshot, snapshot)
rand(clone) == xs[1]       # true — resumes exactly after the snapshot
```

MRG32k3a additionally supports arbitrary jumps inside a stream:

```julia
advance_state!(rng, e, c)
```

moves the state forward by `n` steps, where `n = 2^e + c` (`e` may be negative,
and negative `c` moves backwards). This costs O(log n) matrix operations,
independent of the distance jumped.

## Guarantees

- Streams produced by successive calls to `next_stream!` on the same generator
  object are **provably non-overlapping**.
- Substreams likewise partition a stream into disjoint blocks
  (length ≈ 2^76 steps for MRG32k3a).
