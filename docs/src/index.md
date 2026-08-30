# RandomDataStreams.jl Documentation

Streamable pseudo-random number generators for Julia, with non-overlapping
streams and substreams:

- **MRG32k3a** (L'Ecuyer et al. 2002) — the reference combined MRG of the
  simulation literature;
- the **xoshiro / xoroshiro** families (Blackman & Vigna) — 128, 256 and
  512 bits of state, three scramblers each;
- the **counter-based** generators **Philox** and **Threefry** (Salmon et al.
  2011) — streams are keys, and any draw can be recomputed from its index.

All of them share one interface: the same stream and substream navigation, the
same state contract, and the full `Random` API.

## Contents

1. [Getting Started](getting_started.md)
2. [Streams & Substreams](streams.md)
3. [API Reference](api.md)
4. [Docstrings](docstrings.md)
5. [Implementation Notes](implementation.md)
6. [Validation](validation.md)
7. [Generator Comparison](comparison.md)
8. [FAQ](faq.md)

## Quick example

```julia
using RandomDataStreams

gen  = MRG32k3aGen()
rngA = next_stream!(gen)      # independent stream A
rngB = next_stream!(gen)      # independent stream B

rand(rngA)                   # Float64 in [0, 1)
next_substream!(rngA)        # move to the next substream of A
reset_stream!(rngA)          # rewind stream A to its beginning
```

The same code runs on any generator the package ships — only the first line
changes:

```julia
gen = Philox4x64Gen()        # or Xoshiro256plusGen(), Threefry4x64Gen(), ...
```
