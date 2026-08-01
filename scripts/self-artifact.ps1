param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceRoot
)

$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$generatedRoot = Join-Path $repoRoot ".generated"
$stage1Root = Join-Path $generatedRoot "stage1-framework"
$stage2Root = Join-Path $stage1Root ".generated\stage2-framework"
$markerPath = Join-Path $generatedRoot "self-artifact.marker"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$previousCoreManifest = Join-Path $repoRoot "trustbase\core-manifest.json"
$replayEvidencePath = Join-Path $EvidenceRoot "stage0-core2-core0-replay.json"

function Assert-DirectGeneratedChild {
    param(
        [string]$SourceRoot,
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $expectedParent = [System.IO.Path]::GetFullPath(
        (Join-Path $SourceRoot ".generated")
    )
    $actualParent = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetDirectoryName($fullPath)
    )
    if ($actualParent -ne $expectedParent) {
        throw "refusing artifact cleanup outside $expectedParent`: $fullPath"
    }
}

function Remove-ArtifactRoot {
    param(
        [string]$SourceRoot,
        [string]$Path
    )

    Assert-DirectGeneratedChild $SourceRoot $Path
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Invoke-Checked {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    Write-Host "[self-artifact] $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Captured {
    param(
        [string]$Label,
        [scriptblock]$Command,
        [string]$OutputPath
    )

    Write-Host "[self-artifact] $Label"
    $currentOutput = @(& $Command)
    $currentExit = $LASTEXITCODE
    $outputParent = [System.IO.Path]::GetDirectoryName($OutputPath)
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
    [System.IO.File]::WriteAllText(
        $OutputPath,
        (($currentOutput -join "`n") + "`n"),
        $utf8NoBom
    )
    if ($currentExit -ne 0) {
        throw "$Label failed with exit code $currentExit"
    }
}

function Get-WorktreeFingerprint {
    Push-Location $repoRoot
    try {
        $head = @(git rev-parse HEAD)
        $diff = @(git diff --binary)
        $untracked = @(git ls-files --others --exclude-standard)
        $parts = @($head + $diff)
        foreach ($currentPath in $untracked) {
            $parts += $currentPath
            $parts += [System.IO.File]::ReadAllText(
                (Join-Path $repoRoot $currentPath)
            )
        }
        $bytes = $utf8NoBom.GetBytes(($parts -join "`n"))
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            return (
                [System.BitConverter]::ToString(
                    $hasher.ComputeHash($bytes)
                ).Replace("-", "").ToLowerInvariant()
            )
        }
        finally {
            $hasher.Dispose()
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-FileEqual {
    param(
        [string]$Label,
        [string]$Left,
        [string]$Right
    )

    $leftDigest = (Get-FileHash -Algorithm SHA256 -LiteralPath $Left).Hash
    $rightDigest = (Get-FileHash -Algorithm SHA256 -LiteralPath $Right).Hash
    if ($leftDigest -ne $rightDigest) {
        throw "$Label differs: $leftDigest != $rightDigest"
    }
}

function Assert-Core2ReplayEvidence {
    if (-not (Test-Path -LiteralPath $replayEvidencePath)) {
        throw "core2 -> facade core0 replay evidence is required before the heavy gate"
    }
    $currentReplay = Get-Content -LiteralPath $replayEvidencePath -Raw |
        ConvertFrom-Json
    if (
        $currentReplay.schema -ne "myframework-core2-core0-replay.v1" -or
        $currentReplay.result -ne "passed" -or
        $currentReplay.previousCore -ne "core2" -or
        $currentReplay.candidateCore -ne "core0"
    ) {
        throw "core2 -> facade core0 replay evidence is invalid"
    }
}

$fingerprint = Get-WorktreeFingerprint
if (Test-Path -LiteralPath $markerPath) {
    $previousFingerprint = (
        [System.IO.File]::ReadAllText($markerPath)
    ).Trim()
    if ($previousFingerprint -eq $fingerprint) {
        throw "self-artifact already attempted for this exact worktree fingerprint"
    }
}
[System.IO.File]::WriteAllText(
    $markerPath,
    ($fingerprint + "`n"),
    $utf8NoBom
)

Assert-Core2ReplayEvidence
Remove-ArtifactRoot $repoRoot $stage1Root

Push-Location $repoRoot
try {
    Invoke-Captured "Stage0 materializes Stage1" {
        stack --work-dir .stack-work-codex exec self-artifact-tool -- `
            materialize stage1 $stage1Root
    } (Join-Path $EvidenceRoot "stage0-materialize.json")
    Invoke-Captured "Stage1 manifest verifies" {
        stack --work-dir .stack-work-codex exec self-artifact-tool -- `
            verify $stage1Root
    } (Join-Path $EvidenceRoot "stage1-manifest-verify.json")
}
finally {
    Pop-Location
}

$stage1Evidence = Join-Path $stage1Root ".generated\evidence"
Push-Location $stage1Root
try {
    Invoke-Checked "Stage1 build" {
        stack --work-dir .stack-work-artifact build
    }
    Invoke-Captured "Stage1 semantic witness" {
        stack --work-dir .stack-work-artifact exec curde-semantics-witness
    } (Join-Path $stage1Evidence "semantics.json")
    Invoke-Captured "Stage1 referenced frontend witness" {
        stack --work-dir .stack-work-artifact exec referenced-frontend-witness
    } (Join-Path $stage1Evidence "referenced-frontend.json")
    Invoke-Captured "Stage1 crawler facade witness" {
        stack --work-dir .stack-work-artifact exec crawler-facade-witness
    } (Join-Path $stage1Evidence "crawler-facade.json")
    Invoke-Captured "Stage1 referenced runtime witness" {
        stack --work-dir .stack-work-artifact exec referenced-runtime-witness
    } (Join-Path $stage1Evidence "referenced-runtime.json")
    Invoke-Captured "Stage1 schema elaboration witness" {
        stack --work-dir .stack-work-artifact exec schema-elaboration-witness
    } (Join-Path $stage1Evidence "schema-elaboration.json")
    Invoke-Captured "Stage1 effect application witness" {
        stack --work-dir .stack-work-artifact exec effect-application-witness
    } (Join-Path $stage1Evidence "effect-application.json")
    Invoke-Captured "Stage1 v5.2 facade witness" {
        stack --work-dir .stack-work-artifact exec facade-v52-witness
    } (Join-Path $stage1Evidence "facade-v52.json")
    Invoke-Captured "Stage1 input CPS runtime witness" {
        stack --work-dir .stack-work-artifact exec input-cps-witness
    } (Join-Path $stage1Evidence "input-cps.json")
    Invoke-Captured "Stage1 runtime witness" {
        stack --work-dir .stack-work-artifact exec curde-runtime-witness
    } (Join-Path $stage1Evidence "runtime.json")
    Invoke-Captured "Stage1 TrustBase binding witness" {
        stack --work-dir .stack-work-artifact exec trustbase-binding-witness
    } (Join-Path $stage1Evidence "trustbase-binding.json")
    Invoke-Captured "Stage1 semantic self-interpret witness" {
        stack --work-dir .stack-work-artifact exec core-self-interpret-witness
    } (Join-Path $stage1Evidence "self-interpret.json")
    Invoke-Captured "Stage1 promotion policy witness" {
        stack --work-dir .stack-work-artifact exec core-promotion-witness
    } (Join-Path $stage1Evidence "promotion.json")
    Invoke-Captured "Stage1 approved SDK package witness" {
        stack --work-dir .stack-work-artifact exec sdk-package-witness
    } (Join-Path $stage1Evidence "sdk-package.json")
    Invoke-Captured "Stage1 self model report" {
        stack --work-dir .stack-work-artifact exec self-artifact-tool -- report
    } (Join-Path $stage1Evidence "self-model.json")
    Invoke-Captured "Stage1 TrustBase manifest" {
        stack --work-dir .stack-work-artifact exec self-artifact-tool -- `
            trust-base $stage1Root
    } (Join-Path $stage1Evidence "trust-base.json")
    Invoke-Captured "Stage1 materializes Stage2" {
        stack --work-dir .stack-work-artifact exec self-artifact-tool -- `
            materialize stage2 $stage2Root
    } (Join-Path $stage1Evidence "stage2-materialize.json")
}
finally {
    Pop-Location
}

$stage2Evidence = Join-Path $stage2Root ".generated\evidence"
Push-Location $stage2Root
try {
    Invoke-Checked "Stage2 build" {
        stack --work-dir .stack-work-artifact build
    }
    Invoke-Captured "Stage2 semantic witness" {
        stack --work-dir .stack-work-artifact exec curde-semantics-witness
    } (Join-Path $stage2Evidence "semantics.json")
    Invoke-Captured "Stage2 referenced frontend witness" {
        stack --work-dir .stack-work-artifact exec referenced-frontend-witness
    } (Join-Path $stage2Evidence "referenced-frontend.json")
    Invoke-Captured "Stage2 crawler facade witness" {
        stack --work-dir .stack-work-artifact exec crawler-facade-witness
    } (Join-Path $stage2Evidence "crawler-facade.json")
    Invoke-Captured "Stage2 referenced runtime witness" {
        stack --work-dir .stack-work-artifact exec referenced-runtime-witness
    } (Join-Path $stage2Evidence "referenced-runtime.json")
    Invoke-Captured "Stage2 schema elaboration witness" {
        stack --work-dir .stack-work-artifact exec schema-elaboration-witness
    } (Join-Path $stage2Evidence "schema-elaboration.json")
    Invoke-Captured "Stage2 effect application witness" {
        stack --work-dir .stack-work-artifact exec effect-application-witness
    } (Join-Path $stage2Evidence "effect-application.json")
    Invoke-Captured "Stage2 v5.2 facade witness" {
        stack --work-dir .stack-work-artifact exec facade-v52-witness
    } (Join-Path $stage2Evidence "facade-v52.json")
    Invoke-Captured "Stage2 input CPS runtime witness" {
        stack --work-dir .stack-work-artifact exec input-cps-witness
    } (Join-Path $stage2Evidence "input-cps.json")
    Invoke-Captured "Stage2 runtime witness" {
        stack --work-dir .stack-work-artifact exec curde-runtime-witness
    } (Join-Path $stage2Evidence "runtime.json")
    Invoke-Captured "Stage2 TrustBase binding witness" {
        stack --work-dir .stack-work-artifact exec trustbase-binding-witness
    } (Join-Path $stage2Evidence "trustbase-binding.json")
    Invoke-Captured "Stage2 semantic self-interpret witness" {
        stack --work-dir .stack-work-artifact exec core-self-interpret-witness
    } (Join-Path $stage2Evidence "self-interpret.json")
    Invoke-Captured "Stage2 promotion policy witness" {
        stack --work-dir .stack-work-artifact exec core-promotion-witness
    } (Join-Path $stage2Evidence "promotion.json")
    Invoke-Captured "Stage2 approved SDK package witness" {
        stack --work-dir .stack-work-artifact exec sdk-package-witness
    } (Join-Path $stage2Evidence "sdk-package.json")
    Invoke-Captured "Stage2 self model report" {
        stack --work-dir .stack-work-artifact exec self-artifact-tool -- report
    } (Join-Path $stage2Evidence "self-model.json")
    Invoke-Captured "Stage2 TrustBase manifest" {
        stack --work-dir .stack-work-artifact exec self-artifact-tool -- `
            trust-base $stage2Root
    } (Join-Path $stage2Evidence "trust-base.json")
}
finally {
    Pop-Location
}

Push-Location $repoRoot
try {
    Invoke-Captured "Stage1/Stage2 source fixed point" {
        stack --work-dir .stack-work-codex exec self-artifact-tool -- `
            compare $stage1Root $stage2Root
    } (Join-Path $EvidenceRoot "stage1-stage2-artifact-fixed-point.json")
    Invoke-Captured "Stage0/Stage1 collected evidence fixed point" {
        stack --work-dir .stack-work-codex exec self-artifact-tool -- `
            fixed-point `
            stage0 `
            (Join-Path $EvidenceRoot "stage0-semantics.json") `
            (Join-Path $EvidenceRoot "stage0-runtime.json") `
            $stage1Root `
            stage1 `
            (Join-Path $stage1Evidence "semantics.json") `
            (Join-Path $stage1Evidence "runtime.json") `
            $stage2Root
    } (Join-Path $EvidenceRoot "stage0-stage1-evidence-fixed-point.json")
    Invoke-Captured "core2 -> facade core0 candidate promotion record" {
        stack --work-dir .stack-work-codex exec core-promotion-tool -- `
            prepare `
            $previousCoreManifest `
            core0 `
            $stage1Root `
            (Join-Path $stage1Evidence "self-interpret.json") `
            (Join-Path $EvidenceRoot "stage1-stage2-artifact-fixed-point.json") `
            (Join-Path $stage1Evidence "self-interpret.json") `
            (Join-Path $EvidenceRoot "core0-manifest.json") `
            (Join-Path $EvidenceRoot "promotion.pending.json")
    } (Join-Path $EvidenceRoot "promotion-prepare.json")
    Invoke-Captured "Candidate promotion verification" {
        stack --work-dir .stack-work-codex exec core-promotion-tool -- `
            verify `
            (Join-Path $EvidenceRoot "core0-manifest.json") `
            (Join-Path $EvidenceRoot "promotion.pending.json") `
            (Join-Path $stage1Evidence "self-interpret.json") `
            (Join-Path $EvidenceRoot "stage1-stage2-artifact-fixed-point.json") `
            (Join-Path $stage1Evidence "self-interpret.json")
    } (Join-Path $EvidenceRoot "promotion-verify.json")
}
finally {
    Pop-Location
}

Assert-FileEqual `
    "Stage0/Stage1 semantic witness" `
    (Join-Path $EvidenceRoot "stage0-semantics.json") `
    (Join-Path $stage1Evidence "semantics.json")
Assert-FileEqual `
    "Stage0/Stage1 referenced frontend witness" `
    (Join-Path $EvidenceRoot "stage0-referenced-frontend.json") `
    (Join-Path $stage1Evidence "referenced-frontend.json")
Assert-FileEqual `
    "Stage0/Stage1 crawler facade witness" `
    (Join-Path $EvidenceRoot "stage0-crawler-facade.json") `
    (Join-Path $stage1Evidence "crawler-facade.json")
Assert-FileEqual `
    "Stage0/Stage1 referenced runtime witness" `
    (Join-Path $EvidenceRoot "stage0-referenced-runtime.json") `
    (Join-Path $stage1Evidence "referenced-runtime.json")
Assert-FileEqual `
    "Stage0/Stage1 runtime witness" `
    (Join-Path $EvidenceRoot "stage0-runtime.json") `
    (Join-Path $stage1Evidence "runtime.json")
Assert-FileEqual `
    "Stage0/Stage1 TrustBase binding witness" `
    (Join-Path $EvidenceRoot "stage0-trustbase-binding.json") `
    (Join-Path $stage1Evidence "trustbase-binding.json")
Assert-FileEqual `
    "Stage0/Stage1 semantic self-interpret witness" `
    (Join-Path $EvidenceRoot "stage0-self-interpret.json") `
    (Join-Path $stage1Evidence "self-interpret.json")
Assert-FileEqual `
    "Stage0/Stage1 promotion policy witness" `
    (Join-Path $EvidenceRoot "stage0-promotion.json") `
    (Join-Path $stage1Evidence "promotion.json")
Assert-FileEqual `
    "Stage1/Stage2 semantic witness" `
    (Join-Path $stage1Evidence "semantics.json") `
    (Join-Path $stage2Evidence "semantics.json")
Assert-FileEqual `
    "Stage1/Stage2 referenced frontend witness" `
    (Join-Path $stage1Evidence "referenced-frontend.json") `
    (Join-Path $stage2Evidence "referenced-frontend.json")
Assert-FileEqual `
    "Stage1/Stage2 crawler facade witness" `
    (Join-Path $stage1Evidence "crawler-facade.json") `
    (Join-Path $stage2Evidence "crawler-facade.json")
Assert-FileEqual `
    "Stage1/Stage2 referenced runtime witness" `
    (Join-Path $stage1Evidence "referenced-runtime.json") `
    (Join-Path $stage2Evidence "referenced-runtime.json")
Assert-FileEqual `
    "Stage1/Stage2 runtime witness" `
    (Join-Path $stage1Evidence "runtime.json") `
    (Join-Path $stage2Evidence "runtime.json")
Assert-FileEqual `
    "Stage1/Stage2 TrustBase binding witness" `
    (Join-Path $stage1Evidence "trustbase-binding.json") `
    (Join-Path $stage2Evidence "trustbase-binding.json")
Assert-FileEqual `
    "Stage1/Stage2 semantic self-interpret witness" `
    (Join-Path $stage1Evidence "self-interpret.json") `
    (Join-Path $stage2Evidence "self-interpret.json")
Assert-FileEqual `
    "Stage1/Stage2 promotion policy witness" `
    (Join-Path $stage1Evidence "promotion.json") `
    (Join-Path $stage2Evidence "promotion.json")
Assert-FileEqual `
    "Stage1/Stage2 approved SDK package witness" `
    (Join-Path $stage1Evidence "sdk-package.json") `
    (Join-Path $stage2Evidence "sdk-package.json")
Assert-FileEqual `
    "Stage1/Stage2 self model report" `
    (Join-Path $stage1Evidence "self-model.json") `
    (Join-Path $stage2Evidence "self-model.json")
Assert-FileEqual `
    "Stage1/Stage2 TrustBase report" `
    (Join-Path $stage1Evidence "trust-base.json") `
    (Join-Path $stage2Evidence "trust-base.json")

Write-Host '{"schema":"myframework-self-artifact-gate.v1","result":"passed"}'
