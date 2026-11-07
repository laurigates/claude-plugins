# Process-Match Traps

## `pgrep -f` matches its own shell wrapper

`pgrep -f <pattern>` matches against **full command lines**, and the shell the
agent runs it from carries the pattern in *its* command line. The check matches
itself whether or not the target process exists. Two failures follow, pointing
in opposite directions:

| Use | Symptom |
|---|---|
| `until ! pgrep -f 'x'; do sleep N; done` | **Never exits.** The loop's own wrapper satisfies the condition, so the wait runs to its timeout and no completion notification fires |
| `pgrep -f 'x' && echo RUNNING` | **False positive.** Reports the job alive after it has finished |

> Observed 2026-08 on a 100-minute GPU sweep: the watcher hung silently, and a
> manual `pgrep -f '<job name>'` printed `STILL RUNNING` while the job's log
> already read `48/48 cells`. The log was right and the process check was wrong.

### The tell

**A completion log that contradicts a liveness check.** Don't pick a side;
print what matched:

```sh
pgrep -af 'myjob'
# 699812 /bin/zsh -c ... eval 'until ! pgrep -f '"'"'myjob'"'"' ...
```

A `/bin/zsh -c ... eval` (or `bash -c`) line containing your own pattern *is*
the false match. This is the control test for this trap: one `pgrep -af` shows
what the negative or positive was made of.

### The fix

Match the **executable**, not the whole command line, so a shell wrapper cannot
satisfy it:

```sh
# Wrong: matches its own wrapper
pgrep -f 'myjob.py'

# Right: real processes only, wrappers excluded
ps -eo pid,comm,args --no-headers | awk '$2 ~ /^python/ && /myjob\.py/ {print}'
```

Other reliable forms:

- **`pgrep -x <comm>`** when the process name alone identifies it.
- **Hold the PID.** `nohup cmd & echo $!`, then `kill -0 <pid>` or wait on that
  exact PID. Immune to pattern matching; the best option when you launch the
  job yourself.
- **Watch the artifact, not the process**: poll for the sentinel the job writes
  on completion (a final log line, a manifest, an exit-code file). It cannot
  self-match.
- **Let the harness own the lifecycle.** Run the job with
  `run_in_background: true` and let the completion notification fire; reach for
  a hand-rolled watcher only for a process the harness did not start.
