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
        ("Xoshiro256+", () -> Xoshiro256plusGen()),
        ("Philox", PhiloxGen)
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

run_bigcrush()
