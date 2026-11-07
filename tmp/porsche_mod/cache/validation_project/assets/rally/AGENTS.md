# rally assets — exported Open Formula content

Scope: Ford chassis, four wheels, Ford collision proxy and Russia Stage 1 visual/collision GLBs with provenance manifests.
Consumers: `game/scenes/rally/` and the isolated Windows export.
Rules: generated, do not hand-edit. Regenerate from the source assets under `D:\open-formula` and update `manifest.json` hashes in the same change. This repository stores derived runtime content, not Python asset-generation scripts.

Subfolders are binary leaves covered by this file. The track collision GLB is split by material class so billboard vegetation never becomes an invisible wall. The Ford collision JSON contains convex hulls and two boxes derived from `body_crash`, not a literal import of the undecoded `collision.BMF`.
