# Comparing generators: xoshiro variants vs MRG32k3a

RandomDataStreams.jl lets you pick between two very different generator designs. This page
helps you choose.

## Side-by-side

| Property | MRG32k3a | Xoroshiro128* (p/ss/pp) | Xoshiro256* (p/ss/pp) | Xoshiro512* (p/ss/pp) |
|---|---|---|---|---|
| State (bits) | 192 (6 × Int64) | 128 | 256 | 512 |
| Period | ≈ 2^191 | 2^128 − 1 | 2^256 − 1 | 2^512 − 1 |
| Native output | `Float64` [0,1), ~32-bit resolution | `UInt64` | `UInt64` | `UInt64` |
| Throughput (this package, single core) | ≈ 200 M/s | ≈ 1200 M/s | ≈ 1340 M/s | ≈ 1150 M/s |
| Stream mechanism | matrix power A^2^127 on the seed | `long_jump!` polynomial (2^96) | `long_jump!` (2^192) | `long_jump!` (2^384) |
| Substream mechanism | matrix power A^2^76 | `short_jump!` (2^64) | `short_jump!` (2^128) | `short_jump!` (2^256) |
| Backward jumps | yes (`advance_state!`) | yes (`advance_state!`, GF(2) polynomials) | yes (`advance_state!`) | yes (`advance_state!`) |
| Arbitrary-jump cost | O(e) matrix products | O(deg²) GF(2) ops (~10–500 ms) | same | same |
| Equidistribution | well analysed theory | 1-dim (**/++) / 0-dim (+) | 3-dim (**/++) / 2-dim (+) | 7-dim (**/++) / 6-dim (+) |
| BigCrush (Vigna's shootout) | passes | passes | passes | passes |
| Parallelism scale advised | large | mild (≈ 2^32 streams) | very large | extreme |

(`*` means any of the `+`, `**`, `++` scramblers.)

## When to choose MRG32k3a

- You need **provably non-overlapping streams with published, peer-reviewed
  parameters** (L'Ecuyer et al. 2002), e.g. to stay compatible with simulation
  libraries built on that model (SSJ, Simio, Arena-style stream ids...).
- Your application consumes **floats only**: MRG32k3a emits them natively.
- You can afford ~6x slower generation.

Note: backward jumping is *no longer* a differentiator — every RandomDataStreams generator
supports `advance_state!(rng, e, c)` with negative distances.

## When to choose a xoshiro/xoroshiro variant

- You want **maximum throughput** (all are ≈ 6–7x faster than MRG32k3a here)
  or raw 64-bit integers.
- Choose your state size by parallelism needs:
  - `Xoroshiro128*`: embedded/GPU or few workers only — its 2^64 substreams
    per 2^32 streams are enough for mild parallelism. Note `Xoroshiro128p`
    has a mild Hamming-weight dependency after ~5 TB of output; prefer
    `ss`/`pp`.
  - `Xoshiro256*`: the sweet spot for general use (Julia itself uses
    xoshiro256++ as its default RNG). Use `+` if you generate *only*
    floating-point numbers from the high bits (~15% faster historically);
    otherwise prefer `++`/`**`, whose outputs are fully equidistributed.
  - `Xoshiro512*`: essentially never needed for period reasons — any period
    ≥ 2^256 is beyond every imaginable need — but handy when you want many
    more independent substreams than 2^128 without changing design.

## Scrambler choice within a family

| Scrambler | Output | Best for |
|---|---|---|
| `+`  | sum of two state words | float-only workloads using the top bits; lowest 3 bits have low linear complexity |
| `**` | `rotl(s2·5, 7)·9` | all-purpose; maximal equidistribution (e.g. .NET/Lua default) |
| `++` | `rotl(s1+s4, k)+s1` | all-purpose; Rust's `SmallRng`, Julia's default |

All three share the same transition and therefore the same jump constants:
streams/substreams behave identically across scramblers of one family.

## Practical notes

- Seeding: seed states must not be all-zero. For hash-like seeds, initialize
  with splitmix64 outputs (see Vigna's recommendation).
- The package's jumps are **anchored at stream boundaries** (`Cg ← Bg ← Ig`),
  matching the L'Ecuyer stream model: `next_substream!` always lands at the
  same place regardless of how far you consumed in the current substream,
  which makes scenario replay reproducible.
