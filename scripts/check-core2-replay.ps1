param()

$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$generatedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot ".generated")
)
$replayRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $generatedRoot "approved-core2-replay")
)
$archivePath = [System.IO.Path]::GetFullPath(
    (Join-Path $generatedRoot "approved-core2-replay.zip")
)
$sourceDescriptorPath = Join-Path $repoRoot "trustbase\core2-source.json"

function Assert-GeneratedTarget {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentPath = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetDirectoryName($fullPath)
    )
    if ($parentPath -ne $generatedRoot) {
        throw "refusing replay cleanup outside $generatedRoot`: $fullPath"
    }
}

function Invoke-Checked {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

Assert-GeneratedTarget $replayRoot
Assert-GeneratedTarget $archivePath

$sourceDescriptor = Get-Content -LiteralPath $sourceDescriptorPath -Raw |
    ConvertFrom-Json

if ($sourceDescriptor.schema -ne "myframework-core-source-replay.v1") {
    throw "unsupported core2 source replay descriptor"
}
if ($sourceDescriptor.coreId -ne "core2") {
    throw "core2 source replay descriptor has the wrong core id"
}

if (Test-Path -LiteralPath $replayRoot) {
    Remove-Item -LiteralPath $replayRoot -Recurse -Force
}
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

Push-Location $repoRoot
try {
    Invoke-Checked "archive approved core2 source" {
        git archive --format=zip -o $archivePath $sourceDescriptor.sourceCommit
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $replayRoot
}
finally {
    Pop-Location
}

Push-Location $replayRoot
try {
    Invoke-Checked "build approved core2 source" {
        stack --work-dir .stack-work-core2-replay build
    }

    $materializedLines = @(
        stack --work-dir .stack-work-core2-replay exec self-artifact-tool -- `
            materialize replay .generated/core2-artifact
    )
    if ($LASTEXITCODE -ne 0) {
        throw "approved core2 artifact materialization failed"
    }
    $materialized = ($materializedLines -join "`n") | ConvertFrom-Json
    if ($materialized.payloadDigest -ne $sourceDescriptor.artifactDigest) {
        throw "replayed core2 payload does not match the approved artifact"
    }

    $payloadDigestLines = @(
        stack --work-dir .stack-work-core2-replay exec ghc -- `
            -ignore-dot-ghci `
            -package myframework `
            -e "case MyFramework.Self.CoreModel.frameworkAsBusiness of { Left e -> print e; Right x -> putStrLn (MyFramework.TrustBase.Digest.sha256 (MyFramework.Self.CoreModel.encodeFrameworkAsBusiness x)) }"
    )
    if ($LASTEXITCODE -ne 0) {
        throw "approved core2 framework payload replay failed"
    }
    $payloadDigest = ($payloadDigestLines -join "`n").Trim()
    if ($payloadDigest -ne $sourceDescriptor.frameworkPayloadDigest) {
        throw "replayed core2 framework payload digest does not match"
    }

    $previousWitnessLines = @(
        stack --work-dir .stack-work-core2-replay exec `
            core-self-interpret-witness
    )
    if ($LASTEXITCODE -ne 0) {
        throw "approved core2 semantic witness failed"
    }
    $previousWitnessText = $previousWitnessLines -join "`n"
    $previousWitness = $previousWitnessText | ConvertFrom-Json
    if ($previousWitness.result -ne "passed") {
        throw "approved core2 semantic witness did not pass"
    }
    if (
        -not $previousWitnessText.Contains(
            $sourceDescriptor.semanticObservationDigest
        )
    ) {
        throw "approved core2 observation digest does not match"
    }
}
finally {
    Pop-Location
}

Push-Location $repoRoot
try {
    $candidateWitnessLines = @(
        stack --work-dir .stack-work-codex exec `
            core-self-interpret-witness
    )
    if ($LASTEXITCODE -ne 0) {
        throw "facade core0 compatibility witness failed"
    }
    $candidateWitnessText = $candidateWitnessLines -join "`n"
    $candidateWitness = $candidateWitnessText | ConvertFrom-Json
    if ($candidateWitness.result -ne "passed") {
        throw "facade core0 compatibility witness did not pass"
    }
    if (
        -not $candidateWitnessText.Contains(
            $sourceDescriptor.frameworkPayloadDigest
        )
    ) {
        throw "facade core0 is not bound to the replayed core2 payload"
    }
    if (
        -not $candidateWitnessText.Contains(
            $sourceDescriptor.semanticObservationDigest
        )
    ) {
        throw "facade core0 is not bound to the replayed core2 observation"
    }
}
finally {
    Pop-Location
}

[ordered]@{
    schema = "myframework-core2-core0-replay.v1"
    result = "passed"
    previousCore = $sourceDescriptor.coreId
    sourceCommit = $sourceDescriptor.sourceCommit
    artifactDigest = $sourceDescriptor.artifactDigest
    frameworkPayloadDigest = $sourceDescriptor.frameworkPayloadDigest
    semanticObservationDigest = $sourceDescriptor.semanticObservationDigest
    candidateCore = "core0"
    candidateSchema = "myframework-framework-as-business.v4"
} | ConvertTo-Json -Compress
