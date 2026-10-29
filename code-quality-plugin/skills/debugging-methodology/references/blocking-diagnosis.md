# Blocking Diagnosis — Off-CPU Waits and Lock Queues

Open when a workload is slow but not CPU-bound: wall time grows while user time
does not, system time rises, or adding threads stops helping. A CPU profiler
(`perf record`, flame graphs) samples running threads, so time spent asleep
does not appear in its output. Steps 1–3 find where threads
sleep; step 4 confirms which lock they queue on.

Linux only: steps 2 and 3 read `/proc` and kernel tracepoints. Run every step
against a **control** — the same workload with the suspect feature off — because
idle waits (thread-pool workers parked on a futex, an event loop in `epoll_wait`)
show up in both and must be discounted.

## 1. Cheap first signal — context switches and system time

```bash
/usr/bin/time -f "%e wall %U user %S sys vol=%w invol=%c" <cmd>
```

GNU `time`, not the shell builtin. `%w` counts **voluntary** context switches
(the thread gave up the CPU to wait for something), `%c` **involuntary** ones
(the scheduler preempted it). A voluntary count that jumps by orders of
magnitude against the control, with system time up and user time flat, means
the extra time is blocking in the kernel rather than computing.

## 2. Where threads wait — `wchan` sampling, no root needed

`/proc/<pid>/task/<tid>/wchan` names the kernel function a sleeping thread is
waiting in; the first field after the parenthesised name in
`/proc/<pid>/task/<tid>/stat` is its state (field 3, but the name may contain
spaces, so the script splits on the closing parenthesis). Sample every
thread every few milliseconds while the workload loops, keep only blocked
threads, and histogram:

```bash
#!/usr/bin/env bash
# Histogram the kernel wait functions of a command's blocked threads.
# Usage: wchan-sample.sh <seconds> <cmd> [args...]
set -u
duration=$1; shift
( end=$((SECONDS + duration)); while [ $SECONDS -lt $end ]; do "$@" >/dev/null; done ) &
runner=$!
samples=$(mktemp)
end=$((SECONDS + duration))
while [ $SECONDS -lt $end ]; do
    for pid in $(pgrep -P "$runner"); do
        for t in /proc/"$pid"/task/*; do
            state=$(sed 's/.*) //; s/ .*//' "$t/stat" 2>/dev/null) || continue
            case $state in S|D) echo "$(cat "$t/wchan" 2>/dev/null) $state" ;; esac
        done
    done >>"$samples"
    sleep 0.002
done
wait "$runner"
echo "blocked-thread samples: $(wc -l <"$samples")"
sort "$samples" | uniq -c | sort -rn | head -12
rm -f "$samples"
```

Reading the histogram:

- **State `D`** (uninterruptible) is a wait on I/O or a kernel sleeping lock
  (`down()`, a mutex, a buffer lock). A `D` entry absent from the control is
  the lead.
- **State `S`** (interruptible) is usually a futex, poll or pipe wait. Entries
  present in both runs at similar counts are idle workers; discount them.
- `wchan` names only the innermost function. Step 3 gives the full stack.

`wchan` was readable by the process owner on kernel 6.17 with
`kernel.kptr_restrict=1` and `kernel.perf_event_paranoid=2`, with no `perf`
installed. Other kernel configurations are unverified.

## 3. Full off-CPU stacks — bpftrace, root needed

Count kernel stacks at the moment a thread of the process enters
uninterruptible sleep (`prev_state == 2` is `TASK_UNINTERRUPTIBLE`; use `1` for
interruptible waits):

```bash
sudo timeout -s INT 6 bpftrace -q -e '
tracepoint:sched:sched_switch /args->prev_comm == "<comm>" && args->prev_state == 2/ {
    @[kstack(30)] = count();
}
END { print(@, 4); clear(@); }'
```

- **Use a deep stack.** A shallow `kstack(10)` can stop at the lock primitive,
  below the frames that say why the lock was taken. `kstack(30)` reached the
  syscall in the [worked example](#worked-example--fiemap-on-reflinked-xfs).
- `<comm>` is the thread name, truncated to 15 characters. Threads the program
  names itself (worker pools often do) carry their own `comm`; filter on
  `pid == <PID>` instead when the process is long-lived.
- bpftrace 0.14 (Ubuntu 22.04) failed on this script with
  `ERROR: Could not resolve symbol: /proc/self/exe:END_trigger`; 0.20.2
  (Ubuntu 24.04) ran it.

## 4. Confirm the lock — the queue signature and two decisive tests

A lock queue has a scaling signature: throughput rises with threads until the
lock saturates, then goes flat or drops. Sweep the thread count on both the
slow path and the control; a slow path that flattens early while the control
keeps scaling points at a shared lock.

Two tests turn the suspicion into a finding:

1. **Remove your own locks first.** Replace the program's mutexes on the hot
   path (a thread-local cache, a lock-free structure) and re-measure. Unchanged
   voluntary context switches and wall time put the lock outside the program.
2. **Change the suspected lock's count.** If the stack names a lock that exists
   once per partition (per allocation group, per shard, per bucket), rerun on
   the same data with more partitions. A wait that shrinks with the partition
   count is that lock.

Report each comparison with its run-to-run spread, and treat a difference
inside the spread as no difference.

## Worked example — FIEMAP on reflinked XFS

> Observed 2026-10 (`dust --shared-blocks`, which calls `ioctl(FS_IOC_FIEMAP)`
> per file): on reflinked XFS the feature ran 5–8× slower than without it.
>
> 1. `/usr/bin/time`: ~150,000 voluntary context switches per run against
>    ~2,000 without the feature; system time 3.0 s against 0.8 s.
> 2. `wchan` sampling: 646 of 1,356 blocked-thread samples were
>    `xfs_buf_lock` in state `D`. The control had none; its only frequent entry
>    was rayon's idle workers in `futex_do_wait` (state `S`), present in both.
> 3. bpftrace `kstack(10)` stopped at `xfs_buf_find_lock`. `kstack(30)` showed
>    FIEMAP → `xfs_reflink_trim_around_shared` → `xfs_reflink_find_shared` →
>    `xfs_alloc_read_agf` → `xfs_read_agf` → … → `xfs_buf_lock` → `down()`, at
>    730,556 samples against 47 for the next stack.
> 4. Thread sweep: the baseline sped up 7.1× from 1 to 24 threads, the FIEMAP
>    path only 2.7×, flat after ~6 threads. On a 4-AG filesystem, 8 threads
>    were slower than 4 (513 vs 419 ms). Replacing dust's one mutex with a
>    thread-local cache left context switches and wall time unchanged (a 7%
>    difference inside the ±69 ms run spread). The same data on XFS with
>    `agcount=32` instead of 4 cut the run from 506 to 275 ms and voluntary
>    context switches from 67,089 to 4,230.
>
> Each shared-extent lookup reads the allocation group's AGF header buffer under
> its buffer lock, and there is one AGF per allocation group, so the threads
> queued on four locks.
