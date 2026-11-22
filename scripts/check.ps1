# 本地回归检查：重新生成全部命名空间、编译全部组件、逐个运行 demo。
# 有限 demo 须以 Succ 完成，持续 demo 须运行到观察期结束。结果打印在终端。
#
# 用法（在仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File scripts/check.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/check.ps1 -Skip crawler-demo   # 离线时跳过需要网络的 demo
#   powershell -ExecutionPolicy Bypass -File scripts/check.ps1 -Seconds 120         # 单个 demo 的限时

param(
  [string[]]$Skip = @(),
  [int]$Seconds = 60
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 持续运行的 demo（按 Ctrl-C 结束的程序）：限时内没有退出即视为正常，到时结束进程。
$continuous = @('stream-demo')
$continuousSeconds = 10

$failures = New-Object System.Collections.Generic.List[string]

function Write-Step([string]$text) {
  Write-Host ''
  Write-Host "== $text" -ForegroundColor Cyan
}

function Write-Tail([string]$path, [int]$count) {
  if (Test-Path $path) {
    Get-Content -Path $path -Encoding UTF8 -Tail $count | ForEach-Object { Write-Host "    $_" }
  }
}

function Write-Summary {
  Write-Host ''
  if ($failures.Count -eq 0) {
    Write-Host '== 全部通过' -ForegroundColor Green
  } else {
    Write-Host "== 失败 $($failures.Count) 项：" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
  }
}

# 1. 重新生成：demo 下每个带 Generated 目录的命名空间。
Write-Step '重新生成'
$namespaces = Get-ChildItem -Path demo -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName 'Generated') } |
  ForEach-Object { $_.Name }
foreach ($namespace in $namespaces) {
  $output = & cabal run -v0 effect-codegen -- compiler $namespace 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    $failures.Add("生成 $namespace")
    Write-Host "  $namespace 生成失败" -ForegroundColor Red
    Write-Host $output
  } else {
    Write-Host "  $($output.Trim())"
  }
}

# 生成结果与已提交的版本不同，通常表示改了生成器或手写输入还没提交生成结果；只提示，不算失败。
$changed = & git status --short -- demo 2>$null | Where-Object { $_ -match '/Generated/' }
if ($changed) {
  Write-Host '  以下生成文件与已提交的版本不同：' -ForegroundColor Yellow
  $changed | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}

# 2. 编译全部组件；失败时不再运行 demo。
Write-Step '编译'
& cabal build all
if ($LASTEXITCODE -ne 0) {
  $failures.Add('编译')
  Write-Summary
  exit 1
}

# 3. 有限 demo 的业务结果由 interpreter 打印。Failed 也可以正常退出。
Write-Step '运行 demo'
$demos = Select-String -Path *.cabal -Pattern '^executable\s+(\S+-demo)\s*$' |
  ForEach-Object { $_.Matches[0].Groups[1].Value }
foreach ($demo in $demos) {
  if ($Skip -contains $demo) {
    Write-Host "  $demo 跳过" -ForegroundColor DarkGray
    continue
  }
  $exe = (& cabal list-bin $demo 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) {
    $failures.Add("$demo（找不到可执行文件）")
    Write-Host "  $demo 找不到可执行文件" -ForegroundColor Red
    continue
  }
  $stdout = [IO.Path]::GetTempFileName()
  $stderr = [IO.Path]::GetTempFileName()
  $process = Start-Process -FilePath $exe -WorkingDirectory $root -NoNewWindow -PassThru `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $null = $process.Handle  # 让 Windows PowerShell 在进程退出后仍能读到 ExitCode
  $isContinuous = $continuous -contains $demo
  $limit = if ($isContinuous) { $continuousSeconds } else { $Seconds }
  $exited = $process.WaitForExit($limit * 1000)
  if (-not $exited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $process.WaitForExit()
    if ($isContinuous) {
      Write-Host "  $demo 持续运行 $limit 秒无故障，已结束" -ForegroundColor Green
    } else {
      $failures.Add("$demo（超过 $limit 秒未结束）")
      Write-Host "  $demo 超过 $limit 秒未结束" -ForegroundColor Red
      Write-Tail $stdout 10
    }
  } elseif ($isContinuous) {
    $failures.Add("$demo（在观察期内退出，退出码 $($process.ExitCode)）")
    Write-Host "  $demo 提前退出" -ForegroundColor Red
    Write-Tail $stdout 10
    Write-Tail $stderr 10
  } elseif ($process.ExitCode -eq 0) {
    $last = Get-Content -Path $stdout -Encoding UTF8 -Tail 1
    if ($last -cmatch '^Succ(?:\s|$)') {
      Write-Host "  $demo 通过：$last" -ForegroundColor Green
    } else {
      $failures.Add("$demo（未返回 Succ）")
      Write-Host "  $demo 业务未成功" -ForegroundColor Red
      Write-Tail $stdout 10
      Write-Tail $stderr 10
    }
  } else {
    $failures.Add("$demo（退出码 $($process.ExitCode)）")
    Write-Host "  $demo 失败，退出码 $($process.ExitCode)" -ForegroundColor Red
    Write-Tail $stdout 10
    Write-Tail $stderr 10
  }
  Remove-Item -Path $stdout, $stderr -ErrorAction SilentlyContinue
}

Write-Summary
if ($failures.Count -gt 0) { exit 1 }
