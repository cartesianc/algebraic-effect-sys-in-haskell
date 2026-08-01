$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$runtimePath = Join-Path $repoRoot "src\MyFramework\Runtime\V52.hs"
$hookTypesPath = Join-Path $repoRoot "src\MyFramework\Hook\Types.hs"

$runtimeText = Get-Content -LiteralPath $runtimePath -Raw
$contextMatch = [regex]::Match(
    $runtimeText,
    'data MiddlewareContext[\s\S]*?type RuntimeMiddleware'
)
if (-not $contextMatch.Success) {
    throw "MiddlewareContext boundary block missing"
}

$forbidden = @("InputGraph", "ValueGraph", "ContinuationPlan", "PipelinePatch")
foreach ($token in $forbidden) {
    if ($contextMatch.Value.Contains($token)) {
        throw "MiddlewareContext exposes forbidden mutation surface: $token"
    }
}

$hookTypes = Get-Content -LiteralPath $hookTypesPath -Raw
foreach ($token in @("IO ", "RuntimeActionV52", "RuntimeMiddleware")) {
    if ($hookTypes.Contains($token)) {
        throw "serializable HookPlan contains runtime closure token: $token"
    }
}

Write-Host '{"schema":"middleware-boundary.v1","result":"passed"}'
