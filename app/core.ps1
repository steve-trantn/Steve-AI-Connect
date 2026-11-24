# Steve AI Connect - core logic shared by the GUI and the command line.
# Dot-source this file. Set $script:LogSink / $script:ConfirmSink to redirect messages and questions.

$ErrorActionPreference = 'Stop'
$script:AppName   = 'Steve AI Connect'
$script:AppId     = 'SteveCADConnect'
$script:Root      = Split-Path $PSScriptRoot
$script:Version   = (Get-Content (Join-Path $script:Root 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
$script:AppHome   = Join-Path $env:LOCALAPPDATA $script:AppId
$script:ToolDir   = Join-Path $script:AppHome 'tool'
$script:VenvPy    = Join-Path $script:AppHome 'venv\Scripts\python.exe'
$script:Workspace = Join-Path $env:USERPROFILE 'Steve-CAD-AI'
$script:Utf8      = New-Object Text.UTF8Encoding($false)
$script:IsGui     = $false
$script:Author    = 'Steve Tran'
$script:Phone     = '0987 779 228'
$script:Contact   = "$($script:Author) | $($script:Phone)"
$script:RepoUrl   = 'https://github.com/steve-trantn/Steve-AI-Connect'
# registration server (register\Code.gs deployed as a web app, the .../exec address). Empty = no registration.
$script:RegisterUrl = 'https://script.google.com/macros/s/AKfycbxxGPIt7HH86zXb0LUuc4nDyPKUPjdZn0vUT8df73YQha0gQfTZahNctXeyKDUraFXh3Q/exec'
if ($env:STEVECAD_REGURL) { $script:RegisterUrl = $env:STEVECAD_REGURL }   # tests
# products and services shown in the "buy me a coffee" dialog
$script:Products = @('ADSCivil BIM', 'ZWCAD', 'ADSCivil CDE', 'ADSCivil BIM Studio', 'ADSCivil IFC', 'Đào tạo BIM', 'Thuê làm dự án BIM')

# our own MCP server for ZWCAD / AutoCAD (folder server\ of this tool), installed to %LOCALAPPDATA%
$script:ServerDir = Join-Path $script:AppHome 'server'
$script:Settings  = Join-Path $script:AppHome 'settings.json'

$script:CadList    = @('zwcad', 'autocad', 'adscivil')
$script:CadLabel   = @{ zwcad = 'ZWCAD'; autocad = 'AutoCAD'; adscivil = 'ADSCivil' }
$script:ClientList = @('claude', 'claudecode', 'codex', 'gemini')
$script:ClientLabel = @{ claude = 'Claude Desktop'; claudecode = 'Claude Code'; codex = 'ChatGPT (Codex)'; gemini = 'Gemini CLI' }
# assistants that run in a terminal window: Steve AI (shortcut, STEVEAI command in CAD) opens these
$script:LaunchClients = @('claudecode', 'codex', 'gemini')
$script:Launcher  = Join-Path $script:AppHome 'tool\app\SteveAI.ps1'
$script:CadLisp   = Join-Path $script:AppHome 'SteveAI.lsp'

$script:LogSink     = { param($m, $lvl) Write-Host $m }
$script:ConfirmSink = { param($q) (Read-Host "$q (Y/N)") -match '^(y|yes|c|co)$' }
function Write-Log([string]$m, [string]$lvl = 'info') { & $script:LogSink $m $lvl }
function Confirm-User([string]$q) { return [bool](& $script:ConfirmSink $q) }
function Invoke-UiPump { if ($script:IsGui) { [System.Windows.Forms.Application]::DoEvents() } }

function Update-PathEnv {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
# Makes $dst a copy of $src without deleting $dst itself (a running process may have it open):
# copies new/changed files over, then removes files that are not in $src. __pycache__ is skipped.
function Sync-Folder([string]$src, [string]$dst) {
  $src = (Resolve-Path $src).Path.TrimEnd('\')
  New-Item -ItemType Directory -Force $dst | Out-Null
  $dst = (Resolve-Path $dst).Path.TrimEnd('\')
  $want = @{}
  foreach ($f in Get-ChildItem $src -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\__pycache__\\' }) {
    $rel = $f.FullName.Substring($src.Length + 1); $want[$rel.ToLower()] = $true
    $to = Join-Path $dst $rel
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    Copy-Item $f.FullName $to -Force
  }
  Get-ChildItem $dst -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and -not $want[$_.FullName.Substring($dst.Length + 1).ToLower()] } |
    Remove-Item -Force -ErrorAction SilentlyContinue
}
function Backup-File($f) { if (Test-Path $f) { Copy-Item $f "$f.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" } }
function Read-Json($f) {
  if (Test-Path $f) { $t = [IO.File]::ReadAllText($f); if ($t.Trim()) { return ($t | ConvertFrom-Json) } }
  return (New-Object PSObject)
}
function Get-Setting([string]$name, $default = $null) {
  $s = Read-Json $script:Settings
  if ($s.PSObject.Properties[$name]) { return $s.$name } else { return $default }
}
function Set-Setting([string]$name, $value) {
  New-Item -ItemType Directory -Force $script:AppHome | Out-Null
  $s = Read-Json $script:Settings; Set-Prop $s $name $value; Write-Json $script:Settings $s
}
function Write-Json($f, $obj) { [IO.File]::WriteAllText($f, ($obj | ConvertTo-Json -Depth 30), $script:Utf8) }
function Set-Prop($obj, [string]$name, $value) {
  if ($obj.PSObject.Properties[$name]) { $obj.$name = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# Runs an executable, streams its output to the log, keeps the GUI responsive. Returns the exit code.
function Invoke-Exe([string]$File, [string[]]$ArgList = @(), [switch]$Quiet) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $File
  $psi.Arguments = ($ArgList | ForEach-Object { if ($_ -match '[\s"]' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $script:Utf8; $psi.StandardErrorEncoding = $script:Utf8
  $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
  $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  while (-not $p.HasExited) { Start-Sleep -Milliseconds 100; Invoke-UiPump }
  $p.WaitForExit()
  if (-not $Quiet) {
    (($o.Result + "`n" + $e.Result) -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { Write-Log "      $_" 'detail' }
  }
  return $p.ExitCode
}
function Find-Exe([string]$name) {
  Update-PathEnv
  $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}

# ======================= detection =======================
function Get-ZwcadProgId {
  $ids = Get-ChildItem Registry::HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^ZWCAD\.Application\.\d+$' } | ForEach-Object { $_.PSChildName }
  if ($ids) { return ($ids | Sort-Object { [int]($_ -replace '^ZWCAD\.Application\.', '') } -Descending | Select-Object -First 1) }
  if (Test-Path 'Registry::HKEY_CLASSES_ROOT\ZWCAD.Application') { return 'ZWCAD.Application' }
  return $null
}
function Get-UninstallEntries {
  Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
}
function Get-AutocadVersions {
  $v = Get-UninstallEntries | Where-Object { $_.DisplayName -match '^AutoCAD (20\d\d)( -|$)' } | ForEach-Object { $Matches[1] }
  return @($v | Sort-Object -Unique)
}
function Find-AdsDir([string]$ver, [string]$mustHave) {
  $cands = @()
  foreach ($b in @("$env:ProgramFiles\BZS", "${env:ProgramFiles(x86)}\BZS")) {
    if ($b -and (Test-Path $b)) {
      $cands += Get-ChildItem $b -Directory | Where-Object { $_.Name -match "ADSCivil.* $ver .*ZWCAD" } | ForEach-Object { $_.FullName }
    }
  }
  $cands += Get-UninstallEntries | Where-Object { $_.DisplayName -match 'ADSCivil' -and $_.DisplayName -match " $ver" -and $_.InstallLocation } |
    ForEach-Object { $_.InstallLocation }
  foreach ($d in $cands) { if ($d -and (Test-Path (Join-Path $d $mustHave))) { return $d.TrimEnd('\') } }
  return $null
}

# Returns @{ zwcad=@{ok;info}; autocad=...; adscivil=@{ok;info;dir2027;dir2026} }
function Get-CadStatus {
  $s = @{}
  $zw = Get-ZwcadProgId
  $s.zwcad = @{ ok = [bool]$zw; info = $(if ($zw) { $zw -replace '^ZWCAD\.Application\.?', 'ZWCAD ' } else { 'chưa cài ZWCAD' }) }
  $ac = Get-AutocadVersions
  $hasAc = Test-Path 'Registry::HKEY_CLASSES_ROOT\AutoCAD.Application'
  $s.autocad = @{ ok = $hasAc; info = $(if ($ac) { 'AutoCAD ' + ($ac -join ', ') } elseif ($hasAc) { 'AutoCAD' } else { 'chưa cài AutoCAD' }) }
  $d27 = Find-AdsDir '2027' 'AdsMcpServer.exe'
  $d26 = Find-AdsDir '2026' 'ZWCAD.lsp'
  $s.adscivil = @{ ok = [bool]$d27; dir2027 = $d27; dir2026 = $d26
                   info = $(if ($d27) { 'ADSCivil NW 2027' + $(if ($d26) { ' + 2026' } else { '' }) } elseif ($d26) { 'chỉ có 2026 - cần bản 2027' } else { 'chưa cài ADSCivil' }) }
  return $s
}

# ---------- start the CAD programs ----------
function Get-CadProcess([string]$cad) {
  $n = @{ zwcad = 'ZWCAD'; adscivil = 'ZWCAD'; autocad = 'acad' }[$cad]
  return @(Get-Process $n -ErrorAction SilentlyContinue)
}
# ADSCivil runs inside ZWCAD.exe / acad.exe: a CAD process is ADSCivil when it has loaded ADSCivil modules (Ads.*).
# Reading a process's module list costs ~100 ms, so the answer is cached per process (a "no" is re-checked after 15 s,
# because ADSCivil loads its modules a few seconds after the CAD window appears).
$script:AdsProcCache = @{}
function Test-AdsProcess($p) {
  $c = $script:AdsProcCache[$p.Id]
  if ($c -and ($c.ads -or ((Get-Date) - $c.t).TotalSeconds -lt 15)) { return $c.ads }
  $ads = $false
  try { $ads = [bool](@($p.Modules) | Where-Object { $_.ModuleName -like 'Ads.*' } | Select-Object -First 1) } catch {}
  $script:AdsProcCache[$p.Id] = @{ ads = $ads; t = Get-Date }
  return $ads
}
function Test-CadRunning([string]$cad) {
  if ($cad -ne 'adscivil') { return (Get-CadProcess $cad).Count -gt 0 }
  foreach ($p in @(Get-Process ZWCAD, acad -ErrorAction SilentlyContinue)) { if (Test-AdsProcess $p) { return $true } }
  return $false
}

# ---------- every installed version of a CAD, so the user can pick one before starting it ----------
# Returns @(@{ id; label; file; args; dir; year }), newest first. Start-menu / desktop shortcuts are used
# when they exist because they carry the product's own switches (/product ACAD /language ...).
$script:LauncherCache = @{}
function Get-ShortcutTargets {
  if ($script:LauncherCache.lnk) { return $script:LauncherCache.lnk }
  $sh = New-Object -ComObject WScript.Shell
  $roots = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
             "$env:PUBLIC\Desktop", [Environment]::GetFolderPath('Desktop'))
  $out = @(foreach ($f in Get-ChildItem $roots -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue) {
    if ($f.Name -notmatch 'ZWCAD|AutoCAD|ADSCivil') { continue }
    try { $s = $sh.CreateShortcut($f.FullName); @{ lnk = $f.FullName; name = $f.BaseName; target = $s.TargetPath; args = $s.Arguments } } catch {}
  })
  $script:LauncherCache.lnk = $out
  return $out
}
function Get-CadLaunchers([string]$cad, [switch]$Refresh) {
  if ($Refresh) { $script:LauncherCache = @{} }
  if ($script:LauncherCache.ContainsKey($cad)) { return $script:LauncherCache[$cad] }
  $found = [ordered]@{}
  $add = { param($file, $argList, $label, $year)
    if (-not $file -or -not (Test-Path $file -PathType Leaf)) { return }
    $id = ("$file|$argList").ToLower().Trim()
    # short: the label without the product name, for the version list under the product's title
    $short = ($label -replace "^$($script:CadLabel[$cad])\s*", '').Trim(); if (-not $short) { $short = $label }
    if (-not $found.Contains($id)) { $found[$id] = @{ id = $id; label = $label; short = $short; file = $file; args = [string]$argList; dir = (Split-Path $file); year = [int]$year } }
  }
  $lnks = Get-ShortcutTargets
  if ($cad -eq 'adscivil') {
    # ADSCivil <year>.exe in each product folder (Program Files\BZS, uninstall entries, shortcuts)
    $dirs = @()
    foreach ($b in @("$env:ProgramFiles\BZS", "${env:ProgramFiles(x86)}\BZS")) {
      if ($b -and (Test-Path $b)) { $dirs += Get-ChildItem $b -Directory | ForEach-Object { $_.FullName } }
    }
    $dirs += Get-UninstallEntries | Where-Object { $_.DisplayName -match 'ADSCivil' -and $_.InstallLocation } | ForEach-Object { $_.InstallLocation }
    $dirs += $lnks | Where-Object { $_.target -match '\\ADSCivil (20\d\d)\.exe$' } | ForEach-Object { Split-Path $_.target }
    foreach ($d in ($dirs | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)) {
      foreach ($exe in Get-ChildItem $d -File -Filter 'ADSCivil *.exe' -ErrorAction SilentlyContinue) {
        if ($exe.Name -notmatch '^ADSCivil (20\d\d)\.exe$') { continue }
        $year = $Matches[1]
        $folder = Split-Path $d -Leaf
        $label = if ($folder -match 'ADSCivil') { ($folder -replace '\s+For\s+', ' · ') } else { "ADSCivil $year" }
        & $add $exe.FullName '' $label $year
      }
    }
  } else {
    $rx = @{ zwcad = '^ZWCAD (20\d\d)( .*)?$'; autocad = '^AutoCAD (20\d\d)( - .+)?$' }[$cad]
    $exeName = @{ zwcad = 'ZWCAD.exe'; autocad = 'acad.exe' }[$cad]
    foreach ($l in $lnks) {
      if ($l.name -notmatch $rx -or (Split-Path $l.target -Leaf) -ne $exeName) { continue }
      $year = [regex]::Match($l.name, '20\d\d').Value
      & $add $l.target $l.args ("$($script:CadLabel[$cad]) $year" + $(if ($l.name -match ' - (.+)$') { " ($($Matches[1]))" } else { '' })) $year
    }
    if (-not $found.Count) {
      # no shortcut: the COM server registered for the CAD
      $pid0 = if ($cad -eq 'zwcad') { Get-ZwcadProgId } else { 'AutoCAD.Application' }
      if ($pid0) {
        $clsid = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$pid0\CLSID" -ErrorAction SilentlyContinue).'(default)'
        $srv = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid\LocalServer32" -ErrorAction SilentlyContinue).'(default)'
        if ($srv -match '^"?([^"]+?\.exe)') { & $add $Matches[1] '' $script:CadLabel[$cad] ([regex]::Match($Matches[1], '20\d\d').Value) }
      }
    }
  }
  # same label twice (e.g. one shortcut with /company ZWSOFT, one with ZWSoft): keep the first
  $seen = @{}
  $list = @($found.Values | Sort-Object @{ e = { $_.year }; Descending = $true }, @{ e = { $_.label } } |
            Where-Object { $k = $_.label.ToLower(); if ($seen[$k]) { $false } else { $seen[$k] = $true; $true } })
  $script:LauncherCache[$cad] = $list
  return $list
}
# The version to start: the one picked last time, otherwise the newest.
function Get-CadLauncher([string]$cad, [string]$Id = '') {
  $list = @(Get-CadLaunchers $cad)
  if (-not $list) { return $null }
  if (-not $Id) { $Id = [string](Get-Setting "Launch_$cad" '') }
  $hit = @($list | Where-Object { $_.id -eq $Id })
  if ($hit) { return $hit[0] } else { return $list[0] }
}
function Start-Cad([string]$cad, [string]$Id = '') {
  $l = Get-CadLauncher $cad $Id
  if (-not $l) { throw "Không tìm thấy file chạy $($script:CadLabel[$cad])." }
  if ($env:STEVECAD_DRYRUN) { Write-Log "DRYRUN Start-Cad $cad -> $($l.label)" 'ok'; return }   # self-test: no CAD is started
  try { Repair-CadAddon } catch {}
  if ($l.args) { Start-Process $l.file -ArgumentList $l.args -WorkingDirectory $l.dir } else { Start-Process $l.file -WorkingDirectory $l.dir }
  Set-Setting "Launch_$cad" $l.id
  Write-Log "Đang khởi động $($l.label)... (mất khoảng 10-30 giây)" 'ok'
}
# The CADs to start for a selection: ADSCivil already starts ZWCAD, so it replaces plain ZWCAD.
function Get-CadsToStart([string[]]$Cads) {
  $list = @($Cads | Where-Object { -not (Test-CadRunning $_) })
  if ($list -contains 'adscivil') { $list = @($list | Where-Object { $_ -ne 'zwcad' }) }
  if (($Cads -contains 'adscivil' -or $Cads -contains 'zwcad') -and (Test-CadRunning 'zwcad')) { $list = @($list | Where-Object { $_ -notin 'zwcad', 'adscivil' }) }
  return $list
}

function Find-Codex {
  $cx = Find-Exe 'codex'
  if (-not $cx) {
    $pkg = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { $cx = Join-Path $pkg.InstallLocation 'app\resources\codex.exe' }
  }
  if ($cx -and (Test-Path $cx)) { return $cx }
  return $null
}

# ---------- logos of the AI assistants ----------
# Taken from the installed apps (their own exe icon), like the CAD logos; Gemini CLI is only a Node.js script
# with no icon, so its official logo ships in app\logos\gemini.png. Returns a file path (exe or png) or $null.
$script:AiIconCache = @{}
function Get-AiIconSource([string]$client) {
  if ($script:AiIconCache.ContainsKey($client)) { return $script:AiIconCache[$client] }
  $claudeApp = {
    $p = Get-AppxPackage Claude -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and (Test-Path (Join-Path $p.InstallLocation 'app\Claude.exe'))) { return (Join-Path $p.InstallLocation 'app\Claude.exe') }
    $d = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path "$d\claude.exe") { return "$d\claude.exe" }
    return $null
  }
  $f = $null
  switch ($client) {
    'claude'     { $f = & $claudeApp }
    'claudecode' { $e = Find-Exe 'claude'; $f = if ($e -and $e -match '\.exe$') { $e } else { & $claudeApp } }
    'codex'      {
      $p = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
      # the GUI: the app's flat logo, white on a dark theme, black on a light one (the exe icon is dark grey,
      # nearly invisible on dark); elsewhere (CAD ribbon) the exe icon
      $alt = if ($script:IsGui) { if ($script:Dark) { 'altform-unplated' } else { 'altform-lightunplated' } } else { '' }
      $png = if ($p -and $alt) { Join-Path $p.InstallLocation "assets\Square44x44Logo.targetsize-96_$alt.png" }
      $f = if ($png -and (Test-Path $png)) { $png } elseif ($p -and (Test-Path (Join-Path $p.InstallLocation 'app\ChatGPT.exe'))) { Join-Path $p.InstallLocation 'app\ChatGPT.exe' } else { Find-Codex }
    }
    'gemini'     { $f = Join-Path $PSScriptRoot 'logos\gemini.png' }
  }
  if ($f -and -not (Test-Path $f)) { $f = $null }
  $script:AiIconCache[$client] = $f
  return $f
}
# A square bitmap of $px pixels from an exe's icon or a png, or $null.
Add-Type -Namespace SteveCad -Name Icon -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint PrivateExtractIcons(string f, int i, int cx, int cy, IntPtr[] h, int[] id, uint n, uint flags);
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
'@ -ErrorAction SilentlyContinue
function Get-IconBitmap([string]$file, [int]$px) {
  if (-not $file -or -not (Test-Path $file)) { return $null }
  Add-Type -AssemblyName System.Drawing
  try {
    if ($file -match '\.png$') {
      $bytes = [IO.File]::ReadAllBytes($file)   # read into memory: Image.FromFile would keep the file locked
      $src = [Drawing.Image]::FromStream((New-Object IO.MemoryStream (, $bytes)))
    } else {
      $h = New-Object IntPtr[] 1; $id = New-Object int[] 1; $ask = [Math]::Max(32, [Math]::Min(256, $px))
      if ([SteveCad.Icon]::PrivateExtractIcons($file, 0, $ask, $ask, $h, $id, 1, 0) -eq 0 -or $h[0] -eq [IntPtr]::Zero) { return $null }
      $src = ([Drawing.Icon]::FromHandle($h[0])).ToBitmap(); [void][SteveCad.Icon]::DestroyIcon($h[0])
    }
    $b = New-Object Drawing.Bitmap $px, $px
    $g = [Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([Drawing.Color]::Transparent); $g.DrawImage($src, 0, 0, $px, $px); $g.Dispose(); $src.Dispose()
    return $b
  } catch { return $null }
}
function Get-ClaudeDesktopConfigs {
  $list = @()
  Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    ForEach-Object { $list += Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' }
  if ((Test-Path (Join-Path $env:LOCALAPPDATA 'AnthropicClaude')) -or (Test-Path (Join-Path $env:APPDATA 'Claude'))) {
    $list += Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
  }
  return $list
}
function Get-ClientStatus {
  $s = @{}
  $s.claude     = @{ ok = (@(Get-ClaudeDesktopConfigs).Count -gt 0); hint = 'Cài Claude Desktop: claude.ai/download' }
  $s.claudecode = @{ ok = [bool](Find-Exe 'claude'); hint = 'Cài Claude Code: claude.com/claude-code' }
  $s.codex      = @{ ok = [bool](Find-Codex); hint = 'Cài app Codex (Microsoft Store), đăng nhập ChatGPT' }
  $s.gemini     = @{ ok = [bool](Find-Exe 'gemini'); hint = 'Chưa có - sẽ tự cài Gemini CLI khi Connect' }
  return $s
}

# Which of our servers each client has now: @{ codex=@('zwcad',...); ... }
function Get-Connections {
  $r = @{}
  foreach ($c in $script:ClientList) { $r[$c] = @() }
  $cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
  if (Test-Path $cfg) {
    $t = [IO.File]::ReadAllText($cfg)
    $r.codex = @($script:CadList | Where-Object { $t -match "(?m)^\[mcp_servers\.$_\]" })
  }
  $g = Read-Json (Join-Path $env:USERPROFILE '.gemini\settings.json')
  if ($g.PSObject.Properties['mcpServers']) { $r.gemini = @($script:CadList | Where-Object { $g.mcpServers.PSObject.Properties[$_] }) }
  foreach ($f in Get-ClaudeDesktopConfigs) {
    $j = Read-Json $f
    if ($j.PSObject.Properties['mcpServers']) { $r.claude = @($r.claude + @($script:CadList | Where-Object { $j.mcpServers.PSObject.Properties[$_] }) | Select-Object -Unique) }
  }
  try {
    $j = Read-Json (Join-Path $env:USERPROFILE '.claude.json')
    if ($j.PSObject.Properties['mcpServers']) { $r.claudecode = @($script:CadList | Where-Object { $j.mcpServers.PSObject.Properties[$_] }) }
  } catch {}
  return $r
}

# ======================= servers =======================
function Find-Python {
  Update-PathEnv
  $cands = @()
  $py = Find-Exe 'py'; if ($py) { $cands += , @($py, '-3') }
  $p = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
  if ($p) { $cands += , @($p.Source) }
  Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | ForEach-Object { $cands += , @($_.FullName) }
  foreach ($c in $cands) {
    try {
      $pre = @($c | Select-Object -Skip 1)
      $v = & $c[0] @pre -c "import sys;print('%d.%d' % sys.version_info[:2])" 2>$null
      if ($LASTEXITCODE -eq 0 -and "$v" -match '^3\.(\d+)$' -and [int]$Matches[1] -ge 10) { return , $c }
    } catch {}
  }
  return $null
}

function Install-PythonEnv {
  $mark = Join-Path $script:AppHome 'venv\.ok'
  $req = Join-Path $script:Root 'server\requirements.txt'
  $want = [IO.File]::ReadAllText($req).Trim()
  if ((Test-Path $script:VenvPy) -and (Test-Path $mark) -and ([IO.File]::ReadAllText($mark).Trim() -eq $want)) { return }
  if (Test-Path $script:VenvPy) {
    Write-Log "  Cập nhật thư viện Python..."
    if ((Invoke-Exe $script:VenvPy @('-m', 'pip', 'install', '-q', '--disable-pip-version-check', '-r', $req)) -ne 0) { throw "Cài thư viện Python thất bại (kiểm tra Internet)." }
    [IO.File]::WriteAllText($mark, $want, $script:Utf8); return
  }
  $py = Find-Python
  if (-not $py) {
    Write-Log "  Máy chưa có Python 3.10+ (cần cho ZWCAD/AutoCAD)." 'warn'
    if (-not (Find-Exe 'winget')) { throw "Không có winget. Cài Python 3.12 từ python.org rồi bấm Connect lại." }
    if (-not (Confirm-User "Cài Python 3.12 (miễn phí, từ Microsoft winget) ngay bây giờ?")) { throw "Cần Python để chạy MCP cho ZWCAD/AutoCAD." }
    Write-Log "  Đang cài Python 3.12..."
    Invoke-Exe (Find-Exe 'winget') @('install', '--id', 'Python.Python.3.12', '-e', '--scope', 'user', '--accept-source-agreements', '--accept-package-agreements') | Out-Null
    $py = Find-Python
    if (-not $py) { throw "Cài Python chưa xong. Đóng công cụ, mở lại rồi bấm Connect." }
  }
  Write-Log "  Python: $($py -join ' ')"
  Write-Log "  Tạo môi trường Python riêng và cài thư viện (1-2 phút)..."
  $pre = @($py | Select-Object -Skip 1)
  if ((Invoke-Exe $py[0] ($pre + @('-m', 'venv', (Join-Path $script:AppHome 'venv'))) -Quiet) -ne 0) { throw "Tạo môi trường Python thất bại." }
  if ((Invoke-Exe $script:VenvPy @('-m', 'pip', 'install', '-q', '--disable-pip-version-check', '-r', $req)) -ne 0) { throw "Cài thư viện Python thất bại (kiểm tra Internet)." }
  [IO.File]::WriteAllText($mark, $want, $script:Utf8)
}

# Copies the Steve CAD MCP server (server\ of this tool) to %LOCALAPPDATA%\SteveCADConnect\server.
function Install-Server {
  Install-PythonEnv
  $src = Join-Path $script:Root 'server'
  if ((Resolve-Path $src).Path.TrimEnd('\') -ne $script:ServerDir) {
    # running MCP servers keep this folder open: update in place, never delete the folder
    Sync-Folder $src $script:ServerDir
    Get-ChildItem $script:ServerDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Log "  Steve CAD MCP server sẵn sàng."
}

# @{ command; args; cwd } for one of our MCP servers
function Get-ServerSpec([string]$cad) {
  if ($cad -eq 'adscivil') {
    $d = Find-AdsDir '2027' 'AdsMcpServer.exe'
    if (-not $d) { throw "Không thấy ADSCivil NW 2027 (AdsMcpServer.exe)." }
    return @{ command = (Join-Path $d 'AdsMcpServer.exe'); args = @(); cwd = $d }
  }
  $a = @((Join-Path $script:ServerDir 'run.py'), '--cad', $cad)
  if ($cad -eq 'zwcad') { $pid0 = Get-ZwcadProgId; if ($pid0) { $a += @('--progid', $pid0) } }
  if (Get-Setting 'AllowScript' $false) { $a += '--allow-script' }
  return @{ command = $script:VenvPy; args = $a; cwd = $script:ServerDir }
}

# ======================= clients =======================
function Add-ToCodex([string]$name, $spec) {
  $cx = Find-Codex; if (-not $cx) { throw "Không thấy Codex." }
  $cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
  Backup-File $cfg
  Invoke-Exe $cx @('mcp', 'remove', $name) -Quiet | Out-Null
  if ((Invoke-Exe $cx (@('mcp', 'add', $name, '--', $spec.command) + $spec.args) -Quiet) -ne 0) { throw "codex mcp add $name thất bại." }
  # the Codex desktop app needs cwd, otherwise: "The directory name is invalid (os error 267)"
  $text = [IO.File]::ReadAllText($cfg)
  $rx = "(?m)^(\[mcp_servers\.$name\]\r?\n(?:(?!\[)[^\r\n]*\r?\n)*?command\s*=\s*[^\r\n]*\r?\n)"
  if ($text -notmatch "(?ms)^\[mcp_servers\.$name\][^\[]*?^cwd\s*=") {
    $text = [regex]::Replace($text, $rx, { param($m) $m.Value + "cwd = '$($spec.cwd)'`nstartup_timeout_sec = 60`n" }, 1)
    [IO.File]::WriteAllText($cfg, $text, $script:Utf8)
  }
}
function Remove-FromCodex([string]$name) {
  $cx = Find-Codex; if (-not $cx) { return }
  Backup-File (Join-Path $env:USERPROFILE '.codex\config.toml')
  Invoke-Exe $cx @('mcp', 'remove', $name) -Quiet | Out-Null
}

function Add-ToGemini([string]$name, $spec) {
  $gdir = Join-Path $env:USERPROFILE '.gemini'
  New-Item -ItemType Directory -Force $gdir | Out-Null
  $sf = Join-Path $gdir 'settings.json'
  Backup-File $sf
  $s = Read-Json $sf
  if (-not $s.PSObject.Properties['mcpServers']) { Set-Prop $s 'mcpServers' (New-Object PSObject) }
  Set-Prop $s.mcpServers $name ([pscustomobject]@{ command = $spec.command; args = @($spec.args); cwd = $spec.cwd; timeout = 600000; trust = $false })
  if (-not $s.PSObject.Properties['security']) { Set-Prop $s 'security' (New-Object PSObject) }
  if (-not $s.security.PSObject.Properties['auth']) { Set-Prop $s.security 'auth' (New-Object PSObject) }
  Set-Prop $s.security.auth 'selectedType' 'gemini-api-key'
  Write-Json $sf $s
  # Gemini disables MCP servers in untrusted folders
  $tf = Join-Path $gdir 'trustedFolders.json'
  $t = Read-Json $tf
  Set-Prop $t $script:Workspace 'TRUST_FOLDER'
  Write-Json $tf $t
}
function Remove-FromGemini([string]$name) {
  $sf = Join-Path $env:USERPROFILE '.gemini\settings.json'
  $s = Read-Json $sf
  if ($s.PSObject.Properties['mcpServers'] -and $s.mcpServers.PSObject.Properties[$name]) {
    Backup-File $sf; $s.mcpServers.PSObject.Properties.Remove($name); Write-Json $sf $s
  }
}

function Add-ToClaudeDesktop([string]$name, $spec) {
  foreach ($cf in Get-ClaudeDesktopConfigs) {
    New-Item -ItemType Directory -Force (Split-Path $cf) | Out-Null
    Backup-File $cf
    $s = Read-Json $cf
    if (-not $s.PSObject.Properties['mcpServers']) { Set-Prop $s 'mcpServers' (New-Object PSObject) }
    Set-Prop $s.mcpServers $name ([pscustomobject]@{ command = $spec.command; args = @($spec.args) })
    Write-Json $cf $s
  }
}
function Remove-FromClaudeDesktop([string]$name) {
  foreach ($cf in Get-ClaudeDesktopConfigs) {
    $s = Read-Json $cf
    if ($s.PSObject.Properties['mcpServers'] -and $s.mcpServers.PSObject.Properties[$name]) {
      Backup-File $cf; $s.mcpServers.PSObject.Properties.Remove($name); Write-Json $cf $s
    }
  }
}

function Add-ToClaudeCode([string]$name, $spec) {
  $cl = Find-Exe 'claude'; if (-not $cl) { throw "Không thấy Claude Code." }
  Invoke-Exe $cl @('mcp', 'remove', '-s', 'user', $name) -Quiet | Out-Null
  if ((Invoke-Exe $cl (@('mcp', 'add', '-s', 'user', $name, '--', $spec.command) + $spec.args) -Quiet) -ne 0) { throw "claude mcp add $name thất bại." }
}
function Remove-FromClaudeCode([string]$name) {
  $cl = Find-Exe 'claude'; if (-not $cl) { return }
  Invoke-Exe $cl @('mcp', 'remove', '-s', 'user', $name) -Quiet | Out-Null
}

function Install-GeminiCli {
  if (Find-Exe 'gemini') { return }
  if (-not (Confirm-User "Máy chưa có Gemini CLI. Cài Gemini CLI (và Node.js nếu thiếu) ngay bây giờ?")) { throw "Bỏ qua Gemini." }
  if (-not (Find-Exe 'npm.cmd')) {
    $wg = Find-Exe 'winget'; if (-not $wg) { throw "Không có winget. Cài Node.js LTS từ nodejs.org rồi thử lại." }
    Write-Log "  Đang cài Node.js..."
    Invoke-Exe $wg @('install', '--id', 'OpenJS.NodeJS.LTS', '-e', '--accept-source-agreements', '--accept-package-agreements') | Out-Null
  }
  $npm = Find-Exe 'npm.cmd'; if (-not $npm) { throw "Cài Node.js chưa xong. Đóng công cụ, mở lại rồi thử." }
  Write-Log "  Đang cài Gemini CLI..."
  Invoke-Exe $npm @('install', '-g', '@google/gemini-cli') | Out-Null
  if (-not (Find-Exe 'gemini')) { throw "Cài Gemini CLI chưa xong. Đóng công cụ, mở lại rồi thử." }
}

function Save-GeminiKey([string]$key) {
  if (-not $key -or -not $key.Trim()) { return }
  New-Item -ItemType Directory -Force $script:Workspace | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:Workspace '.env'), "GEMINI_API_KEY=$($key.Trim())`r`n", $script:Utf8)
  Write-Log "  Đã lưu Gemini API key vào $script:Workspace\.env"
}
function Test-GeminiKey { return ((Test-Path (Join-Path $script:Workspace '.env')) -or [bool]$env:GEMINI_API_KEY) }

# ======================= workspace (instructions for the AI) =======================
function Update-Workspace {
  New-Item -ItemType Directory -Force $script:Workspace | Out-Null
  $conn = Get-Connections
  $cads = @($script:ClientList | ForEach-Object { $conn[$_] } | Select-Object -Unique)
  $txt = [IO.File]::ReadAllText((Join-Path $script:Root 'templates\AGENTS.base.md'))
  foreach ($c in $script:CadList) {
    if ($cads -contains $c) { $txt += "`r`n" + [IO.File]::ReadAllText((Join-Path $script:Root "CAD\$($script:CadLabel[$c])\AGENTS.part.md")) }
  }
  foreach ($n in 'AGENTS.md', 'GEMINI.md', 'CLAUDE.md') { [IO.File]::WriteAllText((Join-Path $script:Workspace $n), $txt, $script:Utf8) }
  # skills (server\skills\<name>\SKILL.md): native Claude Code skills in the workspace; other AIs read them via get_skill
  $sk = Join-Path $script:Root 'server\skills'
  if (Test-Path $sk) {
    $dst = Join-Path $script:Workspace '.claude\skills'
    New-Item -ItemType Directory -Force $dst | Out-Null
    Get-ChildItem $sk -Directory | ForEach-Object { Copy-Item $_.FullName $dst -Recurse -Force }
  }
  Copy-Item (Join-Path $script:Root 'templates\Mo Gemini.cmd') $script:Workspace -Force
}

# ======================= Steve AI inside ZWCAD / AutoCAD =======================
. (Join-Path $PSScriptRoot 'cadmenu.ps1')   # ribbon tab "Steve AI" (SteveAI.cuix)
function ConvertTo-Ascii([string]$s) {
  $s = $s -replace 'đ', 'd' -replace 'Đ', 'D'
  $n = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $n.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark' -and [int]$ch -lt 128) { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}

# skills shipped in server\skills\<name>\SKILL.md: @(@{ name; description })
function Get-SkillList {
  $out = @()
  $sk = @((Join-Path $script:Root 'server\skills'), (Join-Path $script:Workspace 'skills'))   # built-in, then the user's own
  foreach ($d in (Get-ChildItem $sk -Directory -ErrorAction SilentlyContinue)) {
    $f = Join-Path $d.FullName 'SKILL.md'; if (-not (Test-Path $f)) { continue }
    $t = [IO.File]::ReadAllText($f)
    $name = $d.Name; $desc = ''
    if ($t -match '(?m)^name:\s*(.+)$') { $name = $Matches[1].Trim() }
    if ($t -match '(?m)^description:\s*(.+)$') { $desc = $Matches[1].Trim() }
    if ($name -notmatch '^[\w\-]+$' -or @($out | Where-Object { $_.name -eq $name }).Count) { continue }
    $out += @{ name = $name; description = $desc }
  }
  return $out
}

# Startup Suite keys (Dialogs\Appload\Startup) of every profile of the given CAD
function Get-StartupKeys([string]$cad) {
  $pat = @{ zwcad = 'HKCU:\Software\ZWSOFT\ZWCAD\*\*\Profiles\*'; autocad = 'HKCU:\Software\Autodesk\AutoCAD\R*\ACAD-*\Profiles\*' }[$cad]
  if (-not $pat) { return @() }
  return @(Get-Item $pat -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.PSPath 'Dialogs\Appload\Startup' })
}
function Get-StartupList([string]$key) {
  $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
  $n = 0; if ($p -and $p.PSObject.Properties['NumStartup']) { $n = [int]$p.NumStartup }
  return @(for ($i = 1; $i -le $n; $i++) { $v = $p."$($i)Startup"; if ($v) { $v } })
}
function Set-StartupList([string]$key, [string[]]$items) {
  if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
  $old = Get-ItemProperty $key
  foreach ($pr in $old.PSObject.Properties) { if ($pr.Name -match '^\d+Startup$') { Remove-ItemProperty $key $pr.Name } }
  for ($i = 0; $i -lt $items.Count; $i++) { Set-ItemProperty $key "$($i + 1)Startup" $items[$i] }
  Set-ItemProperty $key 'NumStartup' "$($items.Count)"
}

# Writes SteveAI.lsp (STEVEAI, STEVEAI-SKILL, AI, AI-<SKILL> commands).
function Write-CadLisp {
  $skills = @(Get-SkillList)
  $q = { param($s) '"' + ((ConvertTo-Ascii $s) -replace '\\', '\\' -replace '"', '\"') + '"' }
  $list = ($skills | ForEach-Object {
    $d = $_.description; if ($d.Length -gt 70) { $d = $d.Substring(0, 67).TrimEnd() + '...' }
    '(' + (& $q $_.name) + ' ' + (& $q $d) + ')' }) -join ' '
  $cmds = ($skills | ForEach-Object {
    $c = 'AI-' + ((ConvertTo-Ascii $_.name).ToUpper() -replace '[^A-Z0-9\-]', '-')
    "(defun c:$c () (steveai-run nil $(& $q $_.name)))" }) -join "`r`n"
  $t = [IO.File]::ReadAllText((Join-Path $script:Root 'templates\SteveAI.lsp'))
  $t = $t.Replace('@LAUNCHER@', ($script:Launcher -replace '\\', '/')).Replace('@SKILLS@', $list).Replace(';;@SKILLCMDS@', $cmds)
  $t = $t.Replace('@CONNECT@', ((Join-Path $script:ToolDir 'app\SteveCADConnect.ps1') -replace '\\', '/'))
  $menu = ''
  try { Write-CadMenu; $menu = $script:CadMenu -replace '\\', '/' } catch { Write-Log "  Không tạo được tab ribbon Steve AI: $($_.Exception.Message)" 'warn' }
  $t = $t.Replace('@CUIX@', $menu)
  $t = $t.Replace('@PANELZW@', ((Join-Path $script:ToolDir 'chat\bin\SteveAIPanel.ZWCAD.dll') -replace '\\', '/'))
  New-Item -ItemType Directory -Force $script:AppHome | Out-Null
  [IO.File]::WriteAllText($script:CadLisp, $t, [Text.Encoding]::ASCII)
  # SteveAI.mnl next to SteveAI.cuix: ZWCAD / AutoCAD load a menu's .mnl into every drawing together with the
  # menu, which the CAD remembers across restarts. Unlike the Startup Suite, the CAD never rewrites it on exit.
  $l = $script:CadLisp -replace '\\', '/'
  [IO.File]::WriteAllText(($script:CadMenu -replace '\.cuix$', '.mnl'), ";; Steve AI Connect: lenh AI / STEVEAI, nap cung menu Steve AI`r`n;; *steveai-from-menu*: SteveAI.lsp must not load the menu again (it is loading now)`r`n(if (findfile `"$l`") (progn (setq *steveai-from-menu* T) (load `"$l`")))`r`n(princ)`r`n", [Text.Encoding]::ASCII)
}

# Adds SteveAI.lsp to the Startup Suite of ZWCAD / AutoCAD and loads it into a running session.
function Install-CadAddon([string[]]$Cads) {
  Write-CadLisp
  $want = @(@(Get-Setting 'CadAddon' @()) + @($Cads | ForEach-Object { if ($_ -eq 'adscivil') { 'zwcad' } else { $_ } } | Where-Object { $_ -in 'zwcad', 'autocad' }) | Select-Object -Unique)
  Set-Setting 'CadAddon' $want
  foreach ($c in @($Cads | Where-Object { $_ -in 'zwcad', 'autocad', 'adscivil' })) {
    $cad = if ($c -eq 'adscivil') { 'zwcad' } else { $c }
    $keys = Get-StartupKeys $cad
    if (-not $keys) { continue }
    foreach ($k in $keys) {
      $items = @(Get-StartupList $k | Where-Object { $_ -notmatch 'SteveAI\.lsp$' }) + $script:CadLisp
      Set-StartupList $k $items
    }
    # running session: load now (best effort, only when the command line is idle)
    $progid = if ($cad -eq 'zwcad') { 'ZWCAD.Application' } else { 'AutoCAD.Application' }
    try {
      $app = [Runtime.InteropServices.Marshal]::GetActiveObject($progid)
      $doc = $app.ActiveDocument
      if ($doc -and [string]$doc.GetVariable('CMDNAMES') -eq '') {
        $doc.SendCommand("(load `"$($script:CadLisp -replace '\\', '/')`") ")
        Write-Log "  $($script:CadLabel[$cad]) đang mở: đã nạp lệnh AI và tab ribbon Steve AI." 'ok'
      }
    } catch {}
  }
}
function Remove-CadAddon {
  foreach ($cad in 'zwcad', 'autocad') {
    foreach ($k in Get-StartupKeys $cad) {
      $all = @(Get-StartupList $k)
      if ($all -match 'SteveAI\.lsp$') { Set-StartupList $k @($all | Where-Object { $_ -notmatch 'SteveAI\.lsp$' }) }
    }
  }
  Remove-Item $script:CadLisp, ($script:CadMenu -replace '\.cuix$', '.mnl') -Force -ErrorAction SilentlyContinue
  Remove-CadMenu
  Set-Setting 'CadAddon' @()
}
# ZWCAD / AutoCAD write their in-memory Startup Suite back to the registry when they close, so an entry
# added while the CAD was open is lost. Put it back when that CAD is not running (GUI start, before Start-Cad).
function Repair-CadAddon {
  if (-not (Test-Path $script:CadLisp)) { return }
  # installs from before SteveAI.mnl existed: write it (with the current lsp / menu) so AI loads with the menu
  if (-not (Test-Path ($script:CadMenu -replace '\.cuix$', '.mnl'))) { try { Write-CadLisp } catch {} }
  foreach ($cad in @(Get-Setting 'CadAddon' @())) {
    if (-not $cad -or (Get-CadProcess $cad).Count -or (Test-CadAddon $cad)) { continue }
    foreach ($k in Get-StartupKeys $cad) { Set-StartupList $k (@(Get-StartupList $k) + $script:CadLisp) }
    Write-Log "Đã đăng ký lại lệnh AI cho $($script:CadLabel[$cad])." 'detail'
  }
}
function Test-CadAddon([string]$cad) {
  foreach ($k in Get-StartupKeys $cad) { if (@(Get-StartupList $k) -match 'SteveAI\.lsp$') { return $true } }
  return $false
}

# the chat window (chat\bin\SteveAIChat.exe) needs Windows 10 1809+, 64-bit, and the WebView2 runtime
function Get-ChatExe { return (Join-Path $script:Root 'chat\bin\SteveAIChat.exe') }
function Test-ChatWindow {
  if ((Get-Setting 'UseTerminal' $false) -or -not (Test-Path (Get-ChatExe)) -or -not [Environment]::Is64BitOperatingSystem) { return $false }
  if ([int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber -lt 17763) { return $false }
  $g = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
  foreach ($k in "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$g", "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$g") {
    $v = [string](Get-ItemProperty $k -ErrorAction SilentlyContinue).pv
    if ($v -and $v -ne '0.0.0.0') { return $true }
  }
  return $false
}

# Opens Steve AI: the chat window, or the AI terminal window.
function Start-SteveAI([string]$Client = '', [string]$Skill = '') {
  $l = $script:Launcher
  if (-not (Test-Path $l)) { $l = Join-Path $PSScriptRoot 'SteveAI.ps1' }
  $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$l`""
  if ($Client) { $a += " -Client $Client" }
  if ($Skill) { $a += " -Skill $Skill" }
  if ($env:STEVECAD_DRYRUN) { Write-Log "DRYRUN Start-SteveAI $Client $Skill" 'ok'; return }   # self-test
  Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $a -WindowStyle Hidden
}

# ======================= ADSCivil 2026 auto-load =======================
function Set-Ads2026Autoload([switch]$Remove) {
  $st = (Get-CadStatus).adscivil
  if (-not $st.dir2026) { Write-Log "  Không có ADSCivil 2026, bỏ qua." ; return }
  if (-not $Remove -and -not $st.dir2027) { throw "Cần ADSCivil 2027 để chép trợ lý AI sang 2026." }
  $script2026 = Join-Path $script:Root 'CAD\ADSCivil\install-2026-autoload.ps1'
  $src = if ($st.dir2027) { $st.dir2027 } else { $st.dir2026 }
  $writable = $true
  try { $t = Join-Path $st.dir2026 "__w$PID.tmp"; [IO.File]::WriteAllText($t, 'x'); Remove-Item $t } catch { $writable = $false }
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script2026, '-Source', $src, '-Target', $st.dir2026)
  if ($Remove) { $a += '-Uninstall' }
  if ($writable) {
    $code = Invoke-Exe (Join-Path $PSHOME 'powershell.exe') $a
  } else {
    Write-Log "  Cần quyền admin để ghi vào $($st.dir2026) - Windows sẽ hỏi xác nhận..."
    $q = $a | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
    $p = Start-Process powershell -Verb RunAs -ArgumentList ($q + '-PauseAtEnd') -Wait -PassThru
    $code = $p.ExitCode
  }
  if ($code -ne 0) { throw "Cài/gỡ tự nạp ADSCivil 2026 báo lỗi (mã $code)." }
}
function Test-Ads2026Autoload {
  $d = (Get-CadStatus).adscivil.dir2026
  if (-not $d) { return $false }
  $lsp = Join-Path $d 'ZWCAD.lsp'
  return ((Test-Path $lsp) -and ([IO.File]::ReadAllText($lsp).Contains('(defun ads-ai-autoload')))
}

# ======================= the tool itself =======================
function New-AppIcon {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object Drawing.Bitmap 64, 64
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.Clear([Drawing.Color]::Transparent)
  $path = New-Object Drawing.Drawing2D.GraphicsPath
  $r = 14; $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc(63 - $r, 0, $r, $r, 270, 90); $path.AddArc(63 - $r, 63 - $r, $r, $r, 0, 90); $path.AddArc(0, 63 - $r, $r, $r, 90, 90); $path.CloseFigure()
  # ZWCAD-style blue gradient (sampled from the ZWCAD icon): white S and gold AI stand out on it
  $g.FillPath((New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Point 0, 0), (New-Object Drawing.Point 64, 64), ([Drawing.Color]::FromArgb(24, 150, 250)), ([Drawing.Color]::FromArgb(0, 88, 228))), $path)
  $f = New-Object Drawing.Font 'Segoe UI', 25, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
  $g.DrawString('S', $f, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 2, 40, 40), $sf)
  $f2 = New-Object Drawing.Font 'Segoe UI', 17, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
  $g.DrawString('AI', $f2, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 255, 196, 0))), (New-Object Drawing.RectangleF 22, 26, 42, 36), $sf)
  $g.Dispose()
  return [Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Install-Self {
  New-Item -ItemType Directory -Force $script:AppHome | Out-Null
  $same = ((Resolve-Path $script:Root).Path.TrimEnd('\') -eq $script:ToolDir)
  if (-not $same) {
    # copy over the old files instead of deleting the folder: the GUI (or a CAD-launched Steve AI)
    # may be running from it, and Windows will not delete a folder that is a process's current directory
    New-Item -ItemType Directory -Force $script:ToolDir | Out-Null
    $items = 'app', 'CAD', 'server', 'templates', 'chat', 'VERSION', 'README.md', 'LICENSE', 'NOTICE', 'Uninstall.cmd', 'Steve AI Connect.cmd'
    Get-ChildItem $script:ToolDir -Force | Where-Object { $items -notcontains $_.Name } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($i in $items) {
      $p = Join-Path $script:Root $i
      if (-not (Test-Path $p)) { continue }
      if (Test-Path $p -PathType Container) { Sync-Folder $p (Join-Path $script:ToolDir $i) }
      else { Copy-Item $p $script:ToolDir -Force }
    }
  }
  $ico = Join-Path $script:AppHome 'app.ico'
  try { $icon = New-AppIcon; $fs = [IO.File]::Create($ico); $icon.Save($fs); $fs.Close() } catch {}
  $ps1 = Join-Path $script:ToolDir 'app\SteveCADConnect.ps1'
  $sh = New-Object -ComObject WScript.Shell
  $lnks = @((Join-Path ([Environment]::GetFolderPath('Desktop')) "$($script:AppName).lnk"),
            (Join-Path ([Environment]::GetFolderPath('Programs')) "$($script:AppName).lnk"))
  foreach ($l in $lnks) {
    $s = $sh.CreateShortcut($l)
    $s.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$ps1`""
    $s.WorkingDirectory = $script:ToolDir
    $s.Description = 'Kết nối ZWCAD, AutoCAD, ADSCivil với Claude, ChatGPT, Gemini'
    if (Test-Path $ico) { $s.IconLocation = $ico }
    $s.Save()
  }
  # "Steve AI": opens the AI terminal window in the workspace (replaces the v2 "Gemini CAD AI" shortcut)
  Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gemini CAD AI.lnk') -Force -ErrorAction SilentlyContinue
  # the product was called "Steve CAD-AI Connect" in early builds: drop the shortcuts with the old name
  foreach ($d0 in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) { Remove-Item (Join-Path $d0 'Steve CAD-AI Connect.lnk') -Force -ErrorAction SilentlyContinue }
  foreach ($l in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Steve AI.lnk'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'Steve AI.lnk'))) {
    $s = $sh.CreateShortcut($l)
    $s.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:Launcher)`""
    $s.WorkingDirectory = $script:Workspace
    $s.Description = 'Mở cửa sổ trợ lý AI làm việc với ZWCAD / AutoCAD / ADSCivil'
    if (Test-Path $ico) { $s.IconLocation = $ico }
    $s.Save()
  }
  # Settings > Apps entry, so it can be removed like any program
  $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($script:AppId)"
  New-Item $k -Force | Out-Null
  $vals = @{ DisplayName = $script:AppName; DisplayVersion = ($script:Version -replace '^v', ''); Publisher = $script:Author;
             Contact = $script:Author; HelpTelephone = $script:Phone; HelpLink = $script:RepoUrl;
             UninstallString = "`"$(Join-Path $script:ToolDir 'Uninstall.cmd')`""; InstallLocation = $script:AppHome;
             DisplayIcon = $ico; URLInfoAbout = $script:RepoUrl }
  foreach ($n in $vals.Keys) { Set-ItemProperty $k $n $vals[$n] }
  Set-ItemProperty $k NoModify 1 -Type DWord; Set-ItemProperty $k NoRepair 1 -Type DWord
}

# Clean up the earlier separate ZWCAD-MCP package once nothing points to it any more.
function Remove-OldInstalls {
  # v1 packages: reuse their Gemini key, drop their desktop shortcuts
  foreach ($w in 'ADSCivil-Gemini', 'ZWCAD-AI') {
    $envOld = Join-Path $env:USERPROFILE "$w\.env"
    if ((Test-Path $envOld) -and -not (Test-Path (Join-Path $script:Workspace '.env'))) {
      New-Item -ItemType Directory -Force $script:Workspace | Out-Null
      Copy-Item $envOld $script:Workspace
    }
  }
  foreach ($l in 'Gemini ADSCivil.lnk', 'Gemini ZWCAD.lnk') { Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) $l) -Force -ErrorAction SilentlyContinue }
  # v2 used the third-party CAD-MCP server; v3 has its own
  $cadmcp = Join-Path $script:AppHome 'cadmcp'
  if (Test-Path $cadmcp) {
    $files0 = @((Join-Path $env:USERPROFILE '.codex\config.toml'), (Join-Path $env:USERPROFILE '.gemini\settings.json'), (Join-Path $env:USERPROFILE '.claude.json')) + @(Get-ClaudeDesktopConfigs)
    $used = $false
    foreach ($f in $files0) { if ((Test-Path $f) -and ([IO.File]::ReadAllText($f) -match 'SteveCADConnect\\{1,2}cadmcp')) { $used = $true } }
    if (-not $used) { Remove-Item $cadmcp -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "  Đã dọn server CAD-MCP cũ (v2)." }
  }
  $old = Join-Path $env:LOCALAPPDATA 'ZWCAD-MCP'
  if (-not (Test-Path $old)) { return }
  $files = @((Join-Path $env:USERPROFILE '.codex\config.toml'), (Join-Path $env:USERPROFILE '.gemini\settings.json'), (Join-Path $env:USERPROFILE '.claude.json')) + @(Get-ClaudeDesktopConfigs)
  foreach ($f in $files) { if ((Test-Path $f) -and ([IO.File]::ReadAllText($f) -match 'AppData\\{1,2}Local\\{1,2}ZWCAD-MCP')) { return } }
  Remove-Item $old -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gemini ZWCAD.lnk') -Force -ErrorAction SilentlyContinue
  Write-Log "  Đã dọn bản ZWCAD-MCP cũ."
}

# v2 -> v3: AI assistants that still point at the old CAD-MCP copy are switched to the new server.
function Update-OldServerRefs {
  $files = @{ codex = @(Join-Path $env:USERPROFILE '.codex\config.toml'); gemini = @(Join-Path $env:USERPROFILE '.gemini\settings.json');
              claudecode = @(Join-Path $env:USERPROFILE '.claude.json'); claude = @(Get-ClaudeDesktopConfigs) }
  $conn = Get-Connections
  foreach ($cl in $script:ClientList) {
    $old = $false
    foreach ($f in $files[$cl]) { if ($f -and (Test-Path $f) -and ([IO.File]::ReadAllText($f) -match 'SteveCADConnect\\{1,2}cadmcp')) { $old = $true } }
    if (-not $old) { continue }
    foreach ($c in @('zwcad', 'autocad')) {
      if ($conn[$cl] -notcontains $c) { continue }
      try {
        Install-Server
        $spec = Get-ServerSpec $c
        switch ($cl) {
          'codex'      { Add-ToCodex $c $spec }
          'gemini'     { Add-ToGemini $c $spec }
          'claude'     { Add-ToClaudeDesktop $c $spec }
          'claudecode' { Add-ToClaudeCode $c $spec }
        }
        Write-Log "  Nâng cấp $($script:ClientLabel[$cl])/$c lên server mới." 'ok'
      } catch { Write-Log "  Lỗi nâng cấp $($script:ClientLabel[$cl])/$c : $($_.Exception.Message)" 'error' }
    }
  }
}

# ======================= main actions =======================
function Invoke-Connect([string[]]$Cads, [string[]]$Clients, [bool]$Ads2026 = $false, [string]$GeminiKey = '') {
  if (-not $Cads) { throw "Chưa chọn phần mềm CAD nào." }
  if (-not $Clients) { throw "Chưa chọn trợ lý AI nào." }
  Write-Log "== CONNECT: $(($Cads | ForEach-Object { $script:CadLabel[$_] }) -join ', ')  ->  $(($Clients | ForEach-Object { $script:ClientLabel[$_] }) -join ', ')" 'title'
  $specs = @{}
  foreach ($c in $Cads) {
    Write-Log "[$($script:CadLabel[$c])] chuẩn bị MCP server..."
    if ($c -ne 'adscivil') { Install-Server }
    $specs[$c] = Get-ServerSpec $c
  }
  $ok = 0; $fail = 0
  foreach ($cl in $Clients) {
    Write-Log "[$($script:ClientLabel[$cl])]"
    try {
      if ($cl -eq 'gemini') { Install-GeminiCli; Save-GeminiKey $GeminiKey }
      foreach ($c in $Cads) {
        switch ($cl) {
          'codex'      { Add-ToCodex $c $specs[$c] }
          'gemini'     { Add-ToGemini $c $specs[$c] }
          'claude'     { Add-ToClaudeDesktop $c $specs[$c] }
          'claudecode' { Add-ToClaudeCode $c $specs[$c] }
        }
        Write-Log "  + $c" 'ok'
      }
      if ($cl -eq 'gemini' -and -not (Test-GeminiKey)) { Write-Log "  Chưa có Gemini API key: dán key vào ô Gemini rồi bấm Connect lại." 'warn' }
      $ok++
    } catch { Write-Log "  Lỗi: $($_.Exception.Message)" 'error'; $fail++ }
  }
  if ($Cads -contains 'adscivil' -and $Ads2026) {
    Write-Log "[ADSCivil 2026] tự nạp trợ lý ADSAI..."
    try { Set-Ads2026Autoload; Write-Log "  Đã bật tự nạp." 'ok' } catch { Write-Log "  Lỗi: $($_.Exception.Message)" 'error'; $fail++ }
  }
  Update-OldServerRefs
  Update-Workspace
  Install-Self
  Remove-OldInstalls
  Write-Log "[Steve AI] lệnh AI trong CAD + shortcut 'Steve AI' trên Desktop..."
  try { Install-CadAddon $Cads; Write-Log "  Xong. Trong ZWCAD/AutoCAD gõ AI (mở trợ lý) hoặc STEVEAI-SKILL (chạy skill)." 'ok' }
  catch { Write-Log "  Lỗi: $($_.Exception.Message)" 'error'; $fail++ }
  Write-Log ""
  if ($fail -eq 0) { Write-Log "XONG. Bấm 'Mở Steve AI' (hoặc shortcut 'Steve AI' / lệnh AI trong CAD) để bắt đầu làm việc. Trợ lý đang mở sẵn thì thoát hẳn rồi mở lại để nhận kết nối mới." 'ok' }
  else { Write-Log "Xong, có $fail lỗi - xem các dòng đỏ ở trên. Cần hỗ trợ: $($script:Contact)" 'warn' }
  return ($fail -eq 0)
}

function Invoke-Disconnect([string[]]$Cads, [string[]]$Clients, [bool]$Ads2026 = $false) {
  Write-Log "== DISCONNECT: $(($Cads | ForEach-Object { $script:CadLabel[$_] }) -join ', ')  khỏi  $(($Clients | ForEach-Object { $script:ClientLabel[$_] }) -join ', ')" 'title'
  foreach ($cl in $Clients) {
    foreach ($c in $Cads) {
      try {
        switch ($cl) {
          'codex'      { Remove-FromCodex $c }
          'gemini'     { Remove-FromGemini $c }
          'claude'     { Remove-FromClaudeDesktop $c }
          'claudecode' { Remove-FromClaudeCode $c }
        }
      } catch { Write-Log "  Lỗi $($script:ClientLabel[$cl])/$c : $($_.Exception.Message)" 'error' }
    }
    Write-Log "  - $($script:ClientLabel[$cl])" 'ok'
  }
  if ($Cads -contains 'adscivil' -and $Ads2026 -and (Test-Ads2026Autoload)) {
    try { Set-Ads2026Autoload -Remove; Write-Log "  Đã tắt tự nạp ADSCivil 2026." 'ok' } catch { Write-Log "  Lỗi: $($_.Exception.Message)" 'error' }
  }
  if (Test-Path $script:Workspace) { Update-Workspace }
  Write-Log "XONG. Khởi động lại trợ lý AI để áp dụng." 'ok'
}

function Invoke-Uninstall {
  Write-Log "== UNINSTALL: gỡ toàn bộ $($script:AppName)" 'title'
  Invoke-Disconnect $script:CadList $script:ClientList $true
  $desk = [Environment]::GetFolderPath('Desktop'); $progs = [Environment]::GetFolderPath('Programs')
  foreach ($l in "$desk\$($script:AppName).lnk", "$progs\$($script:AppName).lnk", "$desk\Gemini CAD AI.lnk", "$desk\Steve AI.lnk", "$progs\Steve AI.lnk", "$desk\Steve CAD-AI Connect.lnk", "$progs\Steve CAD-AI Connect.lnk") { Remove-Item $l -Force -ErrorAction SilentlyContinue }
  try { Remove-CadAddon; Write-Log "  Đã gỡ lệnh STEVEAI khỏi ZWCAD/AutoCAD (Startup Suite)." } catch { Write-Log "  Lỗi gỡ STEVEAI: $($_.Exception.Message)" 'error' }
  Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($script:AppId)" -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $script:AppHome) { Remove-Item $script:AppHome -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "  Đã xóa $script:AppHome" }
  Remove-OldInstalls
  Write-Log "  Thư mục $script:Workspace (có .env chứa API key) được giữ lại, xóa tay nếu muốn."
  Write-Log "ĐÃ GỠ XONG." 'ok'
}

# Talks MCP over stdio to one server: handshake, list tools, optionally call one tool.
function Test-McpServer($spec, [string]$call = '', [int]$timeoutSec = 60) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $spec.command
  $psi.Arguments = ($spec.args | ForEach-Object { "`"$_`"" }) -join ' '
  $psi.WorkingDirectory = $spec.cwd
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
  # .NET Framework writes Console.InputEncoding's preamble to the child's stdin at start; with the
  # system UTF-8 code page that is a BOM, which breaks the first JSON-RPC message. Use UTF-8 without BOM.
  $oldIn = $null
  try { $oldIn = [Console]::InputEncoding; [Console]::InputEncoding = $script:Utf8 } catch {}
  try { $p = [Diagnostics.Process]::Start($psi) } finally { if ($oldIn) { try { [Console]::InputEncoding = $oldIn } catch {} } }
  $null = $p.StandardError.ReadToEndAsync()
  $w = New-Object IO.StreamWriter($p.StandardInput.BaseStream, $script:Utf8)
  $rd = New-Object IO.StreamReader($p.StandardOutput.BaseStream, $script:Utf8)
  $send = { param($o) $w.WriteLine(($o | ConvertTo-Json -Depth 20 -Compress)); $w.Flush() }
  # wait for the response with this id; skip notifications and log messages
  $recv = {
    param($id)
    $end = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $end) {
      $t = $rd.ReadLineAsync()
      while (-not $t.IsCompleted -and (Get-Date) -lt $end) { Start-Sleep -Milliseconds 100; Invoke-UiPump }
      if (-not $t.IsCompleted -or $null -eq $t.Result) { break }
      try { $o = $t.Result | ConvertFrom-Json } catch { continue }
      if ($o.PSObject.Properties['id'] -and $o.id -eq $id) { return $o }
    }
    throw "server không trả lời"
  }
  try {
    & $send @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '2025-06-18'; capabilities = @{}; clientInfo = @{ name = 'steve-cad-ai-test'; version = '1' } } }
    $null = & $recv 1
    & $send @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
    & $send @{ jsonrpc = '2.0'; id = 2; method = 'tools/list' }
    $tools = @((& $recv 2).result.tools)
    $res = @{ tools = $tools.Count; text = '' }
    if ($call) {
      & $send @{ jsonrpc = '2.0'; id = 3; method = 'tools/call'; params = @{ name = $call; arguments = @{} } }
      $o = & $recv 3
      $res.text = if ($o.error) { 'LỖI: ' + $o.error.message } else { (@($o.result.content) | ForEach-Object { $_.text }) -join ' ' }
    }
    return $res
  } finally {
    try { $w.Close() } catch {}
    $p.WaitForExit(2000) | Out-Null; if (-not $p.HasExited) { $p.Kill() }
  }
}

function Invoke-Test([string[]]$Cads) {
  Write-Log "== KIỂM TRA" 'title'
  foreach ($c in $Cads) {
    try {
      $spec = Get-ServerSpec $c
      if (-not (Test-Path $spec.command) -or ($spec.args -and -not (Test-Path $spec.args[0]))) { Write-Log "[$($script:CadLabel[$c])] chưa cài - bấm Connect trước." 'warn'; continue }
      $proc = @{ zwcad = 'ZWCAD'; adscivil = 'ZWCAD'; autocad = 'acad' }[$c]
      $running = [bool](Get-Process $proc -ErrorAction SilentlyContinue)
      $call = if (-not $running) { '' } elseif ($c -eq 'adscivil') { 'get_drawing_info' } else { 'info' }
      $r = Test-McpServer $spec $call
      Write-Log "[$($script:CadLabel[$c])] server chạy, $($r.tools) tool." 'ok'
      if (-not $running) { Write-Log "  $($script:CadLabel[$c]) chưa mở - mở phần mềm và một bản vẽ để thử đọc bản vẽ." 'warn' }
      elseif ($c -eq 'adscivil') { Write-Log ("  " + ($r.text -replace '\s+', ' ').Substring(0, [Math]::Min(220, ($r.text -replace '\s+', ' ').Length))) }
      else {
        try { $j = $r.text | ConvertFrom-Json } catch { $j = $null }
        if ($j -and $j.drawing) { Write-Log "  Đọc được bản vẽ $(Split-Path $j.drawing -Leaf): $($j.modelspace_objects) đối tượng, layer hiện hành '$($j.current_layer)', đơn vị $($j.units)." 'ok' }
        else { Write-Log "  Chưa đọc được bản vẽ: $($r.text)" 'warn' }
      }
    } catch { Write-Log "[$($script:CadLabel[$c])] lỗi: $($_.Exception.Message)" 'error' }
  }
}
