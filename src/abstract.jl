"""
`AbstractRNGStream` is an abstraction for creating RNG objects with non-overlaping random numbers.
"""
abstract type AbstractRNGStream end
"""
`AbstractStreamableRNG` is a special kind of RNG where one can move between different stream of number that are known to be non-overlapping.

Every concrete subtype implements the same interface, so that code written
against `AbstractStreamableRNG` works with any generator of the package:

| operation | meaning |
|---|---|
| `next_substream!(rng)` | move to the start of the next substream |
| `reset_substream!(rng)` | rewind to the start of the current substream |
| `reset_stream!(rng)` | rewind to the start of the current stream |
| `advance_state!(rng, e, c)` | move by `n` draws, `n` given by `(e, c)`; `n < 0` moves backwards |
| `get_state(rng)` | current position, in a generator-specific representation |
| `set_state!(rng, state)` | restore a position obtained from `get_state` |
| `srand!(rng, seed)` | reseed, resetting the stream and substream boundaries |

The unit of `advance_state!` is one `rand(rng)` draw, for every generator, so
that a jump written against `AbstractStreamableRNG` means the same thing
everywhere.
`get_state` and `set_state!` are inverses — `set_state!(rng, get_state(rng))`
leaves `rng` unchanged — and they move only the current position, never the
stream or substream boundaries. The representation returned by `get_state`
differs between families, so generic code should treat it as opaque and only
ever hand it back to `set_state!`.

Streams themselves are produced by an [`AbstractRNGStream`](@ref) object:
`next_stream!(gen)` returns the next non-overlapping stream.
"""
abstract type AbstractStreamableRNG <: AbstractRNG end # object of subtype of AbstractStreamableRNG are StreamableRNG