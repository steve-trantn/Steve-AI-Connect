<#
.SYNOPSIS
  Steve AI Connect - kết nối ZWCAD, AutoCAD, ADSCivil với Claude, ChatGPT (Codex), Gemini qua MCP.

.DESCRIPTION
  Không tham số: mở giao diện (chọn CAD + trợ lý AI, Kết nối / Kiểm tra / Ngắt kết nối, mở Steve AI, xem danh sách tool).
  Dòng lệnh (cho IT):
    -Connect | -Disconnect | -Test | -Uninstall
    -Cad zwcad,autocad,adscivil        (mặc định: những phần mềm có trên máy)
    -Client claude,claudecode,codex,gemini   (mặc định: những trợ lý có trên máy)
    -Ads2026                            (ADSCivil 2026 tự nạp trợ lý ADSAI)
    -GeminiKey <key>
    -AllowScript / -AllowScript:$false  (cho AI chạy script Python trong ZWCAD/AutoCAD - nâng cao)
    -Launch zwcad|autocad|adscivil [-CadVersion <chữ trong tên bản, ví dụ 2026>]   khởi động CAD; nhiều bản thì hỏi chọn
    -ListVersions                        liệt kê các bản CAD đã cài
#>
param(
  [switch]$Connect, [switch]$Disconnect, [switch]$Test, [switch]$Uninstall,
  [string[]]$Cad, [string[]]$Client, [switch]$Ads2026, [string]$GeminiKey = '', [switch]$AllowScript,
  [string]$Launch = '', [string]$CadVersion = '', [switch]$ListVersions, [switch]$FirstRun,
  [ValidateSet('', 'home', 'share', 'feature', 'diag', 'help', 'update', 'options')][string]$Open = ''   # used by the CAD ribbon
)
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'account.ps1')
. (Join-Path $PSScriptRoot 'report.ps1')
Get-ChildItem $script:Root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# ======================= command line =======================
if ($Connect -or $Disconnect -or $Test -or $Uninstall -or $Launch -or $ListVersions) {
  try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
  $script:LogSink = {
    param($m, $lvl)
    $col = @{ ok = 'Green'; warn = 'Yellow'; error = 'Red'; title = 'Cyan'; detail = 'DarkGray' }[$lvl]
    if ($col) { Write-Host $m -ForegroundColor $col } else { Write-Host $m }
  }
  $cs = Get-CadStatus; $ks = Get-ClientStatus
  if (-not $Cad)    { $Cad    = @($script:CadList | Where-Object { $cs[$_].ok }) }
  if (-not $Client) { $Client = @($script:ClientList | Where-Object { $ks[$_].ok }) }
  $Cad = @($Cad -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
  $Client = @($Client -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
  $code = 0
  if ($PSBoundParameters.ContainsKey('AllowScript')) { Set-Setting 'AllowScript' ([bool]$AllowScript) }
  try {
    if ($ListVersions) {
      foreach ($c in $script:CadList) { Write-Log $script:CadLabel[$c] 'title'; Get-CadLaunchers $c | ForEach-Object { Write-Log "  $($_.label)   $($_.file)" } }
    }
    if ($Launch) {
      $c = $Launch.Trim().ToLower(); $list = @(Get-CadLaunchers $c)
      if (-not $list) { throw "Không tìm thấy $Launch trên máy." }
      if ($CadVersion) { $list = @($list | Where-Object { $_.label -like "*$CadVersion*" }); if (-not $list) { throw "Không có bản nào khớp '$CadVersion'." } }
      $pick = $list[0]
      if ($list.Count -gt 1 -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        for ($i = 0; $i -lt $list.Count; $i++) { Write-Log "  $($i + 1). $($list[$i].label)" }
        $n = Read-Host "Chọn bản [1-$($list.Count)] (Enter = 1)"
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $list.Count) { $pick = $list[[int]$n - 1] }
      }
      Start-Cad $c $pick.id
    }
    if ($Uninstall)  { Invoke-Uninstall }
    elseif ($Disconnect) { Invoke-Disconnect $Cad $Client ([bool]$Ads2026) }
    elseif ($Connect) {
      # the email code needs a person: an unattended install gets the trial, the window asks to register later
      if (-not (Test-AccessOk)) {
        if (Get-Setting 'TrialStart' '') { throw "Hết thời gian dùng tạm. Mở $($script:AppName) để đăng ký (miễn phí) rồi chạy lại." }
        Start-Trial; Write-Log "Chưa đăng ký: được dùng tạm $($script:TrialDays) ngày. Mở $($script:AppName) để đăng ký (miễn phí)." 'warn'
      }
      if (-not (Invoke-Connect $Cad $Client ([bool]$Ads2026) $GeminiKey)) { $code = 1 }
    }
    if ($Test) { Invoke-Test $Cad }
  } catch { Write-Log "LỖI: $($_.Exception.Message)" 'error'; Add-ErrorLog 'cli' $_.Exception.Message $_.ScriptStackTrace; $code = 1 }
  exit $code
}

# ======================= GUI =======================
# -Open from a CAD button: hand the request to a window that is already open (gui.ps1 reads the file), else start one
$script:OpenNext = $Open
$script:OpenFile = Join-Path $script:AppHome 'open-request.txt'
if ($Open) {
  $running = $null
  try { $running = [Threading.Mutex]::OpenExisting('Local\SteveAIConnectWindow') } catch {}
  if ($running) {
    $running.Dispose()
    try {
      Add-Type -Namespace SteveCad -Name Fg -MemberDefinition '[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);'
      [void][SteveCad.Fg]::AllowSetForegroundWindow(-1)
    } catch {}
    try {
      [IO.File]::WriteAllText($script:OpenFile, $Open)
      for ($i = 0; $i -lt 50 -and (Test-Path $script:OpenFile); $i++) { Start-Sleep -Milliseconds 100 }
      if (Test-Path $script:OpenFile) {
        Remove-Item $script:OpenFile -Force
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show('Steve AI Connect đang mở và đang bận hoặc chờ bạn trả lời một câu hỏi. Chuyển sang cửa sổ đó rồi thử lại.', $script:AppName, 'OK', 'Information')
      }
    } catch { Add-ErrorLog 'open' $_.Exception.Message $_.ScriptStackTrace }
    exit 0
  }
}
Remove-Item $script:OpenFile -Force -ErrorAction SilentlyContinue
$script:WindowMutex = New-Object Threading.Mutex $false, 'Local\SteveAIConnectWindow'   # lives as long as this window
# started by Setup.exe: create the desktop / Start-menu shortcuts and the Apps entry right away
# (done once the window is up, see gui.ps1: drawing the icon before the GUI turns on DPI awareness makes Windows keep 96 dpi)
$script:FirstRun = [bool]$FirstRun
. (Join-Path $PSScriptRoot 'gui.ps1')
