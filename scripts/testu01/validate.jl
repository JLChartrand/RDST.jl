#!/usr/bin/env julia

# On-demand TestU01 validation.
#
# This is NOT part of `Pkg.test()`, and must not become part of it: the package
# test suite verifies that an installation works, and runs SmallCrush only.
# Crush takes hours and BigCrush the better part of a day per generator, which
# is a validation exercise -- for a release, or for a paper -- not an
# installation check.
#
#     julia scripts/testu01/validate.jl --list
#     julia scripts/testu01/validate.jl --battery=crush --generator=Xoshiro256p
#     julia scripts/testu01/validate.jl --battery=bigcrush --suite=bits
#
# Options
#   --battery=smallcrush|crush|bigcrush   default smallcrush
#   --suite=single|interleaved|bits|all   default single
#   --generator=<name>|all                default all
#   --streams=<n>                         streams for the interleaved suite (64)
#   --values=<n>                          values per stream, interleaved (1)
#   --out=<dir>                           default testu01-results
#   --list                                print the plan and exit
#   --quiet                               summary only, no per-test reports
#
# Each run writes the battery's own TestU01 report to its own log file and
# appends one line to `summary.tsv`. Read the reports: TestU01 ends with a
# summary naming every test whose p-value falls outside [1e-3, 1-1e-3].

using Pkg
Pkg.activate(@__DIR__)
haskey(Pkg.project().dependencies, "RandomDataStreams") ||
    Pkg.develop(path = joinpath(@__DIR__, "..", ".."))
Pkg.instantiate()

using RandomDataStreams, Random, RNGTest, Printf, Dates

# Generators ------------------------------------------------------------------

# Seeds are expanded through splitmix64 from one fixed integer: a low-entropy
# state such as all-ones takes a while to mix and is a poor starting point for
# a battery, while a fixed integer keeps the runs reproducible.
seed_words(n::Int) = RandomDataStreams._splitmix_words(UInt64(12345), n)

# Every generator the package ships, each with the stream generator that
# produces it, so that all three suites cover the same set.
const GENERATOR_STREAMS = Pair{String,Any}[
    "MRG32k3a"        => MRG32k3aGen,
    "Xoroshiro128p"   => () -> Xoroshiro128pGen(seed_words(2)),
    "Xoroshiro128ss"  => () -> Xoroshiro128ssGen(seed_words(2)),
    "Xoroshiro128pp"  => () -> Xoroshiro128ppGen(seed_words(2)),
    "Xoshiro256p"     => () -> Xoshiro256plusGen(seed_words(4)),
    "Xoshiro256ss"    => () -> Xoshiro256ssGen(seed_words(4)),
    "Xoshiro256pp"    => () -> Xoshiro256ppGen(seed_words(4)),
    "Xoshiro512p"     => () -> Xoshiro512pGen(seed_words(8)),
    "Xoshiro512ss"    => () -> Xoshiro512ssGen(seed_words(8)),
    "Xoshiro512pp"    => () -> Xoshiro512ppGen(seed_words(8)),
    "Philox4x32-10"   => PhiloxGen,
    "Philox4x64-10"   => Philox4x64Gen,
    "Threefry4x32-20" => Threefry4x32Gen,
    "Threefry4x64-20" => Threefry4x64Gen,
]

const GENERATORS = GENERATOR_STREAMS

# Suites ----------------------------------------------------------------------
#
# single       the U(0,1) output, what the batteries were designed for
# interleaved  several streams round-robin, testing the streams against each
#              other rather than each on its own (L'Ecuyer et al. 2021, Sec. 6)
# bits         the UInt32 integer path, which the Crush batteries never see:
#              they examine the 30 most significant bits of the U(0,1) outputs

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

mutable struct BitStream{R} <: AbstractRNG
    rng::R
end
Random.rand(w::BitStream, ::Random.SamplerType{UInt32}) = rand(w.rng, UInt32)

# TestU01 calls back into Julia through a C function pointer, so the callback
# must be a Function whose return type infers to Float64. The generator tables
# have an abstract element type, so everything below goes through a function
# barrier: called with a value of unknown type, these specialise on its runtime
# type and close over something concrete. Without the barrier the callback
# returns Any and the C side segfaults.
_single_stream(rng) = () -> rand(rng, Float64)
_bit_stream(rng) = RNGTest.wrap(BitStream(rng), UInt32)
_interleaved(streams::Vector, per::Int) =
    let g = RoundRobin(streams, 1, 0, per)
        () -> g()
    end

stream_gen(name::String) =
    GENERATOR_STREAMS[findfirst(p -> first(p) == name, GENERATOR_STREAMS)].second()
make_rng(name::String) = next_stream!(stream_gen(name))

function build(suite::String, name::String, opts)
    gen = if suite == "single"
        _single_stream(make_rng(name))
    elseif suite == "interleaved"
        g = stream_gen(name)
        _interleaved([next_stream!(g) for _ in 1:opts.streams], opts.values)
    elseif suite == "bits"
        _bit_stream(make_rng(name))
    else
        error("unknown suite: $suite")
    end
    if gen isa Function
        rt = Base.return_types(gen, ())
        (length(rt) == 1 && rt[1] === Float64) ||
            error("callback for $name/$suite is not inferred as Float64 (got $rt); " *
                  "handing it to TestU01 would crash")
    end
    return gen
end

"""
Re-enable TestU01's per-test reports.

RNGTest clears `swrite_Basic` when it loads, which leaves only the final
summary. For a validation run we want the canonical TestU01 report -- every
test with its parameters and p-value -- both to archive and because it is what
makes a battery running for hours observable: the log fills as the tests
complete instead of staying empty until the end.
"""
function set_testu01_verbose(on::Bool)
    try
        unsafe_store!(RNGTest.swrite[], reinterpret(Ptr{Bool}, UInt(on)), 1)
        return true
    catch
        return false
    end
end

"""
Put C's stdout in line-buffered mode.

A battery runs for hours inside a single C call, and C stdout is block-buffered
when it is not a terminal: without this the log stays empty until the run ends,
so an interrupted or crashed run leaves nothing behind and progress cannot be
followed with `tail -f`. Returns false if the C stdout symbol is not reachable,
in which case the report still arrives, just all at once at the end.
"""
function line_buffer_c_stdout()
    try
        cstdout = unsafe_load(cglobal(:stdout, Ptr{Cvoid}))
        ccall(:fflush, Cint, (Ptr{Cvoid},), cstdout)
        ccall(:setvbuf, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Csize_t),
              cstdout, C_NULL, Cint(1), Csize_t(0)) == 0     # 1 = _IOLBF
    catch
        false
    end
end

const BATTERIES = Dict(
    "smallcrush" => (RNGTest.smallcrushTestU01, "minutes"),
    "crush"      => (RNGTest.crushTestU01,      "a few hours"),
    "bigcrush"   => (RNGTest.bigcrushTestU01,   "most of a day"),
)

# Driver ----------------------------------------------------------------------

function parse_args(args)
    opts = (battery = "smallcrush", suite = "single", generator = "all",
            streams = 64, values = 1, out = "testu01-results",
            list = false, quiet = false)
    for a in args
        if a == "--list"
            opts = merge(opts, (list = true,))
        elseif a == "--quiet"
            opts = merge(opts, (quiet = true,))
        elseif startswith(a, "--")
            k, _, v = partition(a)
            k == "battery"   ? (opts = merge(opts, (battery = lowercase(v),))) :
            k == "suite"     ? (opts = merge(opts, (suite = lowercase(v),))) :
            k == "generator" ? (opts = merge(opts, (generator = v,))) :
            k == "streams"   ? (opts = merge(opts, (streams = parse(Int, v),))) :
            k == "values"    ? (opts = merge(opts, (values = parse(Int, v),))) :
            k == "out"       ? (opts = merge(opts, (out = v,))) :
            error("unknown option: $a")
        else
            error("unexpected argument: $a")
        end
    end
    haskey(BATTERIES, opts.battery) || error("unknown battery: $(opts.battery)")
    return opts
end

function partition(a)
    body = a[3:end]
    i = findfirst('=', body)
    i === nothing && error("option needs a value: $a")
    return body[1:i-1], '=', body[i+1:end]
end

function plan(opts)
    names = opts.generator == "all" ? first.(GENERATORS) : [opts.generator]
    for n in names
        any(p -> first(p) == n, GENERATORS) || error("unknown generator: $n")
    end
    suites = opts.suite == "all" ? ["single", "interleaved", "bits"] : [opts.suite]
    return [(n, s) for s in suites for n in names]
end

# RNGTest drives TestU01 through `@cfunction($f, ...)`, which needs an
# executable trampoline for the closure. Apple Silicon forbids writable and
# executable memory, so no battery can run there whatever the generator; say so
# once, clearly, instead of failing inside the first run.
function testu01_available()
    try
        f = let x = 1.0
            () -> x
        end
        @cfunction($f, Float64, ())
        return true
    catch
        return false
    end
end

function main(args)
    opts = parse_args(args)
    runs = plan(opts)
    battery, duration = BATTERIES[opts.battery]

    println("TestU01 validation -- ", opts.battery)
    println("Julia ", VERSION, ", ", Sys.CPU_NAME, ", ", Sys.MACHINE)
    println(length(runs), " run(s), each taking ", duration, " for this battery\n")
    for (n, s) in runs
        @printf("  %-16s %s\n", n, s)
    end
    if opts.list
        println("\n--list given, nothing run.")
        return
    end
    if !testu01_available()
        println("\nThis platform cannot build a C callback from a closure, which")
        println("RNGTest needs to drive TestU01 (Apple Silicon). Nothing can run here.")
        exit(1)
    end

    mkpath(opts.out)
    index = joinpath(opts.out, "summary.tsv")
    isfile(index) || open(io -> println(io,
        "timestamp\tbattery\tsuite\tgenerator\tseconds\tlog\tjulia\tcpu"), index, "w")

    println()
    for (name, suite) in runs
        stamp = Dates.format(now(), "yyyymmdd-HHMMSS")
        log = joinpath(opts.out, "$(opts.battery)-$(suite)-$(replace(name, r"[^\w]" => "_"))-$stamp.log")
        @printf("--> %-16s %-12s -> %s\n", name, suite, log)
        flush(stdout)

        gen = try
            build(suite, name, opts)
        catch err
            println("    SKIPPED: ", sprint(showerror, err))
            continue
        end
        elapsed = open(log, "w") do io
            println(io, "# ", opts.battery, " / ", suite, " / ", name)
            println(io, "# Julia ", VERSION, ", ", Sys.CPU_NAME, ", ", Sys.MACHINE)
            println(io, "# started ", now())
            suite == "interleaved" &&
                println(io, "# ", opts.streams, " streams, ", opts.values, " value(s) each, round-robin")
            flush(io)
            # TestU01 writes its report from C. Redirecting the descriptor is
            # not enough on its own: C stdout is block-buffered when it is not
            # a terminal, so without the fflush the report is still in the C
            # buffer when the descriptor is restored and lands on the console
            # instead of in the log.
            @elapsed redirect_stdout(io) do
                try
                    line_buffer_c_stdout()
                    set_testu01_verbose(!opts.quiet)
                    battery(gen)
                finally
                    ccall(:fflush, Cint, (Ptr{Cvoid},), C_NULL)
                end
            end
        end

        open(index, "a") do io
            println(io, join((now(), opts.battery, suite, name, round(elapsed, digits = 1),
                              log, VERSION, Sys.CPU_NAME), '\t'))
        end
        @printf("    done in %.1f s\n", elapsed)
    end

    println("\nSummary index: ", index)
    println("Read each log's final section: TestU01 lists every test whose")
    println("p-value falls outside [1e-3, 1-1e-3], or says all tests were passed.")
end

main(ARGS)
