# Statistical Validation (TestU01)

`RandomDataStreams.jl` integrates seamlessly with [TestU01](http://simul.iro.umontreal.ca/testu01/tu01.html), the industry-standard C library for empirical statistical testing of RNGs, via the `RNGTest.jl` wrapper.

## Continuous Integration (SmallCrush)

A subset of the TestU01 batteries, **SmallCrush**, is automatically executed on all supported generators (`MRG32k3a`, `Xoshiro256+`, `Philox4x32-10`, `Philox4x64-10`, `Threefry4x64-20` and `Threefry4x32-20`) during the standard test suite. You can trigger this locally by running:

```julia
using Pkg
Pkg.test("RandomDataStreams")
```

## Dependence between streams

A battery run on a single stream says nothing about whether the *streams* are
independent of each other. Following L'Ecuyer et al. (2021, Sec. 6) — "it is
also important to test the dependence between those streams [...] one can
construct sequences that take a few values from each stream for a certain
number of streams, in a round-robin fashion" — the test suite also runs
SmallCrush on a sequence built by interleaving 64 streams, one value at a time,
for each of the six generators. For a counter-based generator this is what
exercises the key schedule: a schedule handing out structurally related keys
shows up here and not in a battery run on a single stream.

The heavier configurations recommended by the paper (up to 1024 streams and up
to 8 values per stream) are in `scripts/testu01_bigcrush.jl`.

## Running BigCrush

The **BigCrush** battery is much more stringent and takes several hours per generator (typically 8 to 12 hours depending on the CPU). Because of this, it is not run during regular CI.

A standalone script is provided in the repository to run the BigCrush validation suite.

### Instructions

1. Open a terminal in the root of the `RandomDataStreams.jl` repository.
2. Ensure you have the test dependencies installed (the script will activate the `test` environment automatically).
3. Run the script using `nohup` or `tmux`/`screen` so it doesn't stop if you disconnect:

```bash
# Run in background and save results to a text file
nohup ./scripts/testu01_bigcrush.jl > bigcrush_results.txt 2>&1 &
```

You can tail the log file to see the progress:
```bash
tail -f bigcrush_results.txt
```

*Note: Once you have run the BigCrush script, you can include the resulting `bigcrush_results.txt` summary below this section.*
