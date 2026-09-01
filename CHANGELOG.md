# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **MRG63k3a** (L'Ecuyer 1999, Table II, fourth entry): `MRG63k3a` and
  `MRG63k3aGen`, the 64-bit-arithmetic member of the MRG32k3a family. Two
  moduli just under `2^63`, period ≈ `2^377`, and just under 63 random bits per
  step against 32 for MRG32k3a — so a `UInt64` costs two steps instead of four,
  and its 32-bit chunks depart from uniformity by `2^-31` rather than `2^-16`.
  Output matches L'Ecuyer's own C implementation value for value. The package
  was testing MRG32k3a's assembled 64-bit words without shipping the generator
  that has 64 bits to give; now it ships both.

  The stream and substream distances, `2^250` and `2^150`, are this package's
  choice: L'Ecuyer published jump matrices for MRG32k3a only. They are his
  `2^127` and `2^76` scaled by the ratio of the two periods, and the matrices
  are computed at precompilation rather than tabulated. `advance_state!`,
  `next_substream!`, `next_stream!`, `get_state`/`set_state!`, `srand!` and
  `Random.seed!` behave exactly as for MRG32k3a.

  The draw avoids a 128-bit remainder: both moduli are `2^63 - c` with `c`
  small, so the reduction is a shift, a multiply, an add and one conditional
  subtraction — a plain remainder is ten times slower, measured. All three of
  Vigna's optimizations for MRG32k3a are in place, including the one this
  package had measured and rejected for the 32-bit generator: keeping the state
  one step ahead so the output overlaps the next state is worth nothing there
  (236 against 235 M/s) and 7% here (196 against 183). The shift is hidden
  behind the API — `get_state` and `show` step back, the constructors and
  `Random.seed!` step forward, and the jump matrices commute with it, so
  streams, substreams and `advance_state!` are untouched.

  It joins every generator list in the suite: SmallCrush on one stream, on 64
  interleaved streams, and on the `UInt32` and `UInt64` bit paths; the threads
  suite; the uniform-interface matrix; the on-demand Crush/BigCrush harness; and
  `notebooks/streams_tour.ipynb`, which now also shows the two MRG word sizes
  side by side.

## [0.2.0]

Two new generator families, and one breaking change to seeding.

### Breaking

- **The all-zero state is now refused everywhere.** It is a fixed point of the
  xoshiro and xoroshiro transitions: a generator seeded with it emits zeros
  forever. Constructors, `srand!`, `set_state!` and `Random.seed!` now throw an
  `ArgumentError` instead of accepting it. The documentation already claimed
  this was rejected; the code did not do it. Code that seeded with an all-zero
  vector was producing constant output and will now fail loudly.

### Added

- **PCG** (O'Neill 2014): `PCG64` and `PCG64DXSM`, with `PCG64Gen` and
  `PCG64DXSMGen`. Raw 64-bit outputs match NumPy's, whose `default_rng()` is
  PCG64, for the same state. Streams and substreams use the closed-form LCG
  advance, so `advance_state!` costs `O(log n)` multiplications at any
  distance, forwards or backwards.
- **Counter-based generators** (Salmon et al. 2011): `PhiloxRNG` (4x32-10),
  `Philox4x64RNG`, `Threefry4x32RNG` and `Threefry4x64RNG`, with their
  generator objects, validated against the authors' test vectors. Streams are
  distinct keys rather than segments of one orbit, so any draw is addressable
  from `(key, substream, index)` without replaying anything.
- **A uniform seeding rule across every family.** Each generator now accepts an
  integer seed, expanded through splitmix64, and a raw seed in its own natural
  form. `MRG32k3a(12345)`, `Xoshiro256ppGen(12345)`, `PCG64(12345)` and
  `Philox4x64Gen(12345)` all work and mean the same thing.
- `set_state!` for `MRG32k3aGen`, and `srand!` for generator objects, closing
  gaps that made the interface non-uniform.
- `scripts/testu01/campaign.jl`: a resumable, parallel driver for the TestU01
  batteries, with a systemd unit for campaigns that outlive a login session.
- `scripts/benchmarks/throughput.jl`: a reproducible throughput benchmark that
  states its measurement method.
- Provenance in every result file: the commit, whether the tree was dirty, and
  the package version that produced each measurement.
- Documentation: a validation page, a generator comparison with a related-work
  section, an FAQ, and `notebooks/streams_tour.ipynb`, a runnable tour of the
  stream model across all four families.

### Fixed

- `advance_state!(rng::MRG32k3a, e, c)` returned the value of its last
  assignment instead of the generator, unlike every other family. It now
  returns `rng`.
- PCG streams used power-of-two jump distances, which for a linear congruential
  generator makes the jump multiplier congruent to 1 modulo a large power of
  two, leaving the streams correlated. Each stream passed SmallCrush alone
  while sixty-four interleaved failed with fourteen of fifteen p-values at
  zero. Stream and substream distances are now odd, `2^32(2^64+1)+1` and
  `2^64+1`. Found by the interleaved battery, which is in the test suite.

## 0.1.0

Initial release: `MRG32k3a` and the xoshiro/xoroshiro families, with the stream
and substream object model of L'Ecuyer et al. (2002). Registered without a git
tag, which is why there is no comparison link for it below.

[Unreleased]: https://github.com/JLChartrand/RandomDataStreams.jl/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/JLChartrand/RandomDataStreams.jl/releases/tag/v0.2.0
