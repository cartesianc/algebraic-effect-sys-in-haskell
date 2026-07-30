# myframework

`myframework` is the source repository for the CURDE framework compiler and
runtime.

## L0 semantic authority

The frozen highest-level frontend contract is
[`docs/L0_REFERENCED_AST_SEMANTICS.zh.md`](docs/L0_REFERENCED_AST_SEMANTICS.zh.md).
If source code, internal IR, witnesses, examples, or another document conflicts
with that contract, the L0 document wins and the conflict is implementation
debt.

The L0 model is a referenced hierarchy: declarations such as
`chain app [a, b]` and `parallel a [a1, a2]` are independently addressable
module/control nodes. Effects are registered per module, their record keys are
their local identities, and R is a separate lazy typed data domain. UI and
runtime resolve the hierarchy on demand instead of requiring one fully nested
Blueprint.

The root SDK facade, self-model, SDK source artifact, runtime resolver, and
promoted core now use the L0 referenced-program contract. Legacy CURDE/AST
modules remain compiled as an internal migration and compatibility surface;
they are not re-exported by `MyFramework` and do not override L0.

## Repository boundaries

- `myframework` is the semantic source.
- `dsl-bootstrap` is a migration reference and behavioral oracle.
- `dsl-sdk` is generated output. It is never edited as a semantic source.
- TrustBase contracts migrate as pure schema, evidence, manifest, and
  fixed-point validation code. Release promotion is a separate operation.

## Current self-bootstrap status

The implementation now contains both required fixed points:

- content-addressed approved-`core2` replay plus the L0 v2
  `core0 -> FrameworkAsBusiness -> EmptyBusiness` semantic bridge;
- Stage1/Stage2 source and evidence reproducibility.

`TrustBaseRef`, existential `BoundTrustBase`, the closed `HostKernel`, explicit
promotion records, current-core pointers, approved-core SDK locks, and a
standalone `sdk-lower` package materializer are part of the same source
closure. Focused semantic, binding, promotion, and SDK package witnesses must
all pass before release validation starts.

Promotion is still deliberately separate from validation. A candidate is not
the current core until the heavy self-artifact gate passes and a maintainer
explicitly approves its pending promotion record. Only that approved core may
feed the beta SDK workflow. Ordinary architecture changes invalidate previous
source digests and are not promoted merely because local semantic witnesses
pass.

The repository current pointer selects the explicitly approved façade-epoch
`core0` artifact. Approved `core2` is retained as content-addressed replay and
rollback evidence and is not an active runtime dependency of core0.

Business authoring imports only `MyFramework`. The executable crawler witness
proves the public façade can directly write:

```haskell
chain crawler [fetch, extract, persist]
fallback fetch [primary, mirror]
parallel extract [links, content]
chain persist [page, links]
```

## Build policy

Development batches related semantic changes before compiling. Focused
semantic evidence is added with the implementation, but expensive release and
self-artifact promotion gates are not part of ordinary iteration.

```powershell
stack --work-dir .stack-work-codex build
stack --work-dir .stack-work-codex exec curde-semantics-witness
stack --work-dir .stack-work-codex exec crawler-facade-witness
stack --work-dir .stack-work-codex exec curde-runtime-witness
.\scripts\check-ast-execution-boundary.ps1
```

See `docs/L0_REFERENCED_AST_SEMANTICS.zh.md` for the frozen semantic boundary.
`docs/ARCHITECTURE.md` maps the current implementation and is subordinate to
the L0 contract.

The approved-core SDK lowering boundary is documented in
`docs/SDK_SOURCE_ARTIFACT.md`. Its current migration representation must
eventually lower the L0 referenced-module surface without introducing another
authoring facade.

The runtime compiler/executor boundary is documented in `docs/RUNTIME.md`.
It consumes a validated lowering result and is not another authoring facade.
