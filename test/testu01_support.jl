# Shared helpers for the three TestU01 batteries.

using Test

"""
    run_battery(f, what) -> result or nothing

Run `f()`, which drives a TestU01 battery, and return `nothing` instead when
the platform cannot hand TestU01 its callback.

RNGTest builds that callback with `@cfunction` over a closure, which needs an
executable trampoline. Apple Silicon forbids memory that is both writable and
executable, so Julia raises `cfunction: closures are not supported on this
platform` and no battery can run there, whatever the generator.

The failure is caught at the point of use rather than predicted by a probe. A
synthetic probe is not trustworthy here: a closure over a constant is compiled
to a singleton, needs no trampoline, and succeeds on exactly the platform where
the real one fails. Only the real call answers the question. Any other error is
rethrown.
"""
function run_battery(f, what)
    try
        return f()
    catch err
        if occursin("closures are not supported", sprint(showerror, err))
            @info "$what skipped: this platform cannot build a C callback " *
                  "from a closure, which RNGTest needs to drive TestU01."
            return nothing
        end
        rethrow()
    end
end

"""
    suspect_pvalues(result) -> Vector{Float64}

p-values outside `[0.001, 0.999]`, the range TestU01 reports as clear failures.
"""
function suspect_pvalues(result)
    ps = Float64[]
    for r in result
        append!(ps, r isa Number ? [r] : collect(r))
    end
    return filter(p -> p < 0.001 || p > 0.999, ps)
end

"""
    check_battery(f, what)

Assert that a battery reports no suspect p-value, or record a skipped test when
the platform cannot run it at all.
"""
function check_battery(f, what)
    res = run_battery(f, what)
    if res === nothing
        @test_skip "TestU01 unavailable on this platform"
    else
        @test isempty(suspect_pvalues(res))
    end
end
