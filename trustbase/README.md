# Promoted TrustBase core

This directory is maintenance state, not a business authoring surface and not
part of the materialized framework source closure.

- `current.json` selects the active rotating framework core.
- `core-manifest.json` is the selected core's content-addressed manifest.
- `promotion.approved.json` is the explicit maintainer decision bound to the
  semantic, artifact, and EmptyBusiness evidence digests.
- `promotion.pending.json` preserves the pre-decision record.
- `core0-manifest.json` is the selected façade-epoch core0 manifest.
- `core1-manifest.json` is an archival pre-L0 core retained for audit.
- `core1-source.json` binds the approved core1 payload to the exact source
  commit and legacy framework/observation digests required for core1 replay.
- `core2-source.json` binds the previous approved L0 core2 artifact, framework
  payload, and semantic observation to the exact committed source used for
  replay.
- `core0-source.json` binds the selected façade core0 to commit, artifact,
  façade payload, and semantic-observation digests for the next bootstrap
  round.
- `evidence/core1/` preserves the core0 -> core1 promotion evidence.
- `evidence/core2/` preserves the L0 core1 -> core2 replay, semantic,
  fixed-point, and promotion evidence.
- `evidence/facade-core0/` preserves the core2 -> façade core0 replay,
  crawler-façade execution, fixed-point, promotion, and SDK evidence.

The current core is the new semantic epoch's `core0`. The historical genesis
core0 is distinguished by its old digest and remains recoverable from git and
the core0 -> core1 evidence; identities are always checked as complete
content-addressed `TrustBaseRef` values, never by the text `core0` alone.
Future rounds must use the current core0 as their previous core, pass the same
semantic and artifact gates, and receive a new explicit approval. Editing only
`current.json` is not a valid promotion.
