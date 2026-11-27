# Installing a missing assistant, without installing anything: Invoke-Exe and Find-Exe are replaced.
param([string]$root)
if (-not $env:STEVECAD_DRYRUN) { Write-Host 'Run it through run.ps1 (sandbox).'; exit 1 }
. (Join-Path $root 'app\core.ps1')
$script:LogSink = { param($m, $l) }
$bad = 0
function Check($n, [bool]$ok, $info = '') { if ($ok) { Write-Host "PASS  $n" } else { Write-Host "FAIL  $n $info"; $script:bad++ } }
$script:have = @{}; $script:calls = @(); $script:after = @{}
function Find-Exe([string]$n) { if ($script:have[$n]) { return "C:\x\$n.exe" } return $null }
function Find-Codex { return (Find-Exe 'codex') }
function Invoke-Exe([string]$File, [string[]]$ArgList = @(), [switch]$Quiet) { $line = "$File $($ArgList -join ' ')"; $script:calls += $line; foreach ($k in $script:after.Keys) { if ($line -match $k) { $script:have[$script:after[$k]] = $true } }; return 0 }
function Reset($h, $a) { $script:have = $h; $script:after = $a; $script:calls = @() }
Reset @{ winget = 1; claude = 1 } @{}; Install-ClaudeCode; Check 'da co thi khong cai' ($script:calls.Count -eq 0)
Reset @{ winget = 1 } @{ 'Anthropic\.ClaudeCode' = 'claude' }; Install-ClaudeCode; Check 'Claude Code qua winget, dung goi, kho chinh thuc' ($script:calls.Count -eq 1 -and $script:calls[0] -match '--id Anthropic\.ClaudeCode -e --source winget') $script:calls
Reset @{} @{ 'claude\.ai/install\.ps1' = 'claude' }; Install-ClaudeCode; Check 'khong co winget: bo cai cua Anthropic' ($script:calls.Count -eq 1 -and $script:calls[0] -match 'https://claude\.ai/install\.ps1')
Reset @{ winget = 1 } @{ 'claude\.ai/install\.ps1' = 'claude' }; Install-ClaudeCode; Check 'winget loi: thu bo cai cua Anthropic' ($script:calls.Count -eq 2)
Reset @{ winget = 1 } @{}; $e = ''; try { Install-ClaudeCode } catch { $e = "$_" }; Check 'cai khong duoc thi bao ro' ($e -match 'claude\.com')
Reset @{ winget = 1 } @{ 'OpenAI\.Codex' = 'codex' }; Install-CodexCli; Check 'Codex qua winget' ($script:calls.Count -eq 1)
Reset @{} @{}; $e = ''; try { Install-CodexCli } catch { $e = "$_" }; Check 'Codex khong co winget thi bao' ($e -match 'winget')
$script:ConfirmSink = { param($q) throw 'khong duoc hoi' }; $script:NoAsk = $true
Reset @{ winget = 1; 'npm.cmd' = 1 } @{ 'gemini-cli' = 'gemini' }; Install-GeminiCli; Check 'Gemini: da chon thi khong hoi lai' ($script:calls.Count -eq 1)
# the KCS package that a release build carries in kcs\ goes to %LOCALAPPDATA%\SteveCADConnect\kcs with the server
function Install-PythonEnv { }
$script:ServerDir = Join-Path $script:AppHome 'server-test'
$kroot = Join-Path ([IO.Path]::GetTempPath()) ('kcsroot-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force "$kroot\server", "$kroot\kcs\stevekcs" | Out-Null
'x' | Set-Content "$kroot\server\run.py"; 'def check_file(): pass' | Set-Content "$kroot\kcs\stevekcs\api.py"
$keepRoot = $script:Root; $script:Root = $kroot
Remove-Item (Join-Path $script:AppHome 'kcs') -Recurse -Force -ErrorAction SilentlyContinue
Install-Server
Check 'goi KCS di kem ban phat hanh duoc cai' (Test-Path (Join-Path $script:AppHome 'kcs\stevekcs\api.py'))
Remove-Item "$kroot\kcs" -Recurse -Force; Remove-Item (Join-Path $script:AppHome 'kcs') -Recurse -Force
$e = ''; try { Install-Server } catch { $e = "$_" }
Check 'khong co goi KCS van cai binh thuong' ($e -eq '' -and -not (Test-Path (Join-Path $script:AppHome 'kcs')))
$script:Root = $keepRoot; Remove-Item $kroot -Recurse -Force
$f = [IO.File]::ReadAllText((Join-Path $root 'app\gui.ps1'))
Check 'khong con hoi Trusted Locations' (-not $f.Contains('Thêm 3 thư mục của Steve AI vào Trusted Locations (Options'))
# v1.10 Setup.exe: app\SteveCADConnect.ps1 -Setup, no window, progress lines then "@@DONE {json}" (sandbox, DRYRUN)
$p = New-Object Diagnostics.ProcessStartInfo (Join-Path $PSHOME 'powershell.exe'), "-NoProfile -ExecutionPolicy Bypass -STA -File `"$(Join-Path $root 'app\SteveCADConnect.ps1')`" -Setup"
$p.UseShellExecute = $false; $p.RedirectStandardOutput = $true; $p.RedirectStandardInput = $true; $p.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
$pr = [Diagnostics.Process]::Start($p); $pr.StandardInput.Close(); $o = $pr.StandardOutput.ReadToEnd(); $pr.WaitForExit()
$lines = @($o -split "`r?`n" | Where-Object { $_ })
$done = @($lines | Where-Object { $_ -like '@@DONE *' })
$j = $null; if ($done) { $j = $done[-1].Substring(7) | ConvertFrom-Json }
Check '-Setup: tien trinh roi @@DONE' ($lines.Count -ge 3 -and $lines[-1] -like '@@DONE *' -and $lines[0] -match 'chép chương trình') $o
Check '-Setup: bao CAD tim thay (co nhan de mo)' ($j -and $j.version -eq $script:Version -and @($j.cads).Count -ge 1 -and -not @($j.cads | Where-Object { -not $_.label -or -not $_.cad })) $o
Check '-Setup: khong mo cua so, ma thoat 0' ($pr.ExitCode -eq 0) "exit $($pr.ExitCode)"
# the "Mở <CAD>" buttons of Setup.exe pass the exact name: with several versions, that one (not the first) starts
$multi = @(foreach ($c in $script:CadList) { $l = @(Get-CadLaunchers $c); if ($l.Count -ge 2) { @{ cad = $c; want = $l[-1].label } } })
if ($multi) {
  $m = $multi[0]
  $r = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'app\SteveCADConnect.ps1') -Launch $m.cad -CadVersion $m.want
  Check '-Launch dung ban theo ten chinh xac' ((@($r)[-1]) -like "*-> $($m.want)") "$r"
} else { Write-Host 'SKIP  -Launch nhieu ban (may chi co mot ban moi CAD)' }
exit $(if ($bad) { 1 } else { 0 })
