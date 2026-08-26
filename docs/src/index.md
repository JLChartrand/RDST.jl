# RandomDataStreams.jl Documentation

Streamable pseudo-random number generators for Julia:
MRG32k3a (L'Ecuyer) and xoshiro256+ (Blackman & Vigna), with
non-overlapping streams and substreams.

## Contents

1. [Getting Started](getting_started.md)
2. [Streams & Substreams](streams.md)
3. [API Reference](api.md)
4. [Implementation Notes](implementation.md)
5. [Generator Comparison](comparison.md)

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
