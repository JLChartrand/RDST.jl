using RandomDataStreams
using Test
using Random

statewords(::Type{RandomDataStreams.LinRNG{N,S}}) where {N,S} = N

@testset "RandomDataStreams.jl" begin

    @testset "checkseed" begin
        @test checkseed(RandomDataStreams.DEFAULT_SEED)
        @test !checkseed([1, 2, 3, 4, 5])                       # wrong length
        @test !checkseed([0, 0, 0, 1, 1, 1])                    # all-zero first component
        @test !checkseed([1, 1, 1, 0, 0, 0])                    # all-zero second component
        @test !checkseed([-1, 1, 1, 1, 1, 1])                   # negative entry
        @test !checkseed([RandomDataStreams.PMF.m1, 1, 1, 1, 1, 1])          # >= m1 in first half
        @test !checkseed([1, 1, 1, RandomDataStreams.PMF.m2, 1, 1])          # >= m2 in second half
        @test checkseed([RandomDataStreams.PMF.m1 - 1, RandomDataStreams.PMF.m2 - 1, 7, RandomDataStreams.PMF.m2 - 1, 3, 9])
    end

    @testset "MRG32k3a constructors" begin
        rng = MRG32k3a()
        @test rng.Cg == RandomDataStreams.DEFAULT_SEED && rng.Bg == RandomDataStreams.DEFAULT_SEED && rng.Ig == RandomDataStreams.DEFAULT_SEED

        seed = [42, 1, 2, 3, 4, 5]
        rng = MRG32k3a(seed)
        seed[1] = -100                    # constructor must copy the seed
        @test rng.Cg[1] == 42

        x = [1, 2, 3, 4, 5, 6]
        y = [10, 20, 30, 40, 50, 60]
        z = [100, 200, 300, 400, 500, 600]
        rng = MRG32k3a(x, y, z)
        @test rng.Cg == x && rng.Bg == y && rng.Ig == z
        x[1] = 999                        # no aliasing
        @test rng.Cg[1] == 1

        @test_throws AssertionError MRG32k3a([0, 0, 0, 1, 1, 1])
    end

    @testset "MRG32k3a reference values" begin
        rng = next_stream!(MRG32k3aGen())
        @test [rand(rng) for _ in 1:5] ==
              [0.12701112204657714, 0.3185275653967945,
               0.3091860155832701, 0.8258468629271136, 0.2216299157820229]

        for (T, ref) in (
            (UInt8,   UInt8[0xed, 0x82, 0x51]),
            (UInt16,  UInt16[0xcced, 0x0582, 0xd051]),
            (UInt32,  UInt32[0xcced0582, 0xd051b288, 0xbcca9934]),
            (UInt64,  UInt64[0xcced0582d051b288, 0xbcca99340444f89c, 0x22d387a29770f58a]),
            (UInt128, UInt128[0xcced0582d051b288bcca99340444f89c,
                              0x22d387a29770f58a57416a5915ef65d6,
                              0x9ef65959a1651d5418ebdf4023a8b6d5]),
            (Int8,    Int8[-19, -126, 81]),
            (Int16,   Int16[-13075, 1410, -12207]),
            (Int32,   Int32[-856881790, -799952248, -1127573196]),
            (Int64,   Int64[-3680279261092924792, -4842890000594569060, 2509498549770712458]),
            (Int128,  Int128[-67889169649162077992496674455215081316,
                             46292077500965604301225650373683799510,
                             -128985226324011672590792899314054547755]),
            (Float32, Float32[0.8517306, 0.63826084, 0.5828004]),
            (Float16, Float16[0.2314, 0.377, 0.0791]),
            (Bool,    Bool[1, 0, 1]),
        )
            r = next_stream!(MRG32k3aGen())
            @test [rand(r, T) for _ in 1:3] == ref
        end
    end

    @testset "MRG32k3a output properties" begin
        rng = MRG32k3a()
        u = [rand(rng) for _ in 1:100_000]
        @test all(0.0 .<= u .< 1.0)
        @test abs(sum(u) / length(u) - 0.5) < 0.01

        r = next_stream!(MRG32k3aGen())
        v = [rand(r, 1:10) for _ in 1:10_000]
        @test all(1 .<= v .<= 10)
        @test count(==(1), v) > 500 && count(==(10), v) > 500
    end

    @testset "MRG32k3a streams & substreams" begin
        gen = MRG32k3aGen()
        rng1 = next_stream!(gen)
        rng2 = next_stream!(gen)
        first1 = rand(MRG32k3a(copy(rng1.Ig), copy(rng1.Ig), copy(rng1.Ig)))
        first2 = rand(MRG32k3a(copy(rng2.Ig), copy(rng2.Ig), copy(rng2.Ig)))

        # successive streams are disjoint
        a = [rand(rng1) for _ in 1:100]
        b = [rand(rng2) for _ in 1:100]
        @test Set(a) ∩ Set(b) == Set{Float64}()

        # reset_stream! rewinds to the very beginning
        rand(rng1); rand(rng1)
        reset_stream!(rng1)
        @test rand(rng1) == first1

        # reset_substream!: no next_substream! yet -> back to the stream start
        reset_substream!(rng2)
        @test rand(rng2) == first2

        # next_substream! opens a new, different block; reset_substream! rewinds it
        v1 = rand(rng2)
        next_substream!(rng2)
        w1 = rand(rng2)
        reset_substream!(rng2)
        @test rand(rng2) == w1          # start of the new substream
        @test v1 != w1
    end

    @testset "MRG32k3a state handling" begin
        rng = next_stream!(MRG32k3aGen())
        state = get_state(rng)
        xs = [rand(rng) for _ in 1:5]

        clone = MRG32k3a(state, state, state)
        @test rand(clone) == xs[1]

        st = get_state(rng)
        st[1] += 1                      # get_state must return an independent copy
        @test get_state(rng) != st

        c = copy(rng)
        rand(c); rand(c)
        @test rand(rng) != rand(c)      # copies evolve independently
    end

    @testset "MRG32k3a advance_state!" begin
        ref = next_stream!(MRG32k3aGen())
        vals = [rand(ref) for _ in 1:4]

        rng = MRG32k3a([12345, 12345, 12345, 12345, 12345, 12345])
        advance_state!(rng, Int64(2), Int64(-1))     # skip n = 2^2 - 1 = 3 values
        @test rand(rng) == vals[4]

        # backward jump: after consuming vals[4] the position is 4; n = -2^2 = -4
        advance_state!(rng, Int64(-2), Int64(0))
        @test rand(rng) == vals[1]

        # e = 0, c = k: plain forward jump
        rng2 = MRG32k3a([12345, 12345, 12345, 12345, 12345, 12345])
        advance_state!(rng2, Int64(0), Int64(2))
        @test rand(rng2) == vals[3]
    end

    @testset "MRG32k3aGen" begin
        gen = MRG32k3aGen()
        @test gen.seed == RandomDataStreams.DEFAULT_SEED
        @test get_state(gen) == RandomDataStreams.DEFAULT_SEED

        custom = MRG32k3aGen([7, 7, 7, 8, 8, 8])
        @test get_state(custom) == [7, 7, 7, 8, 8, 8]
        @test_throws AssertionError MRG32k3aGen([0, 0, 0, 1, 1, 1])

        g2 = MRG32k3aGen([1, 2, 3, 4, 5, 6])
        r = next_stream!(g2)
        @test get_state(g2) != [1, 2, 3, 4, 5, 6]   # internal seed advanced
    end

    @testset "Xoshiro256p reference values" begin
        seed = UInt64[0x01, 0x02, 0x03, 0x04]
        x = Xoshiro256p(seed)
        @test [RandomDataStreams.next(x) for _ in 1:5] == UInt64[
            0x0000000000000005, 0x0000c00000000007, 0x0000c00018000007,
            0x8001600018040302, 0x8061900024040305]

        x = Xoshiro256p(seed); short_jump!(x)
        @test RandomDataStreams.next(x) == 1153146630064993313
        x = Xoshiro256p(seed); long_jump!(x)
        @test RandomDataStreams.next(x) == 4237864540600467441
    end

    @testset "Xoshiro256p outputs" begin
        x = Xoshiro256p(UInt64[1, 2, 3, 4])
        u = [rand(x) for _ in 1:100_000]
        @test all(0.0 .<= u .< 1.0)
        @test abs(sum(u) / length(u) - 0.5) < 0.01

        x = Xoshiro256p(UInt64[1, 2, 3, 4])
        @test rand(x, UInt64) isa UInt64
        @test rand(x, Float32) isa Float32
        @test rand(x, Float16) isa Float16

        v = [rand(x, Int64(1):Int64(10)) for _ in 1:10_000]
        @test all(1 .<= v .<= 10)
        counts = [count(==(i), v) for i in 1:10]
        @test maximum(counts) < 1500 && minimum(counts) > 500
    end

    @testset "Xoshiro256p streams & substreams" begin
        seed = UInt64[0x01, 0x02, 0x03, 0x04]
        x = Xoshiro256p(seed)
        u0 = RandomDataStreams.next(x)

        srand!(x, seed)
        @test RandomDataStreams.next(x) == u0

        x = Xoshiro256p(seed)
        short_jump!(x)
        after_short = RandomDataStreams.next(x)
        reset_substream!(x)
        @test RandomDataStreams.next(x) == after_short

        x = Xoshiro256p(seed)
        long_jump!(x)
        after_long = RandomDataStreams.next(x)
        reset_stream!(x)
        @test RandomDataStreams.next(x) == after_long

        next_substream!(x)
        ns = RandomDataStreams.next(x)
        reset_substream!(x)
        @test RandomDataStreams.next(x) == ns
    end

    @testset "Xoshiro256p state" begin
        seed = UInt64[0x01, 0x02, 0x03, 0x04]
        x = Xoshiro256p(seed)
        st = get_state(x)
        @test st isa Vector{UInt64} && length(st) == 4
        expected = RandomDataStreams.next(x)
        y = Xoshiro256p(st)
        @test RandomDataStreams.next(y) == expected

        c = copy(x)
        RandomDataStreams.next(c)
        @test RandomDataStreams.next(x) != RandomDataStreams.next(c)
    end

    @testset "Xoshiro256plusGen" begin
        seed = UInt64[0x0d, 0x0e, 0x0a, 0x0d]
        gen = Xoshiro256plusGen(seed)
        @test get_state(gen) == seed

        seed[1] = 0xff                     # generator must own its copy
        @test get_state(gen)[1] == 0x0d

        r1 = next_stream!(gen)
        r2 = next_stream!(gen)
        @test get_state(r1) != get_state(r2)

        srand!(gen, UInt64[1, 1, 1, 1])
        @test get_state(gen) == UInt64[1, 1, 1, 1]
        @test_throws ArgumentError Xoshiro256plusGen(UInt64[1, 2, 3])
    end


    @testset "Philox reference values" begin
        # Known-answer tests from the Random123 reference implementation
        # (Salmon, Moraes, Dror & Shaw, SC 2011), Philox4x32-10.
        z = ntuple(_ -> UInt32(0), 4)
        @test RandomDataStreams.philox(z, (UInt32(0), UInt32(0))) ==
              (0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8)

        f = typemax(UInt32)
        @test RandomDataStreams.philox((f, f, f, f), (f, f)) ==
              (0x408f276d, 0x41c83b0e, 0xa20bc7c6, 0x6d5451fd)

        @test RandomDataStreams.philox((0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344),
                                       (0xa4093822, 0x299f31d0)) ==
              (0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1)

        # the RNG wrapper must hand out those same words, in order
        rng = next_stream!(PhiloxGen())
        @test [rand(rng, UInt32) for _ in 1:4] ==
              UInt32[0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8]

        # 64-bit draws pair two consecutive 32-bit words, low word first
        rng = next_stream!(PhiloxGen())
        @test RandomDataStreams.next(rng) == 0xe169c58d6627e8d5

        # ... and the same vectors for Philox4x64-10
        z64 = ntuple(_ -> UInt64(0), 4)
        @test RandomDataStreams.philox(z64, (UInt64(0), UInt64(0))) ==
              (0x16554d9eca36314c, 0xdb20fe9d672d0fdc,
               0xd7e772cee186176b, 0x7e68b68aec7ba23b)

        g = typemax(UInt64)
        @test RandomDataStreams.philox((g, g, g, g), (g, g)) ==
              (0x87b092c3013fe90b, 0x438c3c67be8d0224,
               0x9cc7d7c69cd777b6, 0xa09caebf594f0ba0)

        @test RandomDataStreams.philox((0x243f6a8885a308d3, 0x13198a2e03707344,
                                        0xa4093822299f31d0, 0x082efa98ec4e6c89),
                                       (0x452821e638d01377, 0xbe5466cf34e90c6c)) ==
              (0xa528f45403e61d95, 0x38c72dbd566e9788,
               0xa5a1610e72fd18b5, 0x57bd43b5e52b7fe6)

        rng = next_stream!(Philox4x64Gen())
        @test [rand(rng, UInt64) for _ in 1:4] ==
              UInt64[0x16554d9eca36314c, 0xdb20fe9d672d0fdc,
                     0xd7e772cee186176b, 0x7e68b68aec7ba23b]
    end

    @testset "Philox outputs" begin
        rng = next_stream!(PhiloxGen())
        v = [rand(rng) for _ in 1:10_000]
        @test all(0 .<= v .< 1)
        @test 0.48 < sum(v) / length(v) < 0.52

        rng = next_stream!(PhiloxGen())
        w = [rand(rng, 1:10) for _ in 1:10_000]
        @test all(1 .<= w .<= 10)
        @test count(==(1), w) > 500 && count(==(10), w) > 500

        # all four words of a block are consumed before the counter moves on
        rng = next_stream!(PhiloxGen())
        for _ in 1:4
            rand(rng, UInt32)
        end
        @test get_state(rng)[1] == 1
    end

    @testset "Philox streams & substreams" begin
        gen = PhiloxGen()
        s1 = next_stream!(gen)
        s2 = next_stream!(gen)
        @test get_state(s1)[2] != get_state(s2)[2]        # distinct keys
        @test isempty(intersect([rand(s1) for _ in 1:100], [rand(s2) for _ in 1:100]))

        # a substream is a jump of 2^64 blocks in the counter
        reset_stream!(s1)
        v1 = rand(s1, UInt32)
        next_substream!(s1)
        @test get_state(s1)[1] == UInt128(1) << 64
        w1 = rand(s1, UInt32)
        @test v1 != w1

        rand(s1, UInt32)
        reset_substream!(s1)
        @test rand(s1, UInt32) == w1                      # start of the substream
        reset_stream!(s1)
        @test rand(s1, UInt32) == v1                      # start of the stream
    end

    @testset "Philox state" begin
        rng = PhiloxRNG((UInt32(3), UInt32(7)))
        ctr, key, _, idx = get_state(rng)
        @test ctr == 0 && key == (UInt32(3), UInt32(7)) && idx == 5

        srand!(rng, UInt32[1, 2])
        @test get_state(rng)[2] == (UInt32(1), UInt32(2))
        @test_throws ArgumentError srand!(rng, UInt32[1, 2, 3])

        gen = PhiloxGen()
        srand!(gen, UInt32[4, 5])
        @test get_state(gen) == (UInt32(4), UInt32(5))
        @test get_state(next_stream!(gen))[2] == (UInt32(4), UInt32(5))

        # advance_state! counts rand(rng) draws, like every other generator --
        # including across block boundaries. A block of Philox4x32-10 holds four
        # 32-bit words, hence two draws.
        base = let q = next_stream!(PhiloxGen()); [rand(q) for _ in 1:20] end
        for n in (1, 2, 3, 5, 9)
            q = next_stream!(PhiloxGen())
            advance_state!(q, 0, n)
            @test [rand(q) for _ in 1:3] == base[n+1:n+3]
        end

        q = next_stream!(PhiloxGen())              # one draw = two 32-bit words
        advance_state!(q, 0, 1)
        ctr, _, _, idx = get_state(q)
        @test ctr == 1 && idx == 3

        q = next_stream!(PhiloxGen())              # backwards from mid-block
        for _ in 1:7
            rand(q)
        end
        advance_state!(q, 0, -5)
        @test [rand(q) for _ in 1:2] == base[3:4]

        q = next_stream!(PhiloxGen())              # a substream is 2^65 draws
        advance_state!(q, 65, 0)
        @test get_state(q)[1] == UInt128(1) << 64

        a = next_stream!(PhiloxGen())
        b = copy(a)
        @test rand(a) == rand(b)                          # copies are independent
        rand(b)
        @test rand(a) != rand(b)
    end



    @testset "Threefry reference values" begin
        # Known-answer tests from the Random123 reference implementation
        # (Salmon, Moraes, Dror & Shaw, SC 2011), Threefry-4x-20.
        z32 = ntuple(_ -> UInt32(0), 4)
        @test RandomDataStreams.threefry(z32, z32) ==
              (0x9c6ca96a, 0xe17eae66, 0xfc10ecd4, 0x5256a7d8)

        f = typemax(UInt32)
        @test RandomDataStreams.threefry((f, f, f, f), (f, f, f, f)) ==
              (0x2a881696, 0x57012287, 0xf6c7446e, 0xa16a6732)

        @test RandomDataStreams.threefry((0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344),
                                         (0xa4093822, 0x299f31d0, 0x082efa98, 0xec4e6c89)) ==
              (0x59cd1dbb, 0xb8879579, 0x86b5d00c, 0xac8b6d84)

        z64 = ntuple(_ -> UInt64(0), 4)
        @test RandomDataStreams.threefry(z64, z64) ==
              (0x09218ebde6c85537, 0x55941f5266d86105,
               0x4bd25e16282434dc, 0xee29ec846bd2e40b)

        g = typemax(UInt64)
        @test RandomDataStreams.threefry((g, g, g, g), (g, g, g, g)) ==
              (0x29c24097942bba1b, 0x0371bbfb0f6f4e11,
               0x3c231ffa33f83a1c, 0xcd29113fde32d168)

        @test RandomDataStreams.threefry((0x243f6a8885a308d3, 0x13198a2e03707344,
                                          0xa4093822299f31d0, 0x082efa98ec4e6c89),
                                         (0x452821e638d01377, 0xbe5466cf34e90c6c,
                                          0xbe5466cf34e90c6c, 0xc0ac29b7c97c50dd)) ==
              (0xa7e8fde591651bd9, 0xbaafd0c30138319b,
               0x84a5c1a729e685b9, 0x901d406ccebc1ba4)

        # the RNG wrappers must hand out those same words, in order
        rng = next_stream!(Threefry4x64Gen())
        @test [rand(rng, UInt64) for _ in 1:4] ==
              UInt64[0x09218ebde6c85537, 0x55941f5266d86105,
                     0x4bd25e16282434dc, 0xee29ec846bd2e40b]

        rng = next_stream!(Threefry4x32Gen())
        @test [rand(rng, UInt32) for _ in 1:4] ==
              UInt32[0x9c6ca96a, 0xe17eae66, 0xfc10ecd4, 0x5256a7d8]

        # the round count is a real parameter, not a constant tuned for 20:
        # the 13-round variant matches its own Random123 vector
        @test RandomDataStreams.threefry(z64, z64, Val(13)) ==
              (0x4071fabee1dc8e05, 0x02ed3113695c9c62,
               0x397311b5b89f9d49, 0xe21292c3258024bc)
        @test RandomDataStreams.threefry(z32, z32, Val(13)) ==
              (0x531c7e4f, 0x39491ee5, 0x2c855a92, 0x3d6abf9a)

        # no multiplication anywhere: the key schedule is pure xor
        @test RandomDataStreams._threefry_ks((UInt32(1), UInt32(2), UInt32(4), UInt32(8)))[5] ==
              UInt32(1) ⊻ UInt32(2) ⊻ UInt32(4) ⊻ UInt32(8) ⊻ 0x1BD11BDA
    end

    @testset "counter-based variant matrix" begin
        # every stream/state routine must behave identically for each variant
        variants = [
            (PhiloxRNG,       PhiloxGen,       UInt32, 2, "Philox4x32-10"),
            (Philox4x64RNG,   Philox4x64Gen,   UInt64, 2, "Philox4x64-10"),
            (Threefry4x32RNG, Threefry4x32Gen, UInt32, 4, "Threefry4x32-20"),
            (Threefry4x64RNG, Threefry4x64Gen, UInt64, 4, "Threefry4x64-20"),
        ]
        for (T, G, W, K, name) in variants
            key = W[3 + i for i in 1:K]
            toolong = W[1 for _ in 1:(K + 1)]
            gen = G()
            s1 = next_stream!(gen)
            s2 = next_stream!(gen)
            @test s1 isa T && s1 isa AbstractRNG
            @test get_state(s1)[2] != get_state(s2)[2]
            @test isempty(intersect([rand(s1) for _ in 1:100], [rand(s2) for _ in 1:100]))

            r = T()
            v1 = rand(r, W)
            next_substream!(r)
            @test get_state(r)[1] == UInt128(1) << 64
            w1 = rand(r, W)
            rand(r, W)
            reset_substream!(r)
            @test rand(r, W) == w1
            reset_stream!(r)
            @test rand(r, W) == v1

            srand!(r, key)
            @test get_state(r)[2] == NTuple{K,W}(key)
            @test_throws ArgumentError srand!(r, toolong)

            srand!(gen, key)
            @test get_state(gen) == NTuple{K,W}(key)
            @test get_state(next_stream!(gen))[2] == NTuple{K,W}(key)

            a = T(); b = copy(a)
            @test rand(a) == rand(b)
            rand(b)
            @test rand(a) != rand(b)

            y = T(); z = T()
            Random.seed!(y, 987); Random.seed!(z, 987)
            @test [rand(y) for _ in 1:20] == [rand(z) for _ in 1:20]

            io = IOBuffer()
            show(io, T()); @test occursin(name, String(take!(io)))
            show(io, G()); @test occursin(name, String(take!(io)))
        end
    end


    @testset "uniform stream interface" begin
        # code written against AbstractStreamableRNG must work for every
        # generator: same navigation, same get_state/set_state! round-trip,
        # same srand! semantics.
        makers = [
            ("MRG32k3a",      () -> MRG32k3a([42, 1, 2, 3, 4, 5]), [7, 7, 7, 8, 8, 8]),
            ("Xoshiro256pp",  () -> Xoshiro256pp(fill(UInt64(42), 4)), UInt64[1, 2, 3, 4]),
            ("Xoroshiro128ss",() -> Xoroshiro128ss(fill(UInt64(42), 2)), UInt64[5, 6]),
            ("Philox4x32-10", () -> next_stream!(PhiloxGen()), UInt32[3, 4]),
            ("Philox4x64-10", () -> next_stream!(Philox4x64Gen()), UInt64[3, 4]),
            ("Threefry4x64-20", () -> next_stream!(Threefry4x64Gen()), UInt64[3, 4, 5, 6]),
            ("Threefry4x32-20", () -> next_stream!(Threefry4x32Gen()), UInt32[3, 4, 5, 6]),
        ]
        for (name, mk, seed) in makers
            @testset "$name" begin
                r = mk()
                @test r isa RandomDataStreams.AbstractStreamableRNG

                # get_state / set_state! are inverses
                for _ in 1:3
                    rand(r)
                end
                st = get_state(r)
                expected = [rand(r) for _ in 1:5]
                set_state!(r, st)
                @test [rand(r) for _ in 1:5] == expected

                # ... and restoring does not disturb the substream anchor
                set_state!(r, st)
                reset_substream!(r)
                v0 = rand(r)
                reset_substream!(r)
                @test rand(r) == v0

                # advance_state! counts draws, both ways, for every generator
                a = mk()
                base = [rand(a) for _ in 1:12]
                b = mk()
                advance_state!(b, 0, 5)
                @test [rand(b) for _ in 1:3] == base[6:8]
                advance_state!(b, 0, -8)
                @test [rand(b) for _ in 1:3] == base[1:3]

                # srand! rewinds the stream and substream boundaries
                c = mk()
                srand!(c, seed)
                first = [rand(c) for _ in 1:4]
                next_substream!(c)
                rand(c)
                srand!(c, seed)
                @test [rand(c) for _ in 1:4] == first
                reset_stream!(c)
                @test [rand(c) for _ in 1:4] == first
            end
        end
    end


    @testset "array fill matches repeated draws" begin
        # rand! on a counter-based generator writes whole blocks straight into
        # the array. It must produce exactly what the scalar path would have
        # produced, in the same order and leaving the same state -- including
        # when the generator does not start on a block boundary, and for
        # lengths that do not divide the block size.
        variants = [
            ("Philox4x32-10",   () -> next_stream!(PhiloxGen()),       UInt32),
            ("Philox4x64-10",   () -> next_stream!(Philox4x64Gen()),   UInt64),
            ("Threefry4x32-20", () -> next_stream!(Threefry4x32Gen()), UInt32),
            ("Threefry4x64-20", () -> next_stream!(Threefry4x64Gen()), UInt64),
        ]
        for (name, mk, W) in variants
            @testset "$name" begin
                for T in (Float64, UInt64, W), n in (0, 1, 3, 4, 5, 8, 9, 17), pre in (0, 1, 2, 3)
                    a, b = mk(), mk()
                    for _ in 1:pre                 # start off a block boundary
                        rand(a, W); rand(b, W)
                    end
                    v = Vector{T}(undef, n)
                    rand!(a, v)
                    @test v == [rand(b, T) for _ in 1:n]
                    @test get_state(a)[1] == get_state(b)[1]     # counter
                    @test get_state(a)[4] == get_state(b)[4]     # index in block
                end
            end
        end

        # MRG32k3a defined its wide unsigned draws on `::Type` only, so the
        # Sampler machinery behind rand! had no method and this threw.
        a, b = MRG32k3a(), MRG32k3a()
        v = Vector{UInt32}(undef, 5)
        rand!(a, v)
        @test v == [rand(b, UInt32) for _ in 1:5]

        a, b = MRG32k3a(), MRG32k3a()
        w = Vector{UInt128}(undef, 3)
        rand!(a, w)
        @test w == [rand(b, UInt128) for _ in 1:3]
    end

    @testset "show methods" begin
        io = IOBuffer()
        show(io, MRG32k3a())
        @test occursin("MRG32k3a", String(take!(io)))
        show(io, MRG32k3aGen())
        @test occursin("MRG32k3a", String(take!(io)))
        show(io, Xoshiro256p(UInt64[1, 2, 3, 4]))
        @test occursin("Xoshiro256plus", String(take!(io)))
        show(io, Xoshiro256plusGen(UInt64[1, 2, 3, 4]))
        @test occursin("Xoshiro256plus", String(take!(io)))
        show(io, PhiloxRNG())
        @test occursin("Philox", String(take!(io)))
        show(io, PhiloxGen())
        @test occursin("Philox", String(take!(io)))
    end

    @testset "Random API integration" begin
        m = MRG32k3a()
        x = Xoshiro256p(UInt64[1, 2, 3, 4])
        @test m isa AbstractRNG && x isa AbstractRNG

        m1 = copy(m); m2 = copy(m)
        @test rand(m1) == rand(m2)      # identical copies produce identical values
        rand(m2)
        @test rand(m1) != rand(m2)
    end

    @testset "xoshiro/xoroshiro families" begin
        # Reference values validated byte-for-byte against the original C
        # implementations (http://xoshiro.di.unimi.it), seeded via splitmix64(0x12345).
        function splitmix_seed(nwords)
            sm = UInt64(0x12345)
            out = Vector{UInt64}(undef, nwords)
            for w in 1:nwords
                sm += 0x9E3779B97f4A7C15
                z = sm
                z = (z ⊻ (z >> 30)) * 0xBF58476D1CE4E5B9
                z = (z ⊻ (z >> 27)) * 0x94D049BB133111EB
                v = z ⊻ (z >> 31)
                out[w] = v == 0 ? UInt64(1) : v
            end
            out
        end

        refs = [
            ("x128p", RandomDataStreams.Xoroshiro128p,
             [16078810691027958445, 16308033409981753773, 2459436067589474410],
             UInt64(3256517475130558849), UInt64(9914398136390617976)),
            ("x128ss", RandomDataStreams.Xoroshiro128ss,
             [1368380786106859145, 4084486448798807325, 5543098162342028434],
             UInt64(13270538264984994966), UInt64(11920770361629577860)),
            ("x128pp", RandomDataStreams.Xoroshiro128pp,
             [1673598725564225250, 4573856857203627046, 16115075492912290848],
             UInt64(6730732423063272729), UInt64(3990584750745030224)),
            ("x256p", RandomDataStreams.Xoshiro256p,
             [9347869054091033467, 4771635083329966370, 15370539120085914707],
             UInt64(5160113462924517804), UInt64(15646076907341602619)),
            ("x256ss", RandomDataStreams.Xoshiro256ss,
             [1368380786106859145, 14675459340006078963, 5910136538917692306],
             UInt64(10763142405286072350), UInt64(16578569578879967412)),
            ("x256pp", RandomDataStreams.Xoshiro256pp,
             [17674668620475692482, 5475324084790473842, 16549419549621501831],
             UInt64(16231616900645524224), UInt64(13257993063221304277)),
            ("x512p", RandomDataStreams.Xoshiro512p,
             [17616468189221365395, 12780371331858795586, 9670281856951386802],
             UInt64(16537263715482372943), UInt64(2902670574299405512)),
            ("x512ss", RandomDataStreams.Xoshiro512ss,
             [1368380786106859145, 14675459340006078963, 11156859077635828455],
             UInt64(2926543538459652119), UInt64(10490133114023169214)),
            ("x512pp", RandomDataStreams.Xoshiro512pp,
             [4070133962183833323, 16966997717490759717, 12310346514993803299],
             UInt64(13604293740491481571), UInt64(151834235382922295)),
        ]
        for (name, T, seq, shortv, longv) in refs
            seed = splitmix_seed(statewords(T))
            x = T(seed)
            @test [RandomDataStreams.next(x) for _ in 1:3] == seq
            y = T(copy(seed)); short_jump!(y)
            @test RandomDataStreams.next(y) == shortv
            z = T(copy(seed)); long_jump!(z)
            @test RandomDataStreams.next(z) == longv
        end

        allvariants = [
            ("Xoroshiro128plus",     RandomDataStreams.Xoroshiro128p,    RandomDataStreams.Xoroshiro128pGen),
            ("Xoroshiro128starstar", RandomDataStreams.Xoroshiro128ss,   RandomDataStreams.Xoroshiro128ssGen),
            ("Xoshiro256plusplus",   RandomDataStreams.Xoshiro256pp,     RandomDataStreams.Xoshiro256ppGen),
            ("Xoshiro512plus",       RandomDataStreams.Xoshiro512p,      RandomDataStreams.Xoshiro512pGen),
            ("Xoshiro512starstar",   RandomDataStreams.Xoshiro512ss,     RandomDataStreams.Xoshiro512ssGen),
        ]
        for (shown_name, T, G) in allvariants
            n = statewords(T)
            x = T(fill(UInt64(0xdecafbad), n))
            u = [rand(x) for _ in 1:10_000]
            @test all(0.0 .<= u .< 1.0)
            @test abs(sum(u) / length(u) - 0.5) < 0.02
            @test rand(x, UInt64) isa UInt64
            @test rand(x, Float32) isa Float32
            v = [rand(x, Int64(1):Int64(100)) for _ in 1:1000]
            @test all(1 .<= v .<= 100)

            x = T(fill(UInt64(0xbeef), n))
            w0 = RandomDataStreams.next(x)
            next_substream!(x)
            w1 = RandomDataStreams.next(x)
            reset_substream!(x)
            @test RandomDataStreams.next(x) == w1
            reset_stream!(x)
            @test RandomDataStreams.next(x) == w0
            srand!(x, fill(UInt64(0xbeef), n))
            @test get_state(x) == fill(UInt64(0xbeef), n)

            io = IOBuffer()
            show(io, x)
            @test occursin(shown_name, String(take!(io)))

            gen = G(fill(UInt64(0xfeed), n))
            r1 = next_stream!(gen)
            r2 = next_stream!(gen)
            s1 = Set([RandomDataStreams.next(r1) for _ in 1:200])
            s2 = Set([RandomDataStreams.next(r2) for _ in 1:200])
            @test isempty(intersect(s1, s2))
            @test get_state(gen) != fill(UInt64(0xfeed), n)
        end

        @test_throws ArgumentError Xoroshiro128pGen(fill(UInt64(1), 3))
        @test_throws ArgumentError Xoshiro512pGen(fill(UInt64(1), 4))
    end

    @testset "advance_state! (xoshiro families)" begin
        seed256 = fill(UInt64(0x31), 4)

        # fixed-distance jumps agree with short_jump! from a fresh generator
        for (T, e) in ((Xoroshiro128p, 64), (Xoshiro256ss, 128), (Xoshiro512p, 256))
            n = statewords(T)
            seed = fill(UInt64(0xabcdef), n)
            a = T(seed); b = T(seed)
            short_jump!(a)
            advance_state!(b, e, 0)
            @test a.Cg == b.Cg
        end

        # small forward jumps match manual stepping
        for k in (1, 2, 3, 17, 1000)
            y = Xoshiro256p(seed256)
            advance_state!(y, 0, k)
            st = RandomDataStreams._lin_step(Xoshiro256p(seed256).Cg)
            for _ in 2:k
                st = RandomDataStreams._lin_step(st)
            end
            @test y.Cg == st
        end

        # round trip: +k then -k restores the exact position
        for T in (Xoroshiro128pp, Xoshiro256p, Xoshiro512ss)
            x = T(fill(UInt64(7), statewords(T)))
            foreach(_ -> RandomDataStreams.next(x), 1:13)
            orig = x.Cg
            advance_state!(x, 0, 12345)
            @test x.Cg != orig
            advance_state!(x, 0, -12345)
            @test x.Cg == orig
        end

        # backward jump then re-draw reproduces earlier values
        x = Xoshiro512pp(fill(UInt64(9), 8))
        v1 = RandomDataStreams.next(x)
        RandomDataStreams.next(x)
        advance_state!(x, 0, -2)
        @test RandomDataStreams.next(x) == v1

        # distance convention n = 2^e + c (e > 0), -2^-e + c (e < 0), c (e = 0)
        x = Xoshiro256p(seed256); advance_state!(x, 0, 7); advance_state!(x, -1, -1)   # -3
        z = Xoshiro256p(seed256); advance_state!(z, 0, 4)
        @test x.Cg == z.Cg

        a = Xoshiro256p(seed256); advance_state!(a, -2, 5)                             # +1
        @test a.Cg == RandomDataStreams._lin_step(Xoshiro256p(seed256).Cg)

        # distances beyond the period are reduced modulo the period
        x = Xoshiro256p(fill(UInt64(5), 4)); advance_state!(x, 1000, 0)
        y = Xoshiro256p(fill(UInt64(5), 4)); advance_state!(y, 232, 0)
        @test x.Cg == y.Cg

        # boundaries are not moved by arbitrary jumps
        r = Xoshiro256p(fill(UInt64(11), 4))
        bg_before = r.Bg; ig_before = r.Ig
        advance_state!(r, 10, 3)
        @test r.Bg == bg_before && r.Ig == ig_before
    end

    @testset "Random API parity" begin
        # drop-in substitutability with the standard library's Xoshiro:
        # every operation below must work for every RandomDataStreams generator.
        mk = [
            () -> MRG32k3a([42, 1, 2, 3, 4, 5]),
            () -> Xoshiro256pp(fill(UInt64(42), 4)),
            () -> Xoroshiro128ss(fill(UInt64(42), 2)),
            () -> Xoshiro512p(fill(UInt64(42), 8)),
            () -> next_stream!(PhiloxGen()),
            () -> next_stream!(Philox4x64Gen()),
            () -> next_stream!(Threefry4x64Gen()),
            () -> next_stream!(Threefry4x32Gen()),
        ]
        for mkm in mk
            r = mkm()
            @test rand(r) isa Float64
            @test rand(r, Bool) isa Bool
            for T in (Int, UInt8, UInt64, Int128, Char)
                v = rand(r, T)
                @test v isa T
            end
            @test all(1 .<= rand(r, 1:10) .<= 10)
            v = rand(r, 5); @test length(v) == 5
            @test size(rand(r, Int, 2, 2)) == (2, 2)
            d = Vector{Float64}(undef, 4); rand!(r, d); @test all(0 .<= d .< 1)
            n = randn(r); @test n isa Float64
            e = randexp(r); @test e >= 0
            @test sort(shuffle(r, collect(1:8))) == collect(1:8)
            p = randperm(r, 6); @test sort(p) == collect(1:6)
            @test Random.randstring(r, 5) |> length == 5
        end

        # seed! reproducibility: same seed -> identical sequence
        for (mka, seed) in (
            (() -> MRG32k3a(), 12345),
            (() -> Xoshiro256pp(fill(UInt64(0), 4)), 6789),
            (() -> PhiloxRNG(), 6789),
        )
            r1 = mka(); r2 = mka()
            Random.seed!(r1, seed); Random.seed!(r2, seed)
            a1 = [rand(r1) for _ in 1:20]
            a2 = [rand(r2) for _ in 1:20]
            @test a1 == a2
        end

        # seed! accepts vectors and validates them
        r = MRG32k3a()
        Random.seed!(r, [7, 7, 7, 8, 8, 8]); @test r.Cg == [7, 7, 7, 8, 8, 8]
        @test_throws ArgumentError Random.seed!(r, [0, 0, 0, 1, 1, 1])
        x = Xoshiro256p(fill(UInt64(0), 4))
        Random.seed!(x, UInt64[1, 2, 3, 4]); @test get_state(x) == UInt64[1, 2, 3, 4]

        # streams still work through the generic API
        gen = Xoshiro256plusGen(UInt64[1, 2, 3, 4])
        s1 = next_stream!(gen); s2 = next_stream!(gen)
        @test !isempty(intersect([rand(s1) for _ in 1:100], [rand(s2) for _ in 1:100])) ==
              false
    end

    @testset "stream API matrix across all variants" begin
        # every stream/substream routine must work, with correct semantics,
        # for every xoshiro/xoroshiro variant.
        statewords(::Type{RandomDataStreams.LinRNG{N,S}}) where {N,S} = N

        variants = [
            (RandomDataStreams.Xoroshiro128p,    RandomDataStreams.Xoroshiro128pGen),
            (RandomDataStreams.Xoroshiro128ss,   RandomDataStreams.Xoroshiro128ssGen),
            (RandomDataStreams.Xoroshiro128pp,   RandomDataStreams.Xoroshiro128ppGen),
            (Xoshiro256p,           Xoshiro256plusGen),
            (RandomDataStreams.Xoshiro256ss,     RandomDataStreams.Xoshiro256ssGen),
            (RandomDataStreams.Xoshiro256pp,     RandomDataStreams.Xoshiro256ppGen),
            (RandomDataStreams.Xoshiro512p,      RandomDataStreams.Xoshiro512pGen),
            (RandomDataStreams.Xoshiro512ss,     RandomDataStreams.Xoshiro512ssGen),
            (RandomDataStreams.Xoshiro512pp,     RandomDataStreams.Xoshiro512ppGen),
        ]
        for (T, G) in variants
            n = statewords(T)
            seed = fill(UInt64(0xabc), n)

            gen = G(seed)
            s1 = next_stream!(gen); s2 = next_stream!(gen)
            @test RandomDataStreams.get_state(s1) != RandomDataStreams.get_state(s2)

            x = T(seed); srand!(x, seed)
            @test get_state(x) == seed

            y = T(seed); z = T(seed)
            Random.seed!(y, 987); Random.seed!(z, 987)
            @test rand(y) == rand(z)

            a = T(seed); b = copy(a)
            RandomDataStreams.next(b); RandomDataStreams.next(b)
            @test a.Cg != b.Cg

            c = T(seed)
            u0 = RandomDataStreams.next(c)
            RandomDataStreams.next(c); RandomDataStreams.next(c)
            reset_stream!(c)
            @test RandomDataStreams.next(c) == u0

            d = T(seed)
            next_substream!(d)
            w1 = RandomDataStreams.next(d)
            reset_substream!(d)
            @test RandomDataStreams.next(d) == w1

            e1 = T(seed); e2 = T(seed)
            short_jump!(e1)
            next_substream!(e2)
            @test e1.Bg == e2.Bg && e1.Cg == e2.Cg

            f = T(seed)
            long_jump!(f)
            @test f.Bg == f.Cg && f.Ig == f.Cg

            g = T(seed)
            bg0, ig0 = g.Bg, g.Ig
            advance_state!(g, 0, 999)
            advance_state!(g, 0, -999)
            @test g.Cg == T(seed).Cg && g.Bg == bg0 && g.Ig == ig0
        end
    end

    @testset "deprecated names" begin
        seed = fill(UInt64(0x77), 4)
        a = Xoshiro256p(seed)
        @test_logs (:warn, r"deprecated") match_mode = :any begin
            b = short_jump(a)          # old name still works...
            @test b === a              # ...and mutates in place
        end
        @test_logs (:warn, r"deprecated") match_mode = :any begin
            srand(a, seed)
            @test get_state(a) == seed
        end
        gen = MRG32k3aGen()
        @test_logs (:warn, r"deprecated") match_mode = :any next_stream(gen) isa MRG32k3a
    end

end

include("readme.jl")

include("test_testu01.jl")

include("test_streams_interleaved.jl")

include("test_bits.jl")
