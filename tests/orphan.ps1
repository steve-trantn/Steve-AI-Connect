# The chat program must end when its CAD ends (also when the CAD is killed), together with the assistant it started.
# Usage: orphan.ps1 <SteveAIChat.exe>     A small window stands in for the CAD.
param([string]$exe)
if (-not $env:STEVECAD_DRYRUN) { Write-Host 'Run it through run.ps1 (sandbox).'; exit 1 }
$code = "Add-Type -AssemblyName System.Windows.Forms; `$f = New-Object Windows.Forms.Form; `$f.Text = 'SteveAI test CAD'; `$f.ShowInTaskbar = `$false; [Windows.Forms.Application]::Run(`$f)"
$cad = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-EncodedCommand', ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))) -PassThru
Add-Type -Namespace T -Name F -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr FindWindow(string c, string t);'
$end = (Get-Date).AddSeconds(15); do { Start-Sleep -Milliseconds 300; $w = [T.F]::FindWindow([NullString]::Value, 'SteveAI test CAD') } while ($w -eq [IntPtr]::Zero -and (Get-Date) -lt $end)
if ($w -eq [IntPtr]::Zero) { Write-Host 'FAIL  orphan: no test window'; $cad.Kill(); exit 1 }
$si = New-Object Diagnostics.ProcessStartInfo $exe, "-Parent $($w.ToInt64()) -Cad autocad -Pid $($cad.Id) -Skill ui-help"
$si.UseShellExecute = $false; $si.RedirectStandardInput = $true; $si.RedirectStandardOutput = $true
$chat = [Diagnostics.Process]::Start($si); Start-Sleep 6
if ($chat.HasExited) { Write-Host 'FAIL  orphan: the chat ended too early'; $cad.Kill(); exit 1 }
$cad.Kill()
if ($chat.WaitForExit(8000)) { Write-Host 'PASS  chat ends with its CAD'; exit 0 }
Write-Host 'FAIL  chat keeps running after its CAD is gone'; $chat.Kill(); exit 1
