# Runs every automatic test:  powershell -ExecutionPolicy Bypass -File tests\run.ps1
# Works on a copy, in sandbox folders, against a mock server on 127.0.0.1:8767. Exit code 1 = something failed.
# Needs node and python. It does not replace trying the buttons in a real CAD (see CLAUDE.md).
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot; $t = Join-Path ([IO.Path]::GetTempPath()) ("steveai-test-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$copy = "$t\repo"; $hm = "$t\home"; $fail = 0
New-Item -ItemType Directory -Force $copy, "$t\lad\SteveCADConnect", "$t\app\Autodesk\ApplicationPlugins", "$t\ws", "$hm\Steve-CAD-AI" | Out-Null
foreach ($i in 'app', 'CAD', 'server', 'templates', 'chat', 'register', 'tests') { Copy-Item (Join-Path $repo $i) $copy -Recurse }
Copy-Item (Join-Path $repo 'VERSION'), (Join-Path $repo 'README.md') $copy
$bundle = Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins\SteveAI.bundle'
function Get-RegState {   # the CAD start-up lists, trusted folders and AutoCAD plug-in of this PC: tests must not change them
  $o = foreach ($k in 'HKCU\Software\ZWSOFT\ZWCAD', 'HKCU\Software\Autodesk\AutoCAD') { foreach ($f in 'SteveAI', 'SteveCADConnect') { reg query $k /s /f $f 2>$null }; reg query $k /s /v NumStartup 2>$null }
  $o += foreach ($f in Get-ChildItem $bundle -Recurse -File -ErrorAction SilentlyContinue) { "$($f.Name) $((Get-FileHash $f.FullName).Hash)" }
  return ($o -join "`n")
}
$ErrorActionPreference = 'Continue'
$before = Get-RegState
node "$copy\tests\report-text.test.js"; if ($LASTEXITCODE) { $fail++ }
$mock = Start-Process node -ArgumentList "`"$copy\tests\mock.js`"" -PassThru -WindowStyle Hidden; Start-Sleep 2
$keep = @{}; foreach ($n in 'APPDATA', 'LOCALAPPDATA', 'USERPROFILE') { $keep[$n] = [Environment]::GetEnvironmentVariable($n) }
$py = (Get-Command python).Source
try {
  $env:APPDATA = "$t\app"; $env:LOCALAPPDATA = "$t\lad"; $env:STEVECAD_DRYRUN = '1'
  # 1. the window, with every step of window.ps1
  $env:STEVECAD_SELFTEST = "$t\window.txt"; $env:STEVECAD_OPENTEST = '1'; $env:STEVECAD_WS = "$t\ws"; $env:STEVECAD_REGTEST = "$copy\tests\window.ps1"
  $w = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$copy\app\SteveCADConnect.ps1`"" -PassThru -WindowStyle Hidden
  if (-not $w.WaitForExit(480000)) { $w.Kill() }
  foreach ($n in 'SELFTEST', 'OPENTEST', 'WS', 'REGTEST') { [Environment]::SetEnvironmentVariable("STEVECAD_$n", $null) }
  if (Test-Path "$t\window.txt") { $l = [IO.File]::ReadAllLines("$t\window.txt"); $l | ForEach-Object { Write-Host $_ }; $fail += @($l | Where-Object { $_ -like 'FAIL*' }).Count } else { Write-Host 'FAIL  window test did not finish'; $fail++ }
  try { [void](New-Object Net.WebClient).DownloadString('http://127.0.0.1:8767/reset') } catch {}
  [IO.File]::WriteAllText("$t\lad\SteveCADConnect\settings.json", '{"Account":{"email":"thu@x.vn","name":"Thu"}}')
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$copy\tests\orphan.ps1" "$copy\chat\bin\SteveAIChat.exe"; if ($LASTEXITCODE) { $fail++ }
  # 2. the work behind the panels inside the CAD
  $env:USERPROFILE = $hm
  & $py -X utf8 "$copy\tests\ui.py" $copy "$hm\Steve-CAD-AI"; if ($LASTEXITCODE) { $fail++ }
} finally {
  foreach ($n in $keep.Keys) { [Environment]::SetEnvironmentVariable($n, $keep[$n]) }; $env:STEVECAD_DRYRUN = $null
  if (-not $mock.HasExited) { $mock.Kill() }
}
if ((Get-RegState) -ne $before) { Write-Host 'FAIL  a test changed the CAD settings of this PC'; $fail++ } else { Write-Host 'PASS  CAD settings of this PC are unchanged' }
cmd /c rmdir "$t\ws\skills\e-link\lk" 2>$null   # the junction first: never delete through it
if (-not (Test-Path "$t\ws\skills\e-link\lk")) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host $(if ($fail) { "=== $fail FAILED ===" } else { '=== ALL PASSED ===' })
exit $(if ($fail) { 1 } else { 0 })
