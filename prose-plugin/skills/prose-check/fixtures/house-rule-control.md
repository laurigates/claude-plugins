# House rule control fixture

Do not fix the prose in this file. Every sentence below exists to trip exactly
one House rule, and `scripts/check-prose-house-style.sh` asserts that each rule
fires against it. A rule that matches nothing is indistinguishable from a rule
with nothing to find, which is how `TicketPlaceholder` shipped broken once: its
five `raw:` entries were concatenated into one impossible pattern rather than
OR'd, and the resulting zero alerts read exactly like a clean document.

Every sentence here is long on purpose, because `MeanSentenceLength` measures
the whole file and only reports once the mean crosses its threshold, so a file
of short sentences could never exercise it at all.

It is worth noting that the deployment finished at some point during the
afternoon, which is the thing that determines whether the cache warmed before
the first request arrived at the edge.

The measurement was somewhat inconclusive and it could be said that the sampling
window closed too early, though arguably the operator would have seen the same
number either way given how the collector batches its writes.

This amazing rewrite will revolutionize the ingest path and is incredibly fast,
seamlessly handling the traffic that the previous cutting-edge implementation
dropped on the floor whenever a partition rebalanced under load.

The rollout date is TBD, the owner is [describe the owner], and the migration
step is FIXME, so nobody reading this ticket can actually tell what work it is
asking anyone to do or when that work is supposed to happen.

Basically the collector was essentially idle, and it really did not matter very
much whether the operator restarted it, because the queue drains at the same
rate regardless of how many consumers happen to be attached at that moment.
