#!/usr/bin/env julia

# Reproducible throughput benchmark for every generator of the package.
# Reports draws per second for the three hot paths (Float64, UInt64, UInt32)
# and, for the counter-based families, the raw bijection rate in blocks per
# second -- which separates the cost of the cipher from the cost of the buffer
# machinery around it.
#
#     julia -O3 --project=. scripts/benchmarks/throughput.jl
#
# Numbers are indicative: pin the CPU frequency and close other work before
# quoting them.

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))

using RandomDataStreams, Printf, InteractiveUtils
const RDS = RandomDataStreams

const N_DRAWS = 20_000_000
const N_BLOCKS = 5_000_000

function draws_per_second(mk, ::Type{T}, n = N_DRAWS) where {T}
    rng = mk()
    acc = zero(T)
    rand(rng, T)                                   # compile and warm up
    t = @elapsed for _ in 1:n
        acc += rand(rng, T)
    end
    return n / t / 1e6, acc
end

function float_draws_per_second(mk, n = N_DRAWS)
    rng = mk()
    acc = 0.0
    rand(rng)
    t = @elapsed for _ in 1:n
        acc += rand(rng)
    end
    return n / t / 1e6, acc
end

# The loop has to live inside a function: measuring @allocated over a loop in
# global scope reports the boxing of the loop itself, not the generator.
function draw_loop(rng, n)
    acc = 0.0
    for _ in 1:n
        acc += rand(rng)
    end
    return acc
end

function blocks_per_second(bijection, ctr, key, n = N_BLOCKS)
    acc = ctr
    bijection(ctr, key)
    t = @elapsed for _ in 1:n
        acc = bijection(acc, key)                  # fed back, so nothing hoists
    end
    return n / t / 1e6, acc
end

function main()
    println("RandomDataStreams throughput")
    println("Julia ", VERSION, ", ", Sys.CPU_NAME, ", ", Sys.MACHINE)
    println(repeat("-", 66), "\n")

    generators = [
        ("MRG32k3a",        () -> MRG32k3a()),
        ("Xoroshiro128p",   () -> Xoroshiro128p(UInt64[1, 2])),
        ("Xoshiro256p",     () -> Xoshiro256p(UInt64[1, 2, 3, 4])),
        ("Xoshiro512p",     () -> Xoshiro512p(fill(UInt64(1), 8))),
        ("Philox4x32-10",   () -> next_stream!(PhiloxGen())),
        ("Philox4x64-10",   () -> next_stream!(Philox4x64Gen())),
        ("Threefry4x32-20", () -> next_stream!(Threefry4x32Gen())),
        ("Threefry4x64-20", () -> next_stream!(Threefry4x64Gen())),
    ]

    @printf("%-18s %14s %14s %14s\n", "generator", "Float64 M/s", "UInt64 M/s", "UInt32 M/s")
    for (name, mk) in generators
        f, _ = float_draws_per_second(mk)
        u64, _ = draws_per_second(mk, UInt64)
        u32, _ = draws_per_second(mk, UInt32)
        @printf("%-18s %14.0f %14.0f %14.0f\n", name, f, u64, u32)
    end

    println("\nRaw bijection rate (counter-based families only):")
    z32 = ntuple(_ -> UInt32(0), 4)
    z64 = ntuple(_ -> UInt64(0), 4)
    bijections = [
        ("philox4x32-10",   (c, k) -> RDS.philox(c, k),   z32, (UInt32(1), UInt32(2))),
        ("philox4x64-10",   (c, k) -> RDS.philox(c, k),   z64, (UInt64(1), UInt64(2))),
        ("threefry4x32-20", (c, k) -> RDS.threefry(c, k), z32, z32),
        ("threefry4x64-20", (c, k) -> RDS.threefry(c, k), z64, z64),
    ]
    @printf("%-18s %14s %14s\n", "bijection", "Mblocks/s", "words/block")
    for (name, f, ctr, key) in bijections
        b, _ = blocks_per_second(f, ctr, key)
        @printf("%-18s %14.1f %14d\n", name, b, 4)
    end

    println("\nAllocations (must be zero):")
    for (name, mk) in generators
        rng = mk()
        draw_loop(rng, 10)                         # compile before measuring
        a = @allocated draw_loop(rng, 1000)
        @printf("  %-18s %d bytes / 1000 draws\n", name, a)
    end
end

main()
