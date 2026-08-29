#!/usr/bin/env julia

# This script runs the TestU01 BigCrush test suite on the implemented generators.
# Note: BigCrush takes several hours to complete (typically 8-12 hours per generator).
# The output can be redirected to a file to be included in the documentation.

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "test"))

using RandomDataStreams
using RNGTest

function run_bigcrush()
    println("================================================")
    println("  TestU01 BigCrush Validation")
    println("================================================\n")

    generators = [
        ("MRG32k3a", MRG32k3aGen),
        ("Xoshiro256+", () -> Xoshiro256plusGen([0x01, 0x02, 0x03, 0x04])),
        ("Philox4x32-10", PhiloxGen),
        ("Philox4x64-10", Philox4x64Gen)
    ]

    for (name, gen_init) in generators
        println("--> Starting BigCrush for: $name")
        println("    (This will take several hours)\n")
        
        gen = gen_init()
        rng = next_stream!(gen)
        
        wrapper = () -> rand(rng, Float64)
        
        time_elapsed = @elapsed begin
            res = RNGTest.bigcrushJulia(wrapper)
        end
        
        println("\n--- Results for $name ---")
        println(res)
        println("Time elapsed: ", round(time_elapsed / 3600, digits=2), " hours")
        println("-"^48, "\n")
    end
end

# L'Ecuyer, Nadeau-Chamard, Chen & Lebar (2021), Sec. 6: batteries must also be
# run on sequences that interleave several streams round-robin, to test the
# dependence *between* streams. The test suite runs the light configuration
# (SmallCrush, 64 streams, 1 value each); these are the heavier ones the paper
# suggests -- a power of two from 16 to 1024 streams, 1 to 8 values per stream.

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
    return () -> g()               # RNGTest needs a Function, and a type-stable one
end

function run_interleaved_bigcrush()
    println("================================================")
    println("  TestU01 BigCrush on interleaved streams")
    println("================================================\n")

    generators = [
        ("MRG32k3a", MRG32k3aGen),
        ("Xoshiro256+", () -> Xoshiro256plusGen([0x01, 0x02, 0x03, 0x04])),
        ("Philox4x32-10", PhiloxGen),
        ("Philox4x64-10", Philox4x64Gen)
    ]

    for (name, gen_init) in generators, (ns, per) in ((16, 8), (256, 2), (1024, 1))
        println("--> BigCrush, $name, $ns streams x $per value(s), round-robin")
        println("    (This will take several hours)\n")

        time_elapsed = @elapsed begin
            res = RNGTest.bigcrushJulia(interleaved(gen_init, ns, per))
        end

        println("\n--- Results for $name ($ns x $per) ---")
        println(res)
        println("Time elapsed: ", round(time_elapsed / 3600, digits=2), " hours")
        println("-"^48, "\n")
    end
end

run_bigcrush()
run_interleaved_bigcrush()
