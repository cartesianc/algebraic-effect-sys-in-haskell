# Runtime execution boundary

## v5.2 unified Runtime

`MyFramework.Runtime.V52` executes an `ElaboratedProgram` through separate AST,
InputGraph, and ValueGraph projections. It also consumes `ContinuationPlan`,
`HookPlan`, `LoopPolicyRegistry`, and `ControlPolicyRegistry`.

Choice records the selected child. Wait and Suspense call `RuntimeControlHooks`
with an immutable live `RuntimeSnapshot`; the result is Ready, Blocked, or
Failed. Context accepts a registered versioned identity. Unknown Context values
fail during `program` construction, before Handler IO. Control hook closures and
snapshots never enter the serialized program.

Hanging middleware compiles into a detached HookPlan and cannot create a boot
root. Callback patches are transactional and run-local. Loop replay is bounded
by its versioned policy and semantic equivalence.

## v2 migration Runtime

`MyFramework.Runtime` is framework-author tooling over an already lowered
application. It is not a serializable authoring surface.

The following contract applies to `MyFramework.Runtime`. `prepareRuntime`
accepts only a `LoweringResult`, rejects the complete error
set, and returns an opaque `RuntimeProgram`. A valid program contains exactly
one executable boot Control tree. Non-empty `hanging` and every `Context` node
are rejected before a demand graph, Control plan, runtime layout, or diagnosis
can be executed.

`runRuntimeProgram` creates a fresh `BootRunId` and single-flight coordinator.
The interpreter can mint an internal `ExecutionPermit` only while visiting a
validated `ControlDemand`. The permit binds:

```text
BootRunId
AstPath
root DemandNodeId
```

The demand evaluator propagates that permit through the exact prerequisite
closure. Each actual R/C/U/D/E handler invocation additionally records the
actual demand node and `HandleId`. A registered handler outside the boot
closure remains `Unused` and has no runtime event.

The public Handler module exposes construction, registration, codecs, and
contract validation only. `invokeCude`, `invokeRead`, `ExecutionPermit`, and
the permit mint function are hidden package internals. The public CURDE
language has no `OperatorRef`, `applyOperator`, or `PureOperatorRegistry`;
business transformations are R Facts in the unified EffSys.

Runtime hooks implement wait, suspense, middleware, callback, and loop
behavior. There is no Context hook and no pure-operator hook. The internal
demand callback cannot be replaced by a caller, and no default hook silently
ignores an explicit executable AST node.

The result contains the final immutable snapshot, the control result, and a
pure diagnosis overlay. Diagnosis does not mutate execution history or trigger
replay. Observation unavailability marks producer validity as `Suspect` while
preserving `ExecutionSucceeded`; an R failure remains a separate read channel.
Race cancellation with no final loser snapshot is reported as settlement
uncertainty instead of being accepted as safe success.

The v2 migration Runtime does not add retry, idempotency, transaction,
compensation, `ana`, `hylo`, protocol-driven unfolding, Context, or hanging
listener semantics.

Focused gates:

```powershell
stack build
stack exec curde-semantics-witness
stack exec curde-runtime-witness
.\scripts\check-ast-execution-boundary.ps1
```

These gates do not promote or replace the current core.
