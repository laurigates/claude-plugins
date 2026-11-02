# Kernel Reproducer Harness: Reference

The complete harness from the 2026-11 XFS FIEMAP contention report, copied
verbatim from the investigation repository. It reproduced the contention on
OrbStack (7.2.12, aarch64) and on a GCP n2-standard-8 (Ubuntu 24.04,
7.0.0-1014-gcp, x86_64). Adapt the syscall in `fiemap_file()` and the
`mkfs` options for another subsystem; keep the structure.

| File | Role |
|---|---|
| `fiemap-mt.c` | `populate DIR NFILES` builds a deterministic tree; `run DIR THREADS [seq\|shuffle]` times open + FIEMAP + close from N threads and prints context switches |
| `run.sh` | Root-only driver: one loop image per AG count, a never-reflinked control tree and a reflinked tree, medians of RUNS |
| `wait-stacks.sh` | bpftrace D-state stack capture during the repro |
| `repro-vm.sh` | GCP checkpoint: create a VM, copy the harness, run both scripts, fetch logs |

## fiemap-mt.c

```c
// fiemap-mt: dust-free reproducer for XFS FIEMAP contention on reflinked files.
//
//   fiemap-mt populate DIR NFILES      create NFILES small files (4-32 KiB, deterministic
//                                      content) in subdirectories of 1000
//   fiemap-mt run DIR THREADS [ORDER]  list regular files under DIR, then open + FIEMAP
//                                      each one from THREADS threads; print wall time,
//                                      voluntary/involuntary context switches, and
//                                      extent counts
//
// ORDER is `seq` (default: directory order, so concurrent threads work on
// neighbouring files, which XFS keeps in the same AG) or `shuffle` (a fixed-seed
// random order, so concurrent threads usually hit different AGs, closer to a
// parallel tree walker like dust).
//
// The file list is built before timing starts, so the timed section is only
// open/FS_IOC_FIEMAP/close, the calls dust --shared-blocks makes per file.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fiemap.h>
#include <linux/fs.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define NEXT 64

static char **paths;
static size_t npaths, cap;
static atomic_size_t next_idx;
static atomic_long n_ext, n_shared_ext, n_shared_files, n_err;

static void die(const char *what) { perror(what); exit(1); }

static void add_path(const char *p) {
  if (npaths == cap) {
    cap = cap ? cap * 2 : 4096;
    paths = realloc(paths, cap * sizeof(*paths));
    if (!paths) die("realloc");
  }
  paths[npaths++] = strdup(p);
}

static void list_files(const char *dir) {
  DIR *d = opendir(dir);
  if (!d) die(dir);
  struct dirent *de;
  char p[4096];
  while ((de = readdir(d))) {
    if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
    snprintf(p, sizeof(p), "%s/%s", dir, de->d_name);
    struct stat st;
    if (lstat(p, &st)) continue;
    if (S_ISDIR(st.st_mode)) list_files(p);
    else if (S_ISREG(st.st_mode) && st.st_blocks > 0) add_path(p);
  }
  closedir(d);
}

static void fiemap_file(const char *p) {
  int fd = open(p, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NOATIME);
  if (fd < 0) fd = open(p, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) { atomic_fetch_add(&n_err, 1); return; }
  char buf[sizeof(struct fiemap) + NEXT * sizeof(struct fiemap_extent)];
  struct fiemap *fm = (struct fiemap *)buf;
  uint64_t start = 0;
  long ext = 0, shared = 0;
  for (;;) {
    memset(fm, 0, sizeof(*fm));
    fm->fm_start = start;
    fm->fm_length = FIEMAP_MAX_OFFSET - start;
    fm->fm_extent_count = NEXT;
    if (ioctl(fd, FS_IOC_FIEMAP, fm) < 0) { atomic_fetch_add(&n_err, 1); break; }
    if (fm->fm_mapped_extents == 0) break;
    int last = 0;
    for (unsigned i = 0; i < fm->fm_mapped_extents; i++) {
      struct fiemap_extent *e = &fm->fm_extents[i];
      ext++;
      if (e->fe_flags & FIEMAP_EXTENT_SHARED) shared++;
      if (e->fe_flags & FIEMAP_EXTENT_LAST) last = 1;
      start = e->fe_logical + e->fe_length;
    }
    if (last || fm->fm_mapped_extents < NEXT) break;
  }
  close(fd);
  atomic_fetch_add(&n_ext, ext);
  atomic_fetch_add(&n_shared_ext, shared);
  if (shared) atomic_fetch_add(&n_shared_files, 1);
}

static void *worker(void *arg) {
  (void)arg;
  for (;;) {
    size_t i = atomic_fetch_add(&next_idx, 1);
    if (i >= npaths) return NULL;
    fiemap_file(paths[i]);
  }
}

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static void shuffle_paths(void) {
  uint64_t x = 0x2545F4914F6CDD1Dull;
  for (size_t i = npaths; i > 1; i--) {
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    size_t j = x % i;
    char *t = paths[i - 1]; paths[i - 1] = paths[j]; paths[j] = t;
  }
}

static int cmd_run(const char *dir, int threads, const char *order) {
  list_files(dir);
  if (!strcmp(order, "shuffle")) shuffle_paths();
  else if (strcmp(order, "seq")) { fprintf(stderr, "ORDER must be seq or shuffle\n"); return 2; }
  pthread_t *tids = calloc(threads, sizeof(*tids));
  struct rusage r0, r1;
  getrusage(RUSAGE_SELF, &r0);
  double t0 = now_ms();
  for (int i = 0; i < threads; i++)
    if (pthread_create(&tids[i], NULL, worker, NULL)) die("pthread_create");
  for (int i = 0; i < threads; i++) pthread_join(tids[i], NULL);
  double t1 = now_ms();
  getrusage(RUSAGE_SELF, &r1);
  double sys = (r1.ru_stime.tv_sec - r0.ru_stime.tv_sec) * 1e3 +
               (r1.ru_stime.tv_usec - r0.ru_stime.tv_usec) / 1e3;
  printf("order=%s threads=%d files=%zu extents=%ld shared_ext=%ld shared_files=%ld errors=%ld "
         "wall_ms=%.1f sys_ms=%.1f vcsw=%ld ivcsw=%ld\n",
         order, threads, npaths, atomic_load(&n_ext), atomic_load(&n_shared_ext),
         atomic_load(&n_shared_files), atomic_load(&n_err), t1 - t0, sys,
         r1.ru_nvcsw - r0.ru_nvcsw, r1.ru_nivcsw - r0.ru_nivcsw);
  return atomic_load(&n_err) ? 1 : 0;
}

static int cmd_populate(const char *dir, long n) {
  static unsigned char buf[32768];
  uint64_t x = 0x9E3779B97F4A7C15ull;
  char p[4096];
  for (long i = 0; i < n; i++) {
    if (i % 1000 == 0) {
      snprintf(p, sizeof(p), "%s/d%04ld", dir, i / 1000);
      if (mkdir(p, 0755) && errno != EEXIST) die(p);
    }
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    size_t len = 4096 * (1 + x % 8);  // 4-32 KiB
    for (size_t j = 0; j < len; j += 8) {
      x ^= x << 13; x ^= x >> 7; x ^= x << 17;
      memcpy(buf + j, &x, 8);
    }
    snprintf(p, sizeof(p), "%s/d%04ld/f%07ld", dir, i / 1000, i);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) die(p);
    if (write(fd, buf, len) != (ssize_t)len) die("write");
    close(fd);
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 4 && !strcmp(argv[1], "populate")) return cmd_populate(argv[2], atol(argv[3]));
  if ((argc == 4 || argc == 5) && !strcmp(argv[1], "run"))
    return cmd_run(argv[2], atoi(argv[3]), argc == 5 ? argv[4] : "seq");
  fprintf(stderr, "usage: %s populate DIR NFILES | run DIR THREADS [seq|shuffle]\n", argv[0]);
  return 2;
}
```

## run.sh

```bash
#!/usr/bin/env bash
# Dust-free reproducer for XFS FIEMAP contention on reflinked files.
# Run as root on any Linux host with xfsprogs, gcc and loop-device support
# (OrbStack machine, GCP VM, bare metal). Builds an XFS image per AG count,
# fills it with a never-reflinked tree and a tree that has a reflink copy, and
# times multithreaded open+FIEMAP over each.
#
#   sudo repro/run.sh                      # defaults below
#   sudo NFILES=50000 RUNS=3 AGCOUNTS="4 32" THREADS="1 4 8" ORDERS=shuffle repro/run.sh
set -euo pipefail

NFILES=${NFILES:-100000}
RUNS=${RUNS:-5}
AGCOUNTS=${AGCOUNTS:-"4 32"}
THREADS=${THREADS:-$(printf '%s\n' 1 4 8 "$(nproc)" | sort -nu | tr '\n' ' ')}
ORDERS=${ORDERS:-"seq shuffle"}
WORK=${WORK:-/var/tmp/xfs-fiemap-repro}
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
mkdir -p "$WORK/mnt"
gcc -O2 -pthread -o "$WORK/fiemap-mt" "$HERE/fiemap-mt.c"
BIN=$WORK/fiemap-mt

cleanup() { mountpoint -q "$WORK/mnt" && umount "$WORK/mnt"; rm -f "$WORK/xfs.img"; }
trap cleanup EXIT

echo "kernel=$(uname -r) arch=$(uname -m) nproc=$(nproc) $(mkfs.xfs -V) nfiles=$NFILES runs=$RUNS"

# Median of RUNS runs by wall_ms; prints the whole median line.
median_run() {
  local dir=$1 t=$2 order=$3
  for _ in $(seq "$RUNS"); do "$BIN" run "$dir" "$t" "$order"; done |
    awk '{for (i = 1; i <= NF; i++) if ($i ~ /^wall_ms=/) {split($i, a, "="); print a[2], $0}}' |
    sort -n | awk -v m=$(( (RUNS + 1) / 2 )) 'NR == m {$1 = ""; sub(/^ /, ""); print}'
}

for ag in $AGCOUNTS; do
  cleanup
  truncate -s 8G "$WORK/xfs.img"
  mkfs.xfs -q -f -d agcount="$ag" -m reflink=1 "$WORK/xfs.img"
  mount -o loop "$WORK/xfs.img" "$WORK/mnt"
  echo "=== $(xfs_info "$WORK/mnt" | grep -o 'agcount=[0-9]*'), $(xfs_info "$WORK/mnt" | grep -o 'reflink=[0-9]')"
  M=$WORK/mnt
  mkdir "$M/plain" "$M/src"
  "$BIN" populate "$M/plain" "$NFILES"
  "$BIN" populate "$M/src" "$NFILES"
  sync
  cp -a --reflink=always "$M/src" "$M/copy"
  sync
  for tree in plain src; do
    "$BIN" run "$M/$tree" "$(nproc)" >/dev/null   # warm the inode, extent and buffer caches
    for order in $ORDERS; do
      for t in $THREADS; do
        echo "ag=$ag tree=$tree $(median_run "$M/$tree" "$t" "$order")"
      done
    done
  done
done
```

## wait-stacks.sh

```bash
#!/usr/bin/env bash
# Capture D-state (TASK_UNINTERRUPTIBLE) kernel wait stacks of fiemap-mt, 4 threads,
# seq order, on a reflinked 20k-file tree, for agcount 4 and 32. Run as root after
# repro/run.sh has built /var/tmp/xfs-fiemap-repro/fiemap-mt. Installs bpftrace (apt).
set -euo pipefail
command -v bpftrace >/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bpftrace >/dev/null; }
W=/var/tmp/stk; BIN=/var/tmp/xfs-fiemap-repro/fiemap-mt; mkdir -p $W/m
for ag in 4 32; do
  mountpoint -q $W/m && umount $W/m
  truncate -s 8G $W/x.img; mkfs.xfs -q -f -d agcount=$ag -m reflink=1 $W/x.img; mount -o loop $W/x.img $W/m
  mkdir $W/m/src; $BIN populate $W/m/src 20000; sync; cp -a --reflink=always $W/m/src $W/m/copy; sync
  $BIN run $W/m/src 4 >/dev/null
  bpftrace -q -e 'tracepoint:sched:sched_switch /comm == "fiemap-mt" && args.prev_state == 2/ { @[kstack(20)] = count(); }' > $W/out-$ag.txt &
  BP=$!; sleep 3
  for _ in $(seq 10); do $BIN run $W/m/src 4; done | tail -2
  kill -INT $BP; wait $BP || true
  echo "=== ag=$ag top stacks"; tail -60 $W/out-$ag.txt
done
umount $W/m; rm -f $W/x.img
```

## repro-vm.sh

```bash
#!/usr/bin/env bash
# Checkpoint run of repro/run.sh and repro/wait-stacks.sh on a GCP VM with a
# stock Ubuntu kernel. Creates the VM, copies repro/, runs both, fetches logs
# into repro/results/, and leaves the VM running (delete it with the printed
# command, or delete the whole project).
#
#   PROJECT=<bench-project-id> ACCOUNT=<you@example.com> cloud/repro-vm.sh
set -euo pipefail
PROJECT=${PROJECT:?set PROJECT}
ACCOUNT=${ACCOUNT:?set ACCOUNT}
NAME=${NAME:-xfs-repro}
FAMILY=${FAMILY:-ubuntu-2404-lts-amd64}
MACHINE=${MACHINE:-n2-standard-8}
GC=(--project="$PROJECT" --account="$ACCOUNT")
HERE=$(cd "$(dirname "$0")/.." && pwd)

ZONE=
for z in europe-north1-b europe-north1-c europe-north1-a; do
  if gcloud compute instances create "$NAME" "${GC[@]}" --zone="$z" \
      --machine-type="$MACHINE" --image-family="$FAMILY" --image-project=ubuntu-os-cloud \
      --boot-disk-size=30GB --boot-disk-type=pd-ssd --format='value(name,zone.basename(),status)'; then
    ZONE=$z; break
  fi
done
[ -n "$ZONE" ] || { echo "no zone had capacity" >&2; exit 1; }
SSH=(gcloud compute ssh "$NAME" "${GC[@]}" --zone="$ZONE" --quiet)

for _ in $(seq 30); do "${SSH[@]}" --command=true 2>/dev/null && break; sleep 10; done
gcloud compute scp --recurse "$HERE/repro" "$NAME:~/" "${GC[@]}" --zone="$ZONE" --quiet
"${SSH[@]}" --command='sudo apt-get -qq update && sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y gcc libc6-dev xfsprogs bpftrace >/dev/null'

TAG=gcp-$("${SSH[@]}" --command='uname -r')-$("${SSH[@]}" --command='uname -m')
"${SSH[@]}" --command='sudo ~/repro/run.sh' > "$HERE/repro/results/$TAG.log" 2>&1
"${SSH[@]}" --command='sudo ~/repro/wait-stacks.sh' > "$HERE/repro/results/wait-stacks-$TAG.txt" 2>&1
echo "results: repro/results/$TAG.log, repro/results/wait-stacks-$TAG.txt"
echo "delete: gcloud compute instances delete $NAME ${GC[*]} --zone=$ZONE --quiet"
```
