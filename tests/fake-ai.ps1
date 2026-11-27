# Test double for app\SteveAIUi.ps1 (STEVECAD_TESTMOCK, only with STEVECAD_DRYRUN): a PC where Claude Code / Codex are
# not installed yet. winget "installs" by writing to a state file, and connecting records the pair instead of writing the
# assistants' real config files. State survives between processes: $env:STEVECAD_MOCKSTATE (JSON).
function Get-MockState {
  $f = $env:STEVECAD_MOCKSTATE
  if ($f -and (Test-Path -LiteralPath $f)) { return ([IO.File]::ReadAllText($f) | ConvertFrom-Json) }
  return [pscustomobject]@{ have = @('winget'); calls = @(); conn = @() }
}
function Save-MockState($s) { [IO.File]::WriteAllText($env:STEVECAD_MOCKSTATE, ($s | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
function Find-Exe([string]$name) { $n = $name -replace '\.(exe|cmd)$', ''; if (@((Get-MockState).have) -contains $n) { return "C:\mock\$n.exe" } return $null }
function Find-Codex { return (Find-Exe 'codex') }
function Get-ClaudeDesktopConfigs { return @() }
function Invoke-Exe([string]$File, [string[]]$ArgList = @(), [switch]$Quiet) {
  $s = Get-MockState; $line = "$File $($ArgList -join ' ')"
  $s.calls = @($s.calls) + $line
  if ($line -match '--id Anthropic\.ClaudeCode') { $s.have = @($s.have) + 'claude' }
  if ($line -match '--id OpenAI\.Codex') { $s.have = @($s.have) + 'codex' }
  Save-MockState $s; return 0
}
function Install-Server { }
function Remove-OldInstalls { }
function Update-OldServerRefs { }
function Add-Mock([string]$cl, [string]$cad) { $s = Get-MockState; $s.conn = @($s.conn) + "$cl/$cad"; Save-MockState $s }
function Add-ToClaudeCode([string]$name, $spec) { Add-Mock 'claudecode' $name }
function Add-ToCodex([string]$name, $spec) { Add-Mock 'codex' $name }
function Add-ToGemini([string]$name, $spec) { Add-Mock 'gemini' $name }
function Add-ToClaudeDesktop([string]$name, $spec) { Add-Mock 'claude' $name }
function Get-Connections {
  $o = @{}; foreach ($c in $script:ClientList) { $o[$c] = @(@((Get-MockState).conn) | Where-Object { $_ -like "$c/*" } | ForEach-Object { ($_ -split '/')[1] }) }
  return $o
}
