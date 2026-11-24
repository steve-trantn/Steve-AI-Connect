# Steve AI Connect - update from GitHub Releases, and the "đề xuất tính năng" dialog. Dot-source after gui.ps1's helpers.
# The check only reads the public release page (no personal data is sent). The Setup.exe is run only when it comes
# from this repository's releases AND its SHA-256 matches the one GitHub publishes.
$script:UpdateApi = 'https://api.github.com/repos/steve-trantn/Steve-AI-Connect/releases/latest'
$script:UpdatePrefix = "$($script:RepoUrl)/releases/download/"
$script:NewRelease = $null

function ConvertTo-Ver([string]$s) { if ($s -match '^v?(\d+\.\d+\.\d+)$') { return [version]$Matches[1] } return $null }
# release JSON -> @{ tag; url; sha; notes } when it is newer than this copy and can be verified, otherwise $null
function Read-Release([string]$json) {
  $r = $json | ConvertFrom-Json
  $new = ConvertTo-Ver ([string]$r.tag_name); $cur = ConvertTo-Ver ([string]$script:Version)
  if (-not $new -or -not $cur -or $new -le $cur) { return $null }
  $a = @($r.assets | Where-Object { $_.name -match '^Steve-AI-Connect-Setup-v[\d.]+\.exe$' })[0]
  if (-not $a -or -not ([string]$a.browser_download_url).StartsWith($script:UpdatePrefix, [StringComparison]::Ordinal)) { return $null }
  if ([string]$a.digest -notmatch '^sha256:([0-9a-f]{64})$') { return $null }
  return @{ tag = [string]$r.tag_name; url = [string]$a.browser_download_url; sha = $Matches[1]; notes = [string]$r.body }
}
function New-UpdateClient {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
  $wc.Headers.Add('User-Agent', 'SteveAIConnect')
  if ($wc.Proxy) { $wc.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials }
  return $wc
}
# waits for a task without freezing the window; throws on error or timeout
function Wait-Task($task, $wc, [int]$sec) {
  $end = [DateTime]::Now.AddSeconds($sec)
  while (-not $task.IsCompleted) {
    if ([DateTime]::Now -gt $end) { $wc.CancelAsync(); throw 'Hết thời gian chờ mạng.' }
    Invoke-UiPump; Start-Sleep -Milliseconds 40
  }
  if ($task.IsFaulted -or $task.IsCanceled) { throw 'Không tải được từ GitHub. Kiểm tra mạng Internet.' }
  return $task.Result
}
function Get-NewRelease {
  $wc = New-UpdateClient
  try { return (Read-Release (Wait-Task ($wc.DownloadStringTaskAsync([Uri]$script:UpdateApi)) $wc 20)) } finally { $wc.Dispose() }
}
# downloads and verifies; returns the path of the exe
function Save-Release($rel) {
  $dir = Join-Path $env:TEMP ("SteveAIUpdate-" + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $dir | Out-Null
  $file = Join-Path $dir "Steve-AI-Connect-Setup-$($rel.tag).exe"
  $wc = New-UpdateClient
  try { $bytes = Wait-Task ($wc.DownloadDataTaskAsync([Uri]$rel.url)) $wc 180 } finally { $wc.Dispose() }
  $h = [Security.Cryptography.SHA256]::Create()
  try { $sha = [BitConverter]::ToString($h.ComputeHash([byte[]]$bytes)).Replace('-', '').ToLower() } finally { $h.Dispose() }
  if ($sha -ne $rel.sha) { throw 'File tải về không khớp mã kiểm tra nên đã bị bỏ. Thử lại sau.' }
  [IO.File]::WriteAllBytes($file, [byte[]]$bytes)
  return $file
}
function Start-Release([string]$file) {
  if ($env:STEVECAD_DRYRUN) { Write-Log "DRYRUN update $file" 'ok'; return }
  Start-Process $file
}

# first start after Setup.exe: bring the installed MCP server, CAD commands and AI notes to this version
function Update-Installed {
  if (Test-Path $script:VenvPy) { Install-Server }
  if (Test-Path $script:CadLisp) { Write-CadLisp }
  if (Test-Path (Join-Path $script:Workspace 'AGENTS.md')) { Update-Workspace }
}

# ---------- GUI ----------
function Show-Update($rel) {
  $d = New-SmallDialog 'Cập nhật Steve AI Connect' 480 372
  $u1 = Put (New-Label "Có bản mới $($rel.tag)" $Fnt.h2 $Pal.text) 20 14 440 26
  $u2 = Put (New-Label "Bạn đang dùng $($script:Version). Cấu hình và đăng ký được giữ nguyên." $Fnt.n $Pal.muted) 20 42 440 20
  $tb = Put (New-Object Windows.Forms.TextBox) 20 70 440 176; $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.TabStop = $false
  $tb.BackColor = $Pal.input; $tb.ForeColor = $Pal.text; $tb.BorderStyle = 'FixedSingle'
  $tb.Text = (($rel.notes -replace '[*`#>]', '') -replace '\r?\n', "`r`n").Trim()
  $cb = New-Object Windows.Forms.CheckBox; $cb.Text = 'Những lần sau tự cập nhật, không cần hỏi'; $cb.Font = $Fnt.s; $cb.ForeColor = $Pal.text
  [void](Put $cb 20 254 440 22); $cb.Checked = [bool](Get-Setting 'AutoUpdate' $false)
  $um = Put (New-Label '' $Fnt.s $Pal.muted) 20 280 440 36
  $go = Put (New-Button 'Cập nhật ngay' 'primary') 222 322 130 36
  $no = Put (New-Button 'Để sau') 360 322 100 36
  $busy = @{ on = $false }
  $go.add_Click({
    if ($busy.on) { return }
    Set-Setting 'AutoUpdate' ([bool]$cb.Checked); $miAuto.Checked = [bool]$cb.Checked
    $busy.on = $true; $go.Enabled = $false; $no.Enabled = $false
    $um.ForeColor = $Pal.muted; $um.Text = 'Đang tải bản mới…'; $done = $false
    try { Start-Release (Save-Release $rel); $done = $true }
    catch { $um.ForeColor = $Pal.red; $um.Text = $_.Exception.Message }
    finally { $busy.on = $false; $go.Enabled = $true; $no.Enabled = $true; Set-ButtonLook $go 'primary' }
    if ($done) { $d.DialogResult = 'OK' }
  })
  $no.add_Click({ if (-not $busy.on) { $d.DialogResult = 'Cancel' } })
  $d.add_FormClosing({ param($s, $e) if ($busy.on) { $e.Cancel = $true } })
  $d.Controls.AddRange(@($u1, $u2, $tb, $cb, $um, $go, $no)); $d.CancelButton = $no; $d.ActiveControl = $go
  $script:UpdUi = @{ d = $d; go = $go; msg = $um }   # tests
  if ($d.ShowDialog($form) -eq 'OK') { $form.Close() }
}
# called with the result of the background check
function Set-NewRelease($rel) {
  $script:NewRelease = $rel
  if (-not $rel) { return }
  $tagline.Visible = $false
  $updLink.Text = "⬆  Có bản mới $($rel.tag) - bấm để cập nhật"; $updLink.Visible = $true; $updLink.BringToFront()
  # automatic: once per version, so a failed update cannot loop
  if ((Get-Setting 'AutoUpdate' $false) -and ([string](Get-Setting 'AutoUpdateTried' '')) -ne $rel.tag -and -not $script:Busy -and $form.OwnedForms.Count -eq 0) {
    Set-Setting 'AutoUpdateTried' $rel.tag
    $updLink.Text = "Đang tự cập nhật $($rel.tag)…"
    $script:Busy = $true
    try { Start-Release (Save-Release $rel); $form.Close() }
    catch { $updLink.Text = "⬆  Có bản mới $($rel.tag) - bấm để cập nhật" }
    finally { $script:Busy = $false }
  }
}
# background check after the window is up; every error is silent (no network, GitHub blocked...)
function Start-UpdateCheck {
  $script:UpdWc = New-UpdateClient
  $script:UpdTask = $script:UpdWc.DownloadStringTaskAsync([Uri]$script:UpdateApi)
  $script:UpdTimer = New-Object Windows.Forms.Timer; $script:UpdTimer.Interval = 400
  $script:UpdTimer.add_Tick({
    if (-not $script:UpdTask.IsCompleted) { return }
    $script:UpdTimer.Stop()
    try { if (-not $script:UpdTask.IsFaulted -and -not $script:UpdTask.IsCanceled) { Set-NewRelease (Read-Release $script:UpdTask.Result) } } catch {}
    finally { $script:UpdWc.Dispose() }
  })
  $script:UpdTimer.Start()
}
function Invoke-UpdateCheckNow {
  try { $rel = Get-NewRelease }
  catch { [void][Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, $script:AppName, 'OK', 'Warning'); return }
  if ($rel) { $script:NewRelease = $rel; Show-Update $rel }
  else { [void][Windows.Forms.MessageBox]::Show($form, "Bạn đang dùng bản mới nhất ($($script:Version)).", $script:AppName, 'OK', 'Information') }
}

# ---------- feature request ----------
function Show-Feature {
  $d = New-SmallDialog 'Đề xuất tính năng' 480 496
  $fs = @{ busy = $false }
  $f1 = Put (New-Label 'Bạn muốn Steve AI Connect làm thêm việc gì?' $Fnt.h2 $Pal.text) 20 14 440 26
  $f2 = Put (New-Label 'Nội dung gửi thẳng tới Steve Tran. Đừng ghi thông tin mật của dự án.' $Fnt.s $Pal.muted) 20 42 440 18
  $l1 = Put (New-Label 'Loại' $Fnt.s $Pal.muted) 20 68 210 18; $cKind = Put (New-Combo) 20 87 214 28
  foreach ($t0 in 'Tính năng mới', 'Cải tiến tính năng có sẵn', 'Báo lỗi') { [void]$cKind.Items.Add($t0) }; $cKind.SelectedIndex = 0
  $l2 = Put (New-Label 'Dùng với' $Fnt.s $Pal.muted) 246 68 210 18; $cCad = Put (New-Combo) 246 87 214 28
  foreach ($t0 in 'Chung', 'ZWCAD', 'AutoCAD', 'ADSCivil') { [void]$cCad.Items.Add($t0) }; $cCad.SelectedIndex = 0
  $mk = { param($max) $b = New-Object Windows.Forms.TextBox; $b.BackColor = $Pal.input; $b.ForeColor = $Pal.text; $b.BorderStyle = 'FixedSingle'; $b.MaxLength = $max; $b }
  $l3 = Put (New-Label 'Tên tính năng' $Fnt.s $Pal.muted) 20 126 440 18; $tTitle = Put (& $mk 120) 20 145 440 26
  $l4 = Put (New-Label 'Mô tả: cần làm gì, dùng khi nào, kết quả mong muốn' $Fnt.s $Pal.muted) 20 180 440 18
  $tDesc = Put (& $mk 3000) 20 199 440 144; $tDesc.Multiline = $true; $tDesc.ScrollBars = 'Vertical'; $tDesc.AcceptsReturn = $true
  $l5 = Put (New-Label 'Email để Steve phản hồi' $Fnt.s $Pal.muted) 20 352 440 18; $tMail = Put (& $mk 120) 20 371 440 26
  $acc = Get-Setting 'Account'; if ($acc -and $acc.email) { $tMail.Text = [string]$acc.email }
  $fm = Put (New-Label '' $Fnt.s $Pal.muted) 20 404 440 36
  $go = Put (New-Button 'Gửi đề xuất' 'primary') 222 446 130 36
  $no = Put (New-Button 'Đóng') 360 446 100 36
  $go.add_Click({
    if ($fs.busy) { return }
    $bad = ''
    if ($tTitle.Text.Trim().Length -lt 5) { $bad = 'Tên tính năng cần ít nhất 5 ký tự.' }
    elseif ($tDesc.Text.Trim().Length -lt 15) { $bad = 'Mô tả thêm một chút (ít nhất 15 ký tự).' }
    elseif (-not (Test-EmailText $tMail.Text)) { $bad = 'Email chưa đúng.' }
    if ($bad) { $fm.ForeColor = $Pal.red; $fm.Text = $bad; return }
    $fs.busy = $true; $go.Enabled = $false; $no.Enabled = $false; $fm.ForeColor = $Pal.muted; $fm.Text = 'Đang gửi…'
    try {
      $r = Invoke-Register @{ action = 'feature'; email = $tMail.Text.Trim().ToLower(); kind = [string]$cKind.SelectedItem; cad = [string]$cCad.SelectedItem
        title = $tTitle.Text.Trim(); desc = $tDesc.Text.Trim(); version = [string]$script:Version }
    } finally { $fs.busy = $false; $go.Enabled = $true; $no.Enabled = $true; Set-ButtonLook $go 'primary' }
    if ($r.ok) { $tTitle.Text = ''; $tDesc.Text = ''; $fm.ForeColor = $Pal.green; $fm.Text = '✓ Đã gửi. Cảm ơn bạn, Steve sẽ xem và phản hồi qua email!' }
    else { $fm.ForeColor = $Pal.red; $fm.Text = $script:RegErrors[[string]$r.error] }
  })
  $no.add_Click({ if (-not $fs.busy) { $d.DialogResult = 'Cancel' } })
  $d.add_FormClosing({ param($s, $e) if ($fs.busy) { $e.Cancel = $true } })
  $d.Controls.AddRange(@($f1, $f2, $l1, $cKind, $l2, $cCad, $l3, $tTitle, $l4, $tDesc, $l5, $tMail, $fm, $go, $no)); $d.CancelButton = $no; $d.ActiveControl = $tTitle
  $script:FeatUi = @{ d = $d; title = $tTitle; desc = $tDesc; mail = $tMail; go = $go; msg = $fm; ui = $fs }   # tests
  [void]$d.ShowDialog($form)
}
