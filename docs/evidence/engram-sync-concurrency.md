# Engram sync exclusion

A controlled exporter reproduced overlapping writes to the same sync checkout
on `1e8f1f5`. The original concurrency fixture only checked that a branch survived;
that did not establish exclusion or safe publication.

The official hook now acquires a nonblocking kernel lock before selecting or
creating its checkout. The key is the repository basename, covering the cold-start
collision between different origins with the same name. Other basenames remain
independent. Locks live outside the checkout-name namespace, under
`~/.engram/git-sync-locks/`; file existence is not evidence of a live lock.

The shell retains fd 9 and descendants inherit it. The lock is released by the
kernel when its last descriptor closes, not by deleting a PID file. Never unlink
these lock files: a replacement inode could allow two owners. Lock errors or
contention do not run the sync body; they log unavailable/deferred rather than
success. Python3/fcntl support is required for this macOS/Linux hook path.

A deferred call does NOT schedule an automatic worker. Local Engram remains the
durable source; publication waits for a subsequent normal hook or manual retry.
There is no immediate remote-durability guarantee, fairness guarantee, stale Git
index-lock cleanup, or claim about tools that deliberately close inherited fds.
This avoids indefinite waits without adding an unbounded background retry loop.

Installation requires observed quiescence of predecessor sync processes, including
their Git/export descendants. An already-running old hook does not acquire this
lock: a mixed-version fixture confirmed overlapping exporters. Do not terminate
unrelated owners; defer rollout until their work finishes. Replace the installed
hook atomically and record the observation and backup. A process snapshot is not
a race-free launch barrier; exclusion applies only to cooperating new hooks.

The lock namespace assumes a trusted HOME and stable lock inodes. Fresh paths
are private (directory 0700, file 0600), but existing ownership/modes are not
changed or certified. The inode check detects replacement before acquisition,
not later unlink/replacement by another actor. This is process coordination, not
a security boundary against another writer able to modify the user HOME.

Disposable tests cover same-checkout exclusion/retry, cold same-name origins,
independent names, pull versus export, inherited ownership after fixture-parent
termination, pre-bootstrap exclusion, symlink refusal, and unavailable lock runtime. No live process was
terminated and no real remote was used by these fixtures. Rollback is this work
unit plus restoration of its scoped installed hook/test originals.

Separate cmux diagnosis found no application process or socket listener, with
stale endpoint artifacts. Start cmux normally before a live communication probe;
do not delete sockets or weaken access policy. This change does not certify peers.
