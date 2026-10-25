$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$crawlerPath = Join-Path $repoRoot "app\CrawlerFacadeWitness.hs"
$entryPath = Join-Path $repoRoot "src\MyFramework.hs"
$cabalPath = Join-Path $repoRoot "myframework.cabal"

$crawler = [System.IO.File]::ReadAllText($crawlerPath)
$entry = [System.IO.File]::ReadAllText($entryPath)
$cabal = [System.IO.File]::ReadAllText($cabalPath)

$forbidden = @(
    "scalarType",
    "recordType",
    "unitType",
    "readRegistry",
    "SchemaIdentity"
)

$violations = @()
foreach ($currentName in $forbidden) {
    if ($crawler.Contains($currentName)) {
        $violations += "crawler exposes legacy schema token: $currentName"
    }
}
if (-not $crawler.Contains("import MyFramework")) {
    $violations += "crawler does not import MyFramework"
}
if ($entry.Contains("MyFramework.Frontend.Runtime")) {
    $violations += "default MyFramework entry still exports the legacy frontend runtime"
}
if (-not $cabal.Contains("version: 0.2.0.0")) {
    $violations += "package version is not 0.2.0.0"
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host '{"schema":"schema-free-facade-boundary.v1","result":"passed"}'
