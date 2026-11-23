<#
.SYNOPSIS
  Bring the ADSCivil 2027 AI assistant (MCP) to ADSCivil 2026 and load it at every ZWCAD start.
  Usually run by Steve CAD-AI Connect, which finds the folders and asks for admin rights.

.DESCRIPTION
  Install:
    1. Copies Ads.System.AI.Assistant.zrx, AdsMcpServer.exe and AdsAI\ from the 2027 folder to the 2026 folder.
    2. Backs up ZWCAD.lsp in the 2026 folder and appends ads-ai-autoload.lsp (only once).
  -Uninstall:
    Removes the auto-load block from ZWCAD.lsp (backup first) and deletes the copied files.
  Close ADSCivil 2026 first. Needs admin rights when the folder is under C:\Program Files.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File CAD\ADSCivil\install-2026-autoload.ps1 -Source "<2027 folder>" -Target "<2026 folder>"
#>
param(
  [string]$Source = "C:\Program Files\BZS\ADSCivil NW 2027 For ZWCAD 2026",
  [string]$Target = "C:\Program Files\BZS\ADSCivil NW 2026 For ZWCAD 2026",
  [switch]$Uninstall,
  [switch]$PauseAtEnd
)
$ErrorActionPreference = 'Stop'
$marker  = '(defun ads-ai-autoload'
$snippet = Join-Path $PSScriptRoot 'ads-ai-autoload.lsp'
$files   = @('Ads.System.AI.Assistant.zrx', 'AdsMcpServer.exe', 'AdsAI')
$utf8    = New-Object Text.UTF8Encoding($false)
$exit    = 0

try {
  if (-not (Test-Path $Target)) { throw "Khong thay thu muc ADSCivil 2026: $Target" }
  $lsp = Join-Path $Target 'ZWCAD.lsp'
  if (-not (Test-Path $lsp)) { throw "Khong thay ZWCAD.lsp trong $Target" }
  $text = [IO.File]::ReadAllText($lsp)

  if ($Uninstall) {
    Write-Host "[1/2] Go doan tu nap khoi ZWCAD.lsp..."
    $rx = '(?s)(\r?\n)*;; =+\r?\n;; (\[[^\]]*\] )?ADSCivil AI \(MCP\).*?\(ads-ai-autoload\)[ \t]*(\r?\n)?'
    if ($text -match $rx) {
      Copy-Item $lsp "$lsp.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
      [IO.File]::WriteAllText($lsp, ([regex]::Replace($text, $rx, "`r`n")), $utf8)
      Write-Host "      Da go."
    } else { Write-Host "      Khong co doan tu nap, bo qua." }
    Write-Host "[2/2] Xoa file module AI da chep..."
    if ((Resolve-Path $Source -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $Target).Path) {
      Write-Host "      Thu muc nguon trung thu muc dich, khong xoa."
    } else {
      foreach ($f in $files) { $p = Join-Path $Target $f; if (Test-Path $p) { Remove-Item $p -Recurse -Force; Write-Host "      Da xoa $f" } }
    }
    Write-Host ""
    Write-Host "XONG: da go tro ly AI khoi ADSCivil 2026."
  } else {
    if (-not (Test-Path $Source)) { throw "Khong thay thu muc ADSCivil 2027: $Source" }
    foreach ($f in $files) {
      if (-not (Test-Path (Join-Path $Source $f))) { throw "Thieu trong thu muc 2027: $f (can ADSCivil NW 2027 ban co tro ly AI)" }
    }
    Write-Host "[1/2] Chep module AI tu 2027 sang 2026..."
    foreach ($f in $files) { Copy-Item (Join-Path $Source $f) $Target -Recurse -Force }

    Write-Host "[2/2] Them doan tu nap vao ZWCAD.lsp..."
    if ($text.Contains($marker)) {
      Write-Host "      ZWCAD.lsp da co doan tu nap, bo qua."
    } else {
      $bak = "$lsp.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
      Copy-Item $lsp $bak
      $add = [IO.File]::ReadAllText((Resolve-Path $snippet))
      $nl  = if ($text.EndsWith("`n")) { '' } else { "`r`n" }
      [IO.File]::WriteAllText($lsp, $text + $nl + "`r`n" + $add, $utf8)
      Write-Host "      Da them. Ban sao luu: $bak"
    }
    Write-Host ""
    Write-Host "XONG. Mo ADSCivil 2026: dong lenh hien 'ADSCivil AI: da nap...'. Go ADSAI de mo tro ly."
    Write-Host "Luu y: cai lai ADSCivil 2026 se ghi de ZWCAD.lsp - khi do bam Connect lai trong Steve CAD-AI Connect."
  }
} catch {
  Write-Host ""
  Write-Host "LOI: $($_.Exception.Message)" -ForegroundColor Red
  $exit = 1
}
if ($PauseAtEnd) { Read-Host "Nhan Enter de dong" | Out-Null }
exit $exit
