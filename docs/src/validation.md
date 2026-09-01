# Statistical Validation (TestU01)

`RandomDataStreams.jl` integrates seamlessly with [TestU01](http://simul.iro.umontreal.ca/testu01/tu01.html), the industry-standard C library for empirical statistical testing of RNGs, via the `RNGTest.jl` wrapper.

The validation is deliberately split in two. The **package test suite** runs
SmallCrush only, over three suites, and answers the question "does this
installation work" in about three minutes. **Crush and BigCrush run on demand**
through `scripts/testu01/validate.jl`, because they take hours to days; see the
last section.

## In the test suite: SmallCrush

A subset of the TestU01 batteries, **SmallCrush**, is automatically executed on all supported generators (`MRG32k3a`, `MRG63k3a`, `Xoshiro256+`, `PCG64`, `PCG64DXSM`, `Philox4x32-10`, `Philox4x64-10`, `Threefry4x64-20` and `Threefry4x32-20`) during the standard test suite. You can trigger this locally by running:

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
for each of the nine generators. For a counter-based generator this is what
exercises the key schedule: a schedule handing out structurally related keys
shows up here and not in a battery run on a single stream.

The heavier configurations recommended by the paper (up to 1024 streams and up
to 8 values per stream) are in `scripts/testu01_bigcrush.jl`.

### Platform limitation

The batteries do not run on **Apple Silicon**. RNGTest hands TestU01 its
callback through `@cfunction($f, ...)`, which needs an executable trampoline
for the closure, and macOS on aarch64 forbids memory that is both writable and
executable — Julia raises `cfunction: closures are not supported on this
platform`. This affects every generator and every battery, and is a property of
the platform rather than of any package here.

The test suite probes the capability and skips the three batteries with a
message when it is missing, so the rest of the suite still runs; the on-demand
harness refuses with the same explanation. Everything else in the suite,
including the reference vectors, runs everywhere.

## The integer paths, at the bit level

The Crush batteries examine the 30 most significant bits of the `U(0,1)`
outputs, so a battery run on the float says nothing about how a generator
builds a machine integer. Where the integer *is* the native output — Philox
4x32, Threefry 4x32 — that is the same stream. Where it is a construction, it
needs testing for itself, and `test/test_bits.jl` runs SmallCrush on the bit
stream of: `MRG32k3a` in `UInt32` and in `UInt64` (16-bit chunks of a
non-power-of-two modulus), `MRG63k3a` in the same two types (32-bit chunks of
the same construction, with a modulus just under 2^63), the 64-bit
counter-based families in `UInt32` (the low half of a cipher word), `PCG64` and `PCG64DXSM` in `UInt32` (the low bits
of a permuted output -- DXSM ends in a multiplication, whose low bits depend on
fewer input bits than its high ones), and `Xoshiro256+` in `UInt32` (the low bits of an
additive scrambler).

This battery earns its place: a `UInt64` construction for MRG32k3a that passed
every `U(0,1)` battery failed here with six p-values at zero. Note also that
passing does not clear the lowest bits of the `+` scramblers, whose linear
weakness Blackman & Vigna document and SmallCrush does not resolve.

## Running Crush and BigCrush

These are **not** part of `Pkg.test()` and must not become part of it. The
package test suite answers "does this installation work", and SmallCrush at
about a minute per battery is the most that belongs there. Crush takes hours
and BigCrush the better part of a day per generator: that is a validation
exercise, for a release or for a paper, not an installation check.

`scripts/testu01/validate.jl` runs any battery over any of the three suites, on
demand:

```bash
# what would run, without running it
julia scripts/testu01/validate.jl --list --battery=bigcrush --suite=all

# one generator, one battery, one suite
julia scripts/testu01/validate.jl --battery=crush --generator=Xoshiro256p --suite=bits

# the full single-stream sweep
julia scripts/testu01/validate.jl --battery=bigcrush --suite=single
```

| option | values | default |
|---|---|---|
| `--battery` | `smallcrush`, `crush`, `bigcrush` | `smallcrush` |
| `--suite` | `single`, `interleaved`, `bits`, `all` | `single` |
| `--generator` | a generator name, or `all` | `all` |
| `--streams`, `--values` | shape of the interleaved suite | 64, 1 |
| `--out` | directory for logs | `testu01-results` |
| `--list` | print the plan and exit | |
| `--quiet` | summary only, no per-test reports | |

Each run writes TestU01's own report to its own log and appends a line to
`summary.tsv` with the battery, suite, generator, wall time, Julia version and
CPU. Per-test reports are on by default: they are the canonical artefact to
archive, and they make a long run observable — the log fills as tests complete,
so progress can be followed with `tail -f` and an interrupted run still leaves
its completed tests behind. Run it under `nohup` or `tmux`:

```bash
nohup julia scripts/testu01/validate.jl --battery=bigcrush --suite=all > run.out 2>&1 &
tail -f testu01-results/bigcrush-*.log
```

## Long campaigns: running for days without a session

`validate.jl` runs one battery in one process, serially. That is the wrong shape
for a BigCrush sweep: the full matrix is 16 generators times 3 suites, 48 runs,
each taking the better part of a day, so a single process means weeks of
sequential work in which one crash loses everything and a lost SSH session ends
the campaign.

`scripts/testu01/campaign.jl` runs the same matrix as independent OS processes:

```bash
# what would run, and what is already done
julia scripts/testu01/campaign.jl --battery=bigcrush --status

# measure one job before committing to the sweep
julia scripts/testu01/campaign.jl --battery=bigcrush --calibrate

# the sweep, six jobs at a time
julia scripts/testu01/campaign.jl --battery=bigcrush --jobs=6
```

`--battery` is required: there is deliberately no default, so that a stray
invocation cannot start a two-week sweep.

**Resuming is the point.** `summary.tsv` records one line per finished
`(battery, suite, generator)`. Re-running the same command skips those and does
the rest, so an interruption costs only the jobs actually in flight — never the
weeks already spent. Each job also writes its own `summary.tsv` in its own
directory, which the driver reconciles, so even a driver killed mid-flight
loses nothing that finished.

**Stopping cleanly.** `touch <out>/STOP` stops new jobs from starting and waits
for the running ones, which is how to end a campaign without discarding a
battery that is twenty hours in. Ctrl-C does the same.

**Surviving logout and reboot.** `nohup` survives a logout, `tmux` survives a
logout and lets you reattach, and neither survives a reboot or restarts a driver
that died. For a campaign measured in weeks, use the systemd *user* unit in
`scripts/testu01/randomdatastreams-campaign.service`:

```bash
loginctl enable-linger $USER          # user services keep running after logout
cp scripts/testu01/randomdatastreams-campaign.service ~/.config/systemd/user/
$EDITOR ~/.config/systemd/user/randomdatastreams-campaign.service   # set paths
systemctl --user daemon-reload
systemctl --user start randomdatastreams-campaign
journalctl --user -u randomdatastreams-campaign -f
```

The unit stops with `SIGINT` and a six-hour stop timeout, so `systemctl --user
stop` lets the driver wait for its children rather than killing them, and
`Restart=on-failure` brings back a driver that died — it resumes from
`summary.tsv` like any other invocation.

### When `enable-linger` is not yours to run

That first line is the one that needs an administrator. Without it, systemd
kills user services at logout, which is exactly what a two-week sweep must
survive. On a shared machine the answer is often "no", so
`scripts/run-campaign.sh` can supervise the campaign with **tmux** instead:

```bash
./scripts/run-campaign.sh run --battery=crush --supervisor=tmux --watchdog
./scripts/run-campaign.sh status --battery=crush      # no flag needed afterwards
./scripts/run-campaign.sh stop   --battery=crush
```

`--supervisor=auto`, the default, uses systemd when linger is on or can be
turned on, and falls back to tmux. The choice is recorded in the output
directory, so `status`, `stop` and `collect` find the campaign without being
told again.

What tmux does not give you is what `--watchdog` restores, through a *user*
crontab entry that needs no privileges:

| | systemd unit | tmux | tmux + `--watchdog` |
|---|---|---|---|
| survives logout | with linger | yes, unless `KillUserProcesses=yes` | same |
| survives a reboot | yes | no | yes (`@reboot`) |
| restarts a driver that died | `Restart=on-failure` | no | yes, within 15 min |
| attach and watch it work | `journalctl -f` | `tmux attach` | `tmux attach` |

Two details the script handles, both of which are silent failures otherwise.
`KillUserProcesses=yes` in `logind.conf` kills a detached tmux session at logout
just as it kills an unlingered service, so tmux is *not* a workaround on such a
machine — `run-campaign.sh` reads the setting and says so before you commit two
weeks to it. And tmux keeps its socket under `/run/user/$UID`, a directory that
is removed when your last session ends; the script points `TMUX_TMPDIR` at a
directory under `$HOME` instead, so the session started from your login shell
and the one the watchdog looks for are the same session.

The watchdog respects `touch <out>/STOP`: a campaign you stopped on purpose
stays stopped. `stop` removes the crontab entry, and any crontab it edits is
backed up to `<out>/crontab.backup` first — your other cron jobs are never
touched.

**Every result names the code that produced it.** `summary.tsv` records the
package version, the commit of `HEAD` and whether the working tree was clean,
alongside the Julia version, the CPU and — for the interleaved suite — the
number of streams and values per stream. Each battery log repeats it in its
header. A campaign started from a dirty tree prints a warning before it begins,
because a run measured in weeks cannot be repeated to find out afterwards which
code produced it. The same line appears at the top of the throughput benchmark's
report.

**Do not benchmark and validate at the same time.** The throughput figures in
the implementation notes are minima over samples on an unloaded machine; a host
running six BigCrush processes will produce numbers that measure the scheduler.
Run `scripts/benchmarks/throughput.jl` first, pinned, then start the campaign.
On a hybrid CPU (Intel 12th generation and later) pin the benchmark to a
performance core with `taskset`; the batteries can use any core, since their
results do not depend on how fast they were produced.

### What still needs BigCrush

Two things the suite cannot settle at SmallCrush level:

- **The low bits of the `+` scramblers.** Blackman & Vigna document the lowest
  bits of `xoshiro256+` and `xoroshiro128+` as linearly weak. SmallCrush does
  not resolve it, so the `bits` suite passing at that level is not a
  clearance; the question needs Crush or BigCrush, and possibly does not show
  even there.
- **Dependence between streams at full strength.** The interleaved suite is
  the construction L'Ecuyer et al. (2021) call for, and the paper says
  batteries for counter-based generators still need development. A SmallCrush
  pass is a smoke test; the claim worth publishing is a BigCrush one.

Results belong in the JOSS submission, not in CI.
