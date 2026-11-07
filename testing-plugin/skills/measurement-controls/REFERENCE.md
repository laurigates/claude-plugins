# Measurement Controls - Reference

Supporting checks for [SKILL.md](SKILL.md). Each section names the law in
SKILL.md it extends.

## The instrument is an arm too

Extends SKILL.md § 1. The measuring instrument can differ between arms, or be
broken in a way that still produces numbers.

- **Select the subject by content, not coordinates**, and print the size of
  the selection (a mask's pixel count, a row filter's match count). A
  fixed-coordinate probe measures a different subject once the arms differ in
  composition. Measure over the exact span the change touches.
- **Interleaved data flattened is N× too long.** Packed multi-channel audio
  (or any interleaved buffer) read as one flat array is `channels` times the
  true length. Branch on the format's own layout flag (planar vs packed), never
  on the array's shape. The tell is a duration that is an exact small multiple
  of the true one.
- **Run mutation controls without bytecode caches** (`python3 -B`): a
  same-size edit in the same second can reuse a stale `.pyc`, so the mutation
  never runs.
- **Stage the whole directory and leave `PYTHONPATH` unset.** A sibling
  module's `sys.path.insert(0, parent)` rebinds imports to the unmutated
  source. Keep a META row (a hard-wired `raise` in the mutated file): if it
  stays green, the harness is not running the edited file.
- **Never run a source-mutating experiment concurrently with a test sweep.**
  Before believing a gate failure, check whether an experiment is in flight.
- **An empty parse of a non-empty input is an error, not a result.** Run the
  probe on a known-good input first. Watch for verbosity flags (`-v error`,
  `-q`) that empty the very stream being parsed.
- **Rates are octave-ambiguous.** A frequency or tempo estimator can lock onto
  half or double the true value. Print the candidate peaks, discriminate with a
  different estimator, and check against the requested value.
- **A result cache makes an A/A′ pair vacuous**: the second run returns the
  first run's output. Disable the cache, or gate on wall time: a re-run under
  half its twin's time is VACUOUS.

## Build-time checks that silently cannot fail

Extends SKILL.md § 1.

- **The check and the checked drawing from the same source**: a
  self-referential set, a constant tested against a list built from it, text
  the generator itself emits. Scan the authored input, never the assembled
  document.
- **An earlier check masking the one under test.** When mutating to prove a
  check fires, read the failure message to see which check fired, and rebuild
  derived state after mutating a table.
- **Covered by an unreachable option is not covered.** Count only the options
  a normal run executes, and pair the coverage check with a partition check.
- **A fix that makes the check a tautology**: say so in the check's comment and
  move the mutation control to the new load-bearing check.

## More ways a control lies

Extends SKILL.md § 1.

- **A test that re-implements its subject cannot fail.** Call the function
  under test over a fabricated fixture; never recompute the expected value the
  same way the code does.
- **A control that cannot pass** is the same defect with the other sign. Judge
  only the arms actually exercised and name the rest. Prefer widening the input
  to lowering the bar, and mutation-test both directions.
- **Ground truth comes from the artifact's own record** (a plan file, a
  manifest, a lockfile), not the current tree. Refuse on mismatch.
- **Byte-identical intermediates across arms** mean the probe measured
  something the arms share. Compare raw measurements before verdicts.

## Locating and calibrating

Extends SKILL.md § 4.

**Calibrate with an injected signal, and read its convention.** Before
believing an estimator, feed it a known magnitude and check it comes back.

- A control that returns the expected value only for the null case proves
  nothing: `1.000` in, `1.000` out is also what a hard-coded `return 1.0` does.
- Check the **sign and direction** of what comes back, not only its magnitude.
  An estimator that returns `0.971` for an injected `1.03` is reporting the
  inverse convention (`1/1.03`), not failing.
- Once calibrated, trust the null reading. A true null rules out a whole family
  of theories.

**Control-test the arm that fails, not the one that passes.** When some runs
fail and a hand-submitted neighbour succeeds, the success is the one arm that
works. Reproduce the failing case, and read the error **body**: client
libraries often discard it in the exception (an HTTP 400 naming the invalid
parameter value, for example).

**Diff structured documents by identity, not by position.** A positional diff
of a list reports every later element as changed after one insertion. Key on
each record's id; a diff that reports 85 changes for 3 real ones stops being
read.

## Where each law bites outside media

| Law (SKILL.md section) | Also bites in |
|---|---|
| § 1 arms differ only in the variable | Any artifact that embeds its inputs: build stamps, PDF metadata, archive mtimes, log headers |
| § 3 grouping artifact | Per-line or per-frame metrics pooled across runs; "X correlates with quality" over files of unequal size, age or type; benchmarks pooled across machines; timings pooled across warm and cold runs |
| § 4 locate by content | Probes keyed on a computed offset: byte positions in a file format, row offsets after a join, timestamps from a nominal rate, an index into a paginated result. Sampling a long artifact for a local defect: log tails, sampled migration rows, a few API responses, spot-checked files in a bulk rename |
| § 5 the user's verdict | Any perceptual output (video, audio, UI, generated text) where the evaluator scores one modality and the user perceives several fused; a headline metric chosen because it was easy to automate |
| § 6 own stem | Audio stems where buses overlap (dialogue under score, a bed under a sting); diff-based placement checks over composited image layers; a telemetry metric summing several producers; any A/B whose arms are measured after being merged into one artifact |
| § 7 per-stream guarantee | Media remux or concat with stream copy; archive copies that keep contents and drop modes, xattrs or symlinks; database migrations transactional for rows but not sequences or constraints; `git cherry` and `merge-tree`, which answer about patch content and not file modes or filter-rewritten line endings; serialisation round-trips that lose key order, precision, or null-vs-absent |

Media-specific traps from the same source:

- **A stream copy can drift audio while video stays exact.** Compressed audio
  frames quantise each segment's audio up to a frame boundary, and a concat
  demuxer can re-insert encoder priming at every join, so each join lands
  later than the last. Copy video byte-for-byte, decode audio, cut it to each
  segment's video duration, concatenate as PCM and encode once.
- **A filter-graph output label is consumable once.** In ffmpeg, feeding one
  labelled output to both the summed mix and a per-layer stem fails with
  `matches no streams`; build per-layer stems in their own passes.

## Provenance

The dated instances behind each law (attribution experiments, seam
measurements, stem checks, concat drift) are recorded in the
laurigates/comfyui-nodes repository, where these laws were first written as
path-scoped rules.
