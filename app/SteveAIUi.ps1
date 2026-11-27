# Steve AI Connect - work behind the panels inside the CAD (help, report, feature request, share a skill, update check).
# Called by chat\SteveAIChat.cs: one JSON request {op, ...} on stdin, one JSON answer on stdout. No window is opened.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'account.ps1')
. (Join-Path $PSScriptRoot 'report.ps1')
. (Join-Path $PSScriptRoot 'update.ps1')
$script:LogSink = { param($m, $lvl) }
$utf8 = New-Object Text.UTF8Encoding $false
if ($env:STEVECAD_TESTURL -like 'http://127.0.0.1:*') { $script:RegisterUrl = $env:STEVECAD_TESTURL }   # tests: only this PC
# tests only (sandbox, DRYRUN): replace Find-Exe / Invoke-Exe... so "a PC without Claude Code" can be tried without installing anything
if ($env:STEVECAD_DRYRUN -and $env:STEVECAD_TESTMOCK -and (Test-Path -LiteralPath $env:STEVECAD_TESTMOCK)) { . $env:STEVECAD_TESTMOCK }
function Out-Answer($o) {
  $b = $utf8.GetBytes(($o | ConvertTo-Json -Depth 6 -Compress)); $s = [Console]::OpenStandardOutput(); $s.Write($b, 0, $b.Length); $s.Flush()
}
function Assert-Access { if (-not (Test-AccessOk)) { throw 'Cần đăng ký một lần (miễn phí). Bấm Mở Steve AI Connect để đăng ký.' } }
function Get-OwnSkill([string]$name) {
  $s = @(Get-OwnSkills | Where-Object { $_.name -ceq $name })[0]
  if (-not $s) { throw 'Không thấy skill này nữa. Đóng rồi mở lại.' }
  return $s
}
try {
  $rd = New-Object IO.StreamReader ([Console]::OpenStandardInput()), $utf8
  $q = $rd.ReadToEnd() | ConvertFrom-Json
  switch -CaseSensitive ([string]$q.op) {
    'ctx' {
      $acc = Get-Setting 'Account'
      Out-Answer @{ email = $(if ($acc) { [string]$acc.email } else { '' }); version = [string]$script:Version; author = [string]$script:Author; phone = [string]$script:Phone; draft = [string](Get-Setting 'ReportDraft' '') }
    }
    'diag' {
      $d = @(); $e = @()
      foreach ($l in ((Get-Diagnostics) -split '\r?\n')) { $x = Protect-Text $l; if (-not $x) { continue }; if ($x -match '^loi: ') { $e += $x } else { $d += $x } }
      Out-Answer @{ diag = @($d); errs = @($e) }
    }
    'draft' { Set-Setting 'ReportDraft' ([string]$q.text); Out-Answer @{ ok = $true } }
    'feature' {   # also the problem report (kind 'Báo lỗi'): the page sends exactly the text it showed
      Assert-Access
      $title = ([string]$q.title).Trim(); $desc = ([string]$q.desc).Trim()
      if (-not (Test-EmailText ([string]$q.email))) { throw 'Email chưa đúng.' }
      if ($title.Length -lt 5 -or $desc.Length -lt 15) { throw 'Mô tả thêm một chút (ít nhất 15 ký tự).' }
      if ($title.Length -gt 120 -or $desc.Length -gt 3000) { throw 'Nội dung quá dài.' }
      $r = Invoke-Register @{ action = 'feature'; email = ([string]$q.email).Trim().ToLower(); kind = [string]$q.kind; cad = [string]$q.cad; title = $title; desc = $desc; version = [string]$script:Version }
      if (-not $r.ok) { throw $script:RegErrors[[string]$r.error] }
      if ($q.kind -eq 'Báo lỗi') { Set-Setting 'ReportDraft' '' }
      Out-Answer @{ ok = $true }
    }
    'skills' { Out-Answer @{ skills = @(Get-OwnSkills | ForEach-Object { @{ name = $_.name; title = $_.title } }) } }
    'pack' {
      $p = New-SkillPack (Get-OwnSkill ([string]$q.name)).dir
      if ($p.error) { throw $p.error }
      $t = $p.text; if ($t.Length -gt 400000) { $t = $t.Substring(0, 400000) + "`n(xem trước bị rút gọn; gói vẫn gửi đủ)" }
      Out-Answer @{ files = @($p.files); notes = @($p.notes); skipped = @($p.skipped); sha = $p.sha; kb = [int][Math]::Ceiling($p.zip.Length / 1KB); text = $t }
    }
    'share' {
      Assert-Access
      if ($q.license -ne $true) { throw 'Cần tích đồng ý giấy phép để chia sẻ.' }
      $o = Get-OwnSkill ([string]$q.name); $p = New-SkillPack $o.dir
      if ($p.error) { throw $p.error }
      if ($p.sha -cne [string]$q.sha) { throw 'Skill vừa bị sửa sau khi xem trước. Chọn lại skill để xem bản mới rồi gửi.' }
      $r = Send-SkillPack $o $p ([string]$q.email) ([string]$q.author)
      if (-not $r.ok) { throw $r.text }
      Out-Answer @{ ok = $true; text = $r.text }
    }
    # ---------- "Thiết lập" inside the CAD (v1.10): registration, assistant, connection; no outside window ----------
    'setup' {
      $acc = Get-Setting 'Account'; $st = Get-CadStatus; $con = Get-Connections
      $exe = @{ claudecode = (Find-Exe 'claude'); codex = (Find-Codex); gemini = (Find-Exe 'gemini') }
      Out-Answer @{
        registered = [bool](Test-Registered); email = $(if ($acc) { [string]$acc.email } else { '' }); access = [bool](Test-AccessOk)
        trialLeft = [int](Get-TrialLeft); trialUsed = [bool](Get-Setting 'TrialStart' ''); version = [string]$script:Version
        cads = @($script:CadList | ForEach-Object { @{ id = $_; label = $script:CadLabel[$_]; ok = [bool]$st[$_].ok } })
        clients = @($script:LaunchClients | ForEach-Object { @{ id = $_; label = $script:ClientLabel[$_]; installed = [bool]$exe[$_]
          connected = [bool](@($con[$_]).Count); key = ($_ -ne 'gemini' -or (Test-GeminiKey)) } })
        default = [string](Get-Setting 'DefaultAI' ''); winget = [bool](Find-Exe 'winget')
      }
    }
    { $_ -in 'reg-send', 'reg-verify' } {
      $em = ([string]$q.email).Trim().ToLower(); $login = [bool]$q.login
      if (-not (Test-EmailText $em)) { throw 'Email chưa đúng.' }
      if (-not $login) {
        if (([string]$q.name).Trim().Length -lt 2) { throw 'Vui lòng nhập họ và tên.' }
        if (-not (Test-PhoneText ([string]$q.phone))) { throw 'Số điện thoại chưa đúng, ví dụ 0912 345 678.' }
        if ($q.consent -ne $true) { throw 'Cần tích đồng ý lưu thông tin để đăng ký.' }
      }
      if ($q.op -eq 'reg-send') { $body = @{ action = 'send'; email = $em } }
      else {
        if (([string]$q.code).Trim() -notmatch '^\d{6}$') { throw 'Mã gồm 6 chữ số.' }
        $body = @{ action = 'verify'; email = $em; code = ([string]$q.code).Trim(); version = [string]$script:Version }
        if (-not $login) { $body.name = ([string]$q.name).Trim(); $body.phone = Get-PhoneText ([string]$q.phone); $body.consent = $true; $body.news = [bool]$q.news }
      }
      $r = Invoke-Register $body
      if ($r.ok) {
        if ($q.op -eq 'reg-verify') { Save-Account $em ([string]$r.name) }
        Out-Answer @{ ok = $true }
      } else {
        # not the person's fault (no network, server...): the 7-day trial may start, once
        Out-Answer @{ ok = $false; text = $script:RegErrors[[string]$r.error]; why = [string]$r.error
          trial = ([string]$r.error -in $script:RegTrialErrors -and -not (Get-Setting 'TrialStart' '')) }
      }
    }
    'trial' {
      if (Get-Setting 'TrialStart' '') { if (-not (Test-AccessOk)) { throw 'Đã hết thời gian dùng tạm. Đăng ký (miễn phí) để dùng tiếp.' } }
      else { Start-Trial }
      Out-Answer @{ ok = $true; left = [int](Get-TrialLeft) }
    }
    'connect' {   # install the chosen assistant if needed, then connect every CAD on this PC with every usable assistant
      Assert-Access
      $inst = [string]$q.install; $key = ([string]$q.key).Trim()
      if ($inst -and $script:LaunchClients -notcontains $inst) { throw 'Trợ lý không hợp lệ.' }
      if ($inst -eq 'gemini' -and -not $key -and -not (Test-GeminiKey)) { throw 'Gemini cần API key. Lấy miễn phí tại aistudio.google.com/apikey rồi dán vào ô.' }
      $st = Get-CadStatus; $cads = @($script:CadList | Where-Object { $st[$_].ok })
      if (-not $cads) { throw 'Máy chưa có ZWCAD, AutoCAD hoặc ADSCivil.' }
      $ks = Get-ClientStatus
      $clis = @($script:ClientList | Where-Object { $ks[$_].ok -and $_ -ne $inst -and ($_ -ne 'gemini' -or $key -or (Test-GeminiKey)) })
      if ($inst) { $clis += $inst }
      if (-not $clis) { throw 'Chọn một trợ lý AI để cài.' }
      $lines = New-Object Collections.ArrayList
      $script:LogSink = { param($m, $lvl) if ($m -and $lvl -ne 'detail') { [void]$lines.Add(($m -replace '\s+', ' ').Trim()) } }
      $script:NoAsk = $true; $script:ConfirmSink = { param($x) $true }   # the person pressed the button for exactly this
      $ok = Invoke-Connect $cads $clis $false $key
      if ($ok -and $inst) { Set-Setting 'DefaultAI' $inst }
      Out-Answer @{ ok = [bool]$ok; log = @($lines | Select-Object -Last 12) }
    }
    'upgrade' {   # the new Setup.exe installs without a window, so the update needs nothing outside the CAD
      $r = Get-NewRelease
      if (-not $r) { throw "Bạn đang dùng bản mới nhất ($($script:Version))." }
      Start-Release (Save-Release $r)
      Out-Answer @{ ok = $true; tag = $r.tag }
    }
    'update' { $r = Get-NewRelease; Out-Answer @{ current = [string]$script:Version; tag = $(if ($r) { $r.tag } else { '' }); notes = $(if ($r) { $r.notes } else { '' }) } }
    'qr' { Out-Answer @{ png = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'donate-qr.png'))) } }
    default { throw 'Yêu cầu không hợp lệ.' }
  }
} catch {
  Out-Answer @{ error = [string]$_.Exception.Message }
}
