
using RandomDataStreams
using Test
using RNGTest

@isdefined(check_battery) || include("testu01_support.jl")


@testset "battery guard" begin
    # The platform failure is skipped; anything else must not be swallowed.
    # Verified here rather than trusted, since the skip branch is unreachable
    # on the platforms where the suite normally runs.
    @test run_battery(() -> error("cfunction: closures are not supported on this platform"),
                      "guard") === nothing
    @test run_battery(() -> 42, "guard") == 42
    @test_throws ErrorException run_battery(() -> error("boom"), "guard")
end

@testset "TestU01 SmallCrush Validation" begin
    # TestU01 tests take a bit of time, but validate the generator's statistical quality
    
    generators = [
        ("MRG32k3a", MRG32k3aGen),
        ("Xoshiro256+", () -> Xoshiro256plusGen([0x01, 0x02, 0x03, 0x04])),
        ("Philox4x32-10", PhiloxGen),
        ("Philox4x64-10", Philox4x64Gen),
        ("Threefry4x64-20", Threefry4x64Gen),
        ("Threefry4x32-20", Threefry4x32Gen),
        ("PCG64", () -> PCG64Gen(20260830)),
        ("PCG64DXSM", () -> PCG64DXSMGen(20260830))
    ]

    for (name, gen_init) in generators
        @testset "$name" begin
            gen = gen_init()
            rng = next_stream!(gen)
            
            wrapper = () -> rand(rng, Float64)      # Float64 in [0, 1)
            check_battery(() -> RNGTest.smallcrushJulia(wrapper), "SmallCrush / $name")
        end
    end
end
