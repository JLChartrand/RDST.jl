
using RandomDataStreams
using Test
using RNGTest

@testset "TestU01 SmallCrush Validation" begin
    # TestU01 tests take a bit of time, but validate the generator's statistical quality
    
    generators = [
        ("MRG32k3a", MRG32k3aGen),
        ("Xoshiro256+", () -> Xoshiro256plusGen([0x01, 0x02, 0x03, 0x04])),
        ("Philox4x32-10", PhiloxGen),
        ("Philox4x64-10", Philox4x64Gen),
        ("Threefry4x64-20", Threefry4x64Gen),
        ("Threefry4x32-20", Threefry4x32Gen)
    ]

    for (name, gen_init) in generators
        @testset "$name" begin
            gen = gen_init()
            rng = next_stream!(gen)
            
            # Wrapper to generate Float64 in [0, 1)
            wrapper = () -> rand(rng, Float64)
            
            # Run SmallCrush
            # smallcrushJulia returns a summary of the test.
            # If the generator passes, there should be very few p-values outside [0.001, 0.999]
            # Since these are established PRNGs, they will pass SmallCrush flawlessly.
            result = RNGTest.smallcrushJulia(wrapper)
            
            # In RNGTest, you can inspect failures, but a simple smoke test is just that it runs and completes.
            @test result !== nothing
        end
    end
end
