# Statistical testing of the INTEGER paths, at the bit level.
#
# The Crush batteries of TestU01 examine the 30 most significant bits of the
# U(0,1) outputs (L'Ecuyer, Nadeau-Chamard, Chen & Lebar 2021, Sec. 6), so the
# SmallCrush run in test_testu01.jl says nothing about how a generator builds a
# machine integer. For a generator whose native output *is* a word -- Philox
# 4x32, Threefry 4x32 -- that is the same stream and needs no separate test.
# For the others the integer is a construction, and a construction has to be
# tested for itself:
#
#   * MRG32k3a assembles 16-bit chunks of z = (x1 - x2) mod m1, whose modulus
#     is not a power of two. Its UInt64 previously had a second implementation,
#     built from the mantissas of two [1,2) draws, which failed here with six
#     p-values at 0 -- bit 12 came out set in two draws out of three -- while
#     passing every U(0,1) battery. This file is the regression net for that.
#   * The 64-bit counter-based families take the low half of a cipher word.
#   * Xoshiro256+ takes the low 32 bits of an additive scrambler, whose lowest
#     bits Blackman & Vigna document as linearly weak. SmallCrush does not
#     resolve that weakness; passing here is not a clearance for those bits.

using RandomDataStreams
using Test
using Random
using RNGTest

@isdefined(testu01_available) || include("testu01_support.jl")


# RNGTest drives an AbstractRNG through `rand!`, so a stream of constructed
# words is exposed as a generator of UInt32.
mutable struct BitStream{F} <: AbstractRNG
    draw::F                                   # () -> UInt32
end
Random.rand(w::BitStream, ::Random.SamplerType{UInt32}) = w.draw()

"Split each 64-bit draw into its two halves, low first."
function halves_of_u64(rng)
    buf = Ref(UInt64(0))
    high = Ref(false)
    return function ()
        if high[]
            high[] = false
            return (buf[] >>> 32) % UInt32
        else
            buf[] = rand(rng, UInt64)
            high[] = true
            return buf[] % UInt32
        end
    end
end

if !testu01_available()
    testu01_skip_notice("TestU01 on the integer paths")
else
@testset "TestU01 SmallCrush on the integer paths" begin
    streams = [
        ("MRG32k3a UInt32",        () -> (m = MRG32k3a(); () -> rand(m, UInt32))),
        ("MRG32k3a UInt64",        () -> halves_of_u64(MRG32k3a())),
        ("Philox4x64-10 UInt32",   () -> (r = next_stream!(Philox4x64Gen()); () -> rand(r, UInt32))),
        ("Threefry4x64-20 UInt32", () -> (r = next_stream!(Threefry4x64Gen()); () -> rand(r, UInt32))),
        ("Xoshiro256+ UInt32",     () -> (r = Xoshiro256p(UInt64[1, 2, 3, 4]); () -> rand(r, UInt32))),
    ]

    for (name, mk) in streams
        @testset "$name" begin
            bad = suspect_pvalues(RNGTest.smallcrushJulia(RNGTest.wrap(BitStream(mk()), UInt32)))
            @test isempty(bad)
        end
    end
end
end
