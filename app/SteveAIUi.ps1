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
    'update' { $r = Get-NewRelease; Out-Answer @{ current = [string]$script:Version; tag = $(if ($r) { $r.tag } else { '' }); notes = $(if ($r) { $r.notes } else { '' }) } }
    'qr' { Out-Answer @{ png = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'donate-qr.png'))) } }
    default { throw 'Yêu cầu không hợp lệ.' }
  }
} catch {
  Out-Answer @{ error = [string]$_.Exception.Message }
}
