# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
