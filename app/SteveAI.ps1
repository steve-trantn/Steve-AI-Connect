<#
.SYNOPSIS
  Steve AI - mở cửa sổ làm việc với trợ lý AI (Claude Code / ChatGPT Codex / Gemini CLI),
  trỏ sẵn vào thư mục làm việc Steve-CAD-AI, đã nối với ZWCAD / AutoCAD / ADSCivil.

.DESCRIPTION
  Gọi từ shortcut "Steve AI", từ lệnh STEVEAI trong ZWCAD/AutoCAD, hoặc từ Steve AI Connect.
    -Client claudecode|codex|gemini   (mặc định: trợ lý đã chọn trong Steve AI Connect)
    -Skill <tên skill>                (mở và chạy ngay skill, ví dụ cong-3d)
#>
param([string]$Client = '', [string]$Skill = '', [switch]$Info, [switch]$Prepare, [switch]$Resume, [switch]$SendErrors)   # -Info / -Prepare: JSON for the chat panel (chat\SteveAIChat.cs)
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'account.ps1')
. (Join-Path $PSScriptRoot 'report.ps1')
if ($SendErrors) { [void](Send-ErrorReports); exit 0 }
$script:LogSink = { param($m, $lvl) }
if ($Info -or $Prepare) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }

function Show-Msg([string]$m) {
  if ($Info -or $Prepare) { [Console]::Out.Write((@{ error = $m } | ConvertTo-Json -Compress)); return }   # the chat panel shows it itself
  Add-Type -AssemblyName System.Windows.Forms
  [void][Windows.Forms.MessageBox]::Show($m, 'Steve AI', 'OK', 'Information')
}

try {
  # the chat window registers inside the CAD (view "Thiết lập"): it asks -Info first, and only -Prepare needs the account
  if (-not (Test-AccessOk) -and -not $Info -and ($Prepare -or -not (Test-ChatWindow))) {
    if ($Prepare) { Show-Msg 'Cần đăng ký một lần (miễn phí). Bấm ⚙ Thiết lập trong khung chat.'; exit 1 }
    Show-Msg "Cần đăng ký một lần (miễn phí) để dùng Steve AI. Bấm OK để mở cửa sổ đăng ký."
    if (-not $env:STEVECAD_DRYRUN) { Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$(Join-Path $PSScriptRoot 'SteveCADConnect.ps1')`"" -WindowStyle Hidden }
    exit 1
  }
  # the chat window (it calls this script back with -Info / -Prepare). Terminal window when it cannot run, or when the user prefers it.
  if (-not ($Info -or $Prepare) -and (Test-ChatWindow)) {
    $chatExe = Get-ChatExe
    if (-not $Client -and -not $Skill) {
      $open = @(Get-Process SteveAIChat -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })[0]
      if ($open) { [void](New-Object -ComObject WScript.Shell).AppActivate($open.Id); exit 0 }   # already open: bring it to the front
    }
    $ca = @()
    if ($Client) { $ca += '-Client', ($Client -replace '[^\w\-]', '') }
    if ($Skill) { $ca += '-Skill', ($Skill -replace '[^\w\-]', '') }
    if ($ca) { Start-Process $chatExe -ArgumentList $ca } else { Start-Process $chatExe }
    exit 0
  }
  $exe = @{ claudecode = (Find-Exe 'claude'); codex = (Find-Codex); gemini = (Find-Exe 'gemini.cmd') }
  if (-not $exe.gemini) { $exe.gemini = Find-Exe 'gemini' }
  if ($Info) {
    $o = @{ default = [string](Get-Setting 'DefaultAI' ''); access = [bool](Test-AccessOk); skills = @(Get-SkillList | ForEach-Object { @{ name = $_.name; title = $_.title; description = $_.description } })
      clients = @($script:LaunchClients | ForEach-Object { @{ id = $_; label = $script:ClientLabel[$_]; ok = ([bool]$exe[$_] -and ($_ -ne 'gemini' -or (Test-GeminiKey))) } }) }
    [Console]::Out.Write(($o | ConvertTo-Json -Depth 5 -Compress)); exit 0
  }
  $Client = $Client.Trim().ToLower()
  $asked = [bool]$Client
  if (-not $Client) { $Client = [string](Get-Setting 'DefaultAI' '') }
  if (-not $asked -and $Client -eq 'gemini' -and -not (Test-GeminiKey)) { $Client = '' }   # default without a key: use another assistant
  if (-not $Client -or -not $exe[$Client]) {
    $Client = @($script:LaunchClients | Where-Object { $exe[$_] } | Select-Object -First 1)[0]
  }
  if (-not $Client) {
    Show-Msg "Máy chưa có trợ lý AI dạng cửa sổ lệnh (Claude Code, ChatGPT Codex hoặc Gemini CLI).`n`nMở Steve AI Connect và bấm 'Kết nối tự động' ở bước 1.`n`nHỗ trợ: $($script:Contact)"
    exit 1
  }
  if ($Client -eq 'gemini' -and -not (Test-GeminiKey)) {
    Show-Msg "Gemini chưa có API key.`n`nMở Steve AI Connect, ở bước 1 bấm 'dán API key' tại dòng Gemini CLI.`nLấy key miễn phí: https://aistudio.google.com/apikey"
    exit 1
  }
  New-Item -ItemType Directory -Force $script:Workspace | Out-Null

  # first message: run the skill. Claude Code has native skills (/name); the others read it via get_skill.
  $prompt = ''
  if ($Skill) {
    $Skill = ($Skill -replace '[^\w\-]', '')
    $prompt = if ($Client -eq 'claudecode') { "/$Skill" }
              else { "Dùng skill $Skill`: gọi tool get_skill với name=$Skill của server CAD đang nối, đọc hướng dẫn rồi làm theo từng bước. Hỏi tôi những thông tin còn thiếu trước khi vẽ." }
  }
  $args0 = @()
  # codex.exe bundled with the Codex desktop app (Microsoft Store) has no local CLI package and
  # stops with "no complete local package" unless it runs without the background server
  if ($Client -eq 'codex' -and $exe.codex -match '\\WindowsApps\\') { $args0 += '--no-daemon' }
  # continue an earlier conversation: the assistant shows its own list (Claude Code, Codex)
  if ($Resume -and $Client -eq 'claudecode') { $args0 += '--resume' }
  if ($Resume -and $Client -eq 'codex') { $args0 = @('resume') + $args0 }
  if ($prompt) { $args0 += $(if ($Client -eq 'gemini') { @('-i', $prompt) } else { @($prompt) }) }

  $title = "Steve AI - $($script:ClientLabel[$Client])" + $(if ($Skill) { " - $Skill" } else { '' })
  # Write the command into a .cmd file and open that: passing paths with spaces (Codex lives in
  # C:\Program Files\WindowsApps) through wt.exe loses the quotes. Windows 11 opens .cmd files in
  # the default terminal (Windows Terminal), older Windows in a console window.
  $q = { param($s) '"' + ($s -replace '%', '%%' -replace '"', '""') + '"' }
  $cmdLine = (@($exe[$Client]) + $args0 | ForEach-Object { & $q $_ }) -join ' '
  if ($exe[$Client] -match '\.(cmd|bat)$') { $cmdLine = 'call ' + $cmdLine }
  $runDir = Join-Path $script:AppHome 'run'
  New-Item -ItemType Directory -Force $runDir | Out-Null
  $bat = Join-Path $runDir "SteveAI-$Client.cmd"
  $body = @(
    '@echo off', 'chcp 65001 >nul', "title $title", "cd /d `"$($script:Workspace)`"",
    $cmdLine,
    'if errorlevel 1 (', '  echo.', "  echo Tro ly AI dung voi loi. Can ho tro: $((ConvertTo-Ascii $script:Contact) -replace '\|', '-')", '  pause', ')'
  ) -join "`r`n"
  [IO.File]::WriteAllText($bat, $body + "`r`n", $script:Utf8)
  if ($Prepare) { [Console]::Out.Write((@{ bat = $bat; dir = $script:Workspace; client = $Client; label = $script:ClientLabel[$Client] } | ConvertTo-Json -Compress)); exit 0 }
  Start-Process $bat -WorkingDirectory $script:Workspace
} catch {
  Add-ErrorLog 'launcher' $_.Exception.Message $_.ScriptStackTrace
  Show-Msg "Không mở được cửa sổ AI: $($_.Exception.Message)`n`nHỗ trợ: $($script:Contact)"
  exit 1
}
