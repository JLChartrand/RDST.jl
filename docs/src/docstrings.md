# Docstrings

Auto-generated documentation from the package docstrings.

## Abstract types

```@docs
AbstractRNGStream
AbstractStreamableRNG
```

## MRG32k3a

```@docs
MRG32k3a
MRG32k3aGen
checkseed
```

## Xoshiro / xoroshiro families

```@docs
RDST.LinRNG
Xoroshiro128p
Xoroshiro128ss
Xoroshiro128pp
Xoshiro256p
Xoshiro256ss
Xoshiro256pp
Xoshiro512p
Xoshiro512ss
Xoshiro512pp
```

### Stream generators

```@docs
RDST.LinGen
Xoroshiro128pGen
Xoroshiro128ssGen
Xoroshiro128ppGen
Xoshiro256plusGen
Xoshiro256ssGen
Xoshiro256ppGen
Xoshiro512pGen
Xoshiro512ssGen
Xoshiro512ppGen
```

### Functions

```@docs
rand(::MRG32k3a)
rand(::RDST.LinRNG)
rand(::RDST.LinRNG, ::Type{Float32})
rand(::RDST.LinRNG, ::Type{Float16})
rand(::RDST.LinRNG, ::UnitRange{Int64})
rand(::MRG32k3a, ::RDST.Random.SamplerTrivial{RDST.Random.CloseOpen12_64})
short_jump!
long_jump!
advance_state!
srand!
get_state
next_stream!
reset_stream!
reset_substream!
next_substream!
```
