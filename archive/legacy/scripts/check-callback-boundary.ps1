$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$runtimePath = Join-Path $repoRoot "src\MyFramework\Runtime\V52.hs"
$runtimeText = Get-Content -LiteralPath $runtimePath -Raw

$callbackMatch = [regex]::Match(
    $runtimeText,
    'data CallbackContext[\s\S]*?type RuntimeCallback'
)
if (-not $callbackMatch.Success) {
    throw "CallbackContext boundary block missing"
}

foreach ($token in @("EffectRegistry", "RuntimeHandlerRegistry", "ElaboratedProgram", "CompiledGraphs")) {
    if ($callbackMatch.Value.Contains($token)) {
        throw "CallbackContext exposes global mutation surface: $token"
    }
}

if (-not $callbackMatch.Value.Contains("callbackContextSubmit")) {
    throw "CallbackContext does not expose the scoped patch submission capability"
}

Write-Host '{"schema":"callback-boundary.v1","result":"passed"}'
