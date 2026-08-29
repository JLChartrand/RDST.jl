# Dependence BETWEEN streams, not the quality of each stream in isolation.
#
# L'Ecuyer, Nadeau-Chamard, Chen & Lebar (2021), Sec. 6: "For RNGs with multiple
# streams and substreams (including splittable, counter-based, etc.), it is also
# important to test the dependence between those streams. For that, one can
# construct sequences that take a few values from each stream for a certain
# number of streams, in a round-robin fashion [...] a power of 2 from 16 to 1024
# [streams], [...] a fixed number of values per stream (from 1 to 8)."
#
# For a counter-based generator this also exercises the key schedule
# (`stream_key`): a schedule that hands out structurally related keys shows up
# here, not in a battery run on a single stream.

using RandomDataStreams
using Test
using RNGTest

# RNGTest hands the callback to C, so it has to be a `Function` whose return
# type infers to Float64; a mutable functor behind a closure gives both.
mutable struct RoundRobin{R}
    streams::Vector{R}
    s::Int
    c::Int
    per::Int
end

function (g::RoundRobin)()
    v = rand(g.streams[g.s], Float64)
    g.c += 1
    if g.c == g.per
        g.c = 0
        g.s = g.s == length(g.streams) ? 1 : g.s + 1
    end
    return v
end

function interleaved(gen_init, nstreams::Int, per_stream::Int)
    gen = gen_init()
    g = RoundRobin([next_stream!(gen) for _ in 1:nstreams], 1, 0, per_stream)
    return () -> g()
end

"p-values outside [0.001, 0.999], the range TestU01 reports as clear failures."
function suspect_pvalues(result)
    ps = Float64[]
    for r in result
        append!(ps, r isa Number ? [r] : collect(r))
    end
    return filter(p -> p < 0.001 || p > 0.999, ps)
end

@testset "TestU01 SmallCrush on interleaved streams" begin
    generators = [
        ("MRG32k3a", MRG32k3aGen),
        ("Xoshiro256+", () -> Xoshiro256plusGen([0x01, 0x02, 0x03, 0x04])),
        ("Philox4x32-10", PhiloxGen),
        ("Philox4x64-10", Philox4x64Gen),
        ("Threefry4x64-20", Threefry4x64Gen),
        ("Threefry4x32-20", Threefry4x32Gen),
    ]

    for (name, gen_init) in generators
        @testset "$name" begin
            f = interleaved(gen_init, 64, 1)
            @test Base.return_types(f, ())[1] === Float64   # else the C callback crashes
            bad = suspect_pvalues(RNGTest.smallcrushJulia(f))
            @test isempty(bad)
        end
    end
end
