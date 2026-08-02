# Semantic self-bootstrap and artifact gate

The repository has two independent fixed-point obligations. Neither substitutes
for the other.

## Semantic closure

```text
Host TCB
  -> content-addressed replay of approved core2
  -> compatibility facet bound to the approved L0 v2 current core
  -> v5.2 FrameworkAsBusiness expressed through MyFramework.Facade
  -> EmptyBusiness
  -> normalized core2/core0 compatibility observations
```

`check-core2-replay.ps1` rebuilds the exact source commit bound to approved
core2, reproduces its artifact digest, façade payload digest, and semantic
observation digest. `core-self-interpret-witness` binds that facet to the v5.2
candidate, proves it runs through the same public Facade and unified Runtime
used by business programs, and closes recursion at a zero-Effect `EmptyBusiness`. The normalized
core2/core0 contract is exchangeable and core0 has no runtime dependency on
core2. A
contaminated back-reference is a required negative witness.

## Artifact fixed point

The heavy gate performs:

1. Stage0 materializes Stage1.
2. Stage1 independently builds and runs semantic, runtime, TrustBase,
   self-interpret, promotion, SDK package, self-model, and manifest witnesses.
3. Stage1 materializes Stage2.
4. Stage2 independently repeats the same witness set.
5. Stage1 and Stage2 source manifests reach a byte-stable fixed point.
6. Collected semantic/runtime evidence reaches a fixed point.
7. Corresponding Stage0/Stage1 and Stage1/Stage2 reports are byte-equal.
8. The promotion tool creates and verifies a core0 candidate manifest and a
   `PromotionPending` record whose previous core is the approved core2.

Only `artifactSourceFiles` enter a materialized artifact. Each is classified as
reproduced source or an explicit trusted seed and receives a SHA-256 digest.

## Commands and status

Ordinary release validation:

```powershell
.\scripts\check-release.ps1
```

Passing it means `ready for self-artifact gate`.

One-shot heavy validation for an exact worktree fingerprint:

```powershell
.\scripts\check-release.ps1 -IncludeSelfArtifact
```

The marker prevents an accidental repeat on the same fingerprint. Timeout is
inconclusive. Passing means `self-artifact passed`, not `promotion approved`.

## Promotion separation

Validation never modifies `trustbase/current.json`. After the heavy gate, a
maintainer reviews the generated core manifest, pending record, TrustBase
classification, diff, and evidence. Only the explicit `core-promotion-tool
approve` command can produce an approved record and matching current pointer.
The repository contains an approved v2 current core. The v5.2 pointer remains
unchanged until its Stage 10 heavy gate and explicit approval complete.

A beta SDK additionally requires those reviewed files and independently checks
that the approved core artifact digest is the payload it packages. CI cannot
turn a pending candidate into a current core.
