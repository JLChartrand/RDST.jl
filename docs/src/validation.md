# Statistical Validation (TestU01)

`RandomDataStreams.jl` integrates seamlessly with [TestU01](http://simul.iro.umontreal.ca/testu01/tu01.html), the industry-standard C library for empirical statistical testing of RNGs, via the `RNGTest.jl` wrapper.

## Continuous Integration (SmallCrush)

A subset of the TestU01 batteries, **SmallCrush**, is automatically executed on all supported generators (`MRG32k3a`, `Xoshiro256+`, and `Philox`) during the standard test suite. You can trigger this locally by running:

```julia
using Pkg
Pkg.test("RandomDataStreams")
```

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
