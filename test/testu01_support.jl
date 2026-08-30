# Shared helpers for the three TestU01 batteries.

using Test

"""
    testu01_available() -> Bool

Whether this platform can hand TestU01 a callback.

RNGTest drives the C batteries through `@cfunction(\$f, ...)`, which needs an
executable trampoline for the closure. Apple Silicon forbids writable and
executable memory, so Julia raises `cfunction: closures are not supported on
this platform` there and no battery can run, whatever the generator. The probe
below asks the question directly rather than maintaining a list of platforms.
"""
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

"Print the reason once, so a skipped battery is visible in the log."
function testu01_skip_notice(what)
    @info "$what skipped: this platform cannot build a C callback from a " *
          "closure, which RNGTest needs to drive TestU01 (Apple Silicon)."
end
