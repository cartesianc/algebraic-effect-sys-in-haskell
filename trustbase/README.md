# Promoted TrustBase core

This directory is maintenance state, not a business authoring surface and not
part of the materialized framework source closure.

- `current.json` selects the active rotating framework core.
- `core-manifest.json` is the selected core's content-addressed manifest.
- `promotion.approved.json` is the explicit maintainer decision bound to the
  semantic, artifact, and EmptyBusiness evidence digests.
- `promotion.pending.json` preserves the pre-decision record.
- `core0-manifest.json` is the previous genesis core retained for audit and
  rollback.
- `core1-manifest.json` is the immediately previous approved core retained for
  audit and rollback; the active core must not depend on it.
- `core1-source.json` binds the approved core1 payload to the exact source
  commit and legacy framework/observation digests required for core1 replay.
- `core2-source.json` binds the current L0 core2 artifact, framework payload,
  and semantic observation to the exact committed source used for replay.
- `evidence/core1/` preserves the core0 -> core1 promotion evidence.
- `evidence/core2/` preserves the L0 core1 -> core2 replay, semantic,
  fixed-point, and promotion evidence.

The current core is `core2`. Future rounds must use core2 as the previous core,
produce a separately identified candidate (for example core3), pass the same
semantic and artifact gates, and receive a new explicit approval. Editing only
`current.json` is not a valid promotion.
