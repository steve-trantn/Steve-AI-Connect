<#
.SYNOPSIS
  Steve AI - mở cửa sổ làm việc với trợ lý AI (Claude Code / ChatGPT Codex / Gemini CLI),
  trỏ sẵn vào thư mục làm việc Steve-CAD-AI, đã nối với ZWCAD / AutoCAD / ADSCivil.

.DESCRIPTION
  Gọi từ shortcut "Steve AI", từ lệnh STEVEAI trong ZWCAD/AutoCAD, hoặc từ Steve AI Connect.
    -Client claudecode|codex|gemini   (mặc định: trợ lý đã chọn trong Steve AI Connect)
    -Skill <tên skill>                (mở và chạy ngay skill, ví dụ cong-3d)
#>
param([string]$Client = '', [string]$Skill = '')
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'account.ps1')
$script:LogSink = { param($m, $lvl) }

function Show-Msg([string]$m) {
  Add-Type -AssemblyName System.Windows.Forms
  [void][Windows.Forms.MessageBox]::Show($m, 'Steve AI', 'OK', 'Information')
}

try {
  if (-not (Test-AccessOk)) {
    Show-Msg "Cần đăng ký một lần (miễn phí) để dùng Steve AI. Bấm OK để mở cửa sổ đăng ký."
    Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$(Join-Path $PSScriptRoot 'SteveCADConnect.ps1')`"" -WindowStyle Hidden
    exit 1
  }
  $exe = @{ claudecode = (Find-Exe 'claude'); codex = (Find-Codex); gemini = (Find-Exe 'gemini.cmd') }
  if (-not $exe.gemini) { $exe.gemini = Find-Exe 'gemini' }
  $Client = $Client.Trim().ToLower()
  if (-not $Client) { $Client = [string](Get-Setting 'DefaultAI' '') }
  if (-not $Client -or -not $exe[$Client]) {
    $Client = @($script:LaunchClients | Where-Object { $exe[$_] } | Select-Object -First 1)[0]
  }
  if (-not $Client) {
    Show-Msg "Máy chưa có trợ lý AI dạng cửa sổ lệnh (Claude Code, ChatGPT Codex hoặc Gemini CLI).`n`nMở Steve AI Connect và bấm “Kết nối tự động” ở bước 1.`n`nHỗ trợ: $($script:Contact)"
    exit 1
  }
  if ($Client -eq 'gemini' -and -not (Test-GeminiKey)) {
    Show-Msg "Gemini chưa có API key.`n`nMở Steve AI Connect, ở bước 1 bấm “dán API key” tại dòng Gemini CLI.`nLấy key miễn phí: https://aistudio.google.com/apikey"
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
  Start-Process $bat -WorkingDirectory $script:Workspace
} catch {
  Show-Msg "Không mở được cửa sổ AI: $($_.Exception.Message)`n`nHỗ trợ: $($script:Contact)"
  exit 1
}
