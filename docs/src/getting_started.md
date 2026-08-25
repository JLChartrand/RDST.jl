# Getting Started

RDST.jl provides pseudo-random number generators with support for
**non-overlapping streams and substreams**, following the stream/substream model
of L'Ecuyer et al. (2002).

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/wirelessroom2/RDST.jl")
```

or, from a local clone:

```julia
using Pkg
Pkg.develop(path = "path/to/RDST.jl")
```

Requirements: Julia ≥ 1.6. The only dependency is the standard library `Random`.

## Choosing a generator

RDST.jl implements the full xoshiro/xoroshiro family of Blackman & Vigna plus
L'Ecuyer's MRG32k3a. All variants of a xoshiro family share the same linear
transition and jump constants; only the output scrambler differs.

| Type | Family | State | Period | Scrambler |
|---|---|---|---|---|
| `Xoroshiro128p` | xoroshiro128 | 128 bits | 2^128 − 1 | `s0 + s1` |
| `Xoroshiro128ss` | xoroshiro128 | 128 bits | 2^128 − 1 | high bits, `**` |
| `Xoroshiro128pp` | xoroshiro128 | 128 bits | 2^128 − 1 | high bits, `++` |
| `Xoshiro256p` | xoshiro256 | 256 bits | 2^256 − 1 | `s0 + s3` |
| `Xoshiro256ss` | xoshiro256 | 256 bits | 2^256 − 1 | high bits, `**` |
| `Xoshiro256pp` | xoshiro256 | 256 bits | 2^256 − 1 | high bits, `++` |
| `Xoshiro512p` | xoshiro512 | 512 bits | 2^512 − 1 | `s0 + s2` |
| `Xoshiro512ss` | xoshiro512 | 512 bits | 2^512 − 1 | high bits, `**` |
| `Xoshiro512pp` | xoshiro512 | 512 bits | 2^512 − 1 | high bits, `++` |
| `MRG32k3a` | combined MRG (L'Ecuyer) | 192 bits | ≈ 2^191 | native `Float64` |

See [Generator Comparison](comparison.md) for guidance and benchmarks.

## First numbers

```julia
using RDST

rng = MRG32k3a()      # default seed [12345, ..., 12345]
rand(rng)             # 0.12701112204657714
rand(rng)             # 0.3185275653967945
```

```julia
x = Xoshiro256p(UInt64[1, 2, 3, 4])
rand(x)               # Float64 in [0, 1)
```

## Supported output types

### MRG32k3a

- `Float64` (native), plus `Float32`, `Float16` via conversion
- `UInt8`, `UInt16`, `UInt32`, `UInt64`, `UInt128`
- `Int8`, `Int16`, `Int32`, `Int64`, `Int128` (same bit patterns)
- `Bool`
- Ranges: `rand(rng, 1:10)` works through the standard `Random` machinery

Note: integer outputs of MRG32k3a are built from its native ~31-bit resolution;
they are not uniform over their full width. Use them for indices, choices and
flags rather than cryptography.

### Xoshiro256p

- `Float64` (native path), `Float32`, `Float16`
- `UInt64`
- Ranges: `rand(rng, r::UnitRange{Int64})`

## Reproducibility

Every generator accepts an explicit seed:

```julia
rng = MRG32k3a([42, 1, 2, 3, 4, 5])
x    = Xoshiro256p(UInt64[0xdead, 0xbeef, 0xcafe, 0xbabe])
```

Seeds are validated by `checkseed`: a valid MRG32k3a seed has 6 non-negative
values; the first three must be < m1 and not all zero, the last three < m2 and
not all zero.

The standard Julia interface also works with every generator:

```julia
Random.seed!(rng, 42)          # integer seed (splitmix64 expansion)
Random.seed!(rng, [7,7,7,8,8,8])   # explicit MRG32k3a seed (validated)
```

## Full Random API

RDST generators are drop-in substitutes for Julia's built-in RNGs: scalars
(all numeric types, `Bool`, `Char`), arrays (`rand(rng, n)`, `rand(rng, T,
dims...)`, `rand!`), ranges, `randn`, `randexp`, `shuffle`, `randperm`,
`randsubseq` and `Random.randstring` all work. Only `sample` requires
StatsBase.jl and is out of scope.

## Next steps

- [Streams & substreams](streams.md)
- [API reference](api.md)
- [Implementation notes](implementation.md)
