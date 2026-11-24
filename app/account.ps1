# Steve AI Connect - one-time registration / login (email code). Dot-source after core.ps1.
# The only data sent: email, name, phone, the two consent ticks and the tool version. After that nothing is
# sent any more: a registered PC works offline. Server side: register\Code.gs.
$script:TrialDays = 7

function Test-Registered { $a = Get-Setting 'Account'; return [bool]($a -and $a.email) }
# days left of the "could not reach the server" trial; 0 = none or over
function Get-TrialLeft {
  $t = [string](Get-Setting 'TrialStart' ''); if (-not $t) { return 0 }
  try { $d0 = [DateTime]::ParseExact($t, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { return 0 }
  $used = ([DateTime]::Today - $d0).Days
  if ($used -lt 0) { return 0 }
  return [Math]::Max(0, $script:TrialDays - $used)
}
function Start-Trial { if (-not (Get-Setting 'TrialStart' '')) { Set-Setting 'TrialStart' ([DateTime]::Today.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)) } }
# no server address in this build = registration is off
function Test-AccessOk { return (-not $script:RegisterUrl) -or (Test-Registered) -or ((Get-TrialLeft) -gt 0) }

function Test-EmailText([string]$s) { return $s.Trim() -match '^[A-Za-z0-9][A-Za-z0-9._%+\-]*@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$' }
function Get-PhoneText([string]$s) { return (($s -replace '[^\d+]', '') -replace '^\+?84', '0') }
function Test-PhoneText([string]$s) { return (Get-PhoneText $s) -match '^0\d{8,10}$' }

$script:RegErrors = @{
  email = 'Email chưa đúng.'; wait = 'Vừa gửi mã rồi. Đợi 1 phút rồi bấm gửi lại.'
  limit = 'Email này đã nhận quá nhiều mã. Thử lại sau 1 giờ.'; quota = 'Hôm nay hệ thống đã gửi hết số email cho phép. Thử lại ngày mai.'
  code = 'Mã chưa đúng. Kiểm tra lại email.'; expired = 'Mã đã hết hạn hoặc nhập sai quá nhiều lần. Bấm gửi mã mới.'
  profile = 'Email này chưa đăng ký. Điền họ tên, SĐT, tích đồng ý rồi bấm Xác nhận lại.'
  busy = 'Máy chủ đang bận. Thử lại sau ít giây.'; server = 'Máy chủ đăng ký gặp lỗi. Thử lại sau.'
  many = 'Bạn đã gửi nhiều đề xuất rồi. Thử lại sau vài giờ.'; empty = 'Thông tin chưa đủ hoặc chưa hợp lệ.'
  sha = 'Gói tới máy chủ không nguyên vẹn. Bấm gửi lại.'; file = 'Máy chủ không nhận gói này (quá lớn hoặc có file không cho phép).'
  full = 'Hộp nhận skill đang đầy.'
  network = 'Không kết nối được máy chủ đăng ký. Kiểm tra mạng Internet.'
}
# these are not the user's fault: they may start the trial
$script:RegTrialErrors = 'network', 'server', 'quota', 'busy'

function Invoke-Register([hashtable]$body, [int]$seconds = 40) {
  $fail = { param($e) [pscustomobject]@{ ok = $false; error = $e; name = '' } }
  $wc = $null
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('Content-Type', 'application/json; charset=utf-8')
    if ($wc.Proxy) { $wc.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress))
    $task = $wc.UploadDataTaskAsync([Uri]$script:RegisterUrl, 'POST', $bytes)
    $end = [DateTime]::Now.AddSeconds($seconds)
    while (-not $task.IsCompleted) {
      if ([DateTime]::Now -gt $end) { $wc.CancelAsync(); return (& $fail 'network') }
      Invoke-UiPump; Start-Sleep -Milliseconds 40
    }
    if ($task.IsFaulted -or $task.IsCanceled) { return (& $fail 'network') }
    $o = [Text.Encoding]::UTF8.GetString($task.Result) | ConvertFrom-Json
  } catch { return (& $fail 'server') } finally { if ($wc) { $wc.Dispose() } }
  if ($o.ok -eq $true) { return $o }
  if ($o.error -and $script:RegErrors.ContainsKey([string]$o.error)) { return $o }
  return (& $fail 'server')
}
function Save-Account([string]$email, [string]$name) {
  Set-Setting 'Account' ([pscustomobject]@{ email = $email; name = $name; at = [DateTime]::Now.ToString('yyyy-MM-dd') })
}

# ---------- dialog (needs gui.ps1) ----------
# returns $true when the tool may be used (registered, or trial running)
function Show-Register {
  $d = New-SmallDialog 'Đăng ký / Đăng nhập' 440 470
  $ui = @{ login = $false; busy = $false; sentTo = ''; trial = ((Get-TrialLeft) -gt 0) }
  $mk = { param($max) $b = New-Object Windows.Forms.TextBox; $b.BackColor = $Pal.input; $b.ForeColor = $Pal.text; $b.BorderStyle = 'FixedSingle'; $b.MaxLength = $max; $b }
  $hd = New-Label '' $Fnt.h2 $Pal.text
  $sub = New-Label '' $Fnt.n $Pal.muted
  $lEm = New-Label 'Email' $Fnt.s $Pal.muted;         $tEm = & $mk 120
  $lNm = New-Label 'Họ và tên' $Fnt.s $Pal.muted;     $tNm = & $mk 80
  $lPh = New-Label 'Số điện thoại' $Fnt.s $Pal.muted; $tPh = & $mk 20
  $cb1 = New-Object Windows.Forms.CheckBox; $cb1.Text = 'Tôi đồng ý để Steve Tran lưu email, họ tên, SĐT để hỗ trợ và báo bản cập nhật (bắt buộc)'
  $cb2 = New-Object Windows.Forms.CheckBox; $cb2.Text = 'Nhận giới thiệu sản phẩm, đào tạo BIM (không bắt buộc)'
  foreach ($c0 in $cb1, $cb2) { $c0.Font = $Fnt.s; $c0.ForeColor = $Pal.text; $c0.BackColor = [Drawing.Color]::Transparent; $c0.CheckAlign = 'TopLeft'; $c0.TextAlign = 'TopLeft' }
  $bSend = New-Button 'Gửi mã về email' 'primary'
  $lCd = New-Label 'Mã 6 số trong email (xem cả mục Spam)' $Fnt.s $Pal.muted; $tCd = & $mk 6
  $bOk = New-Button 'Xác nhận' 'primary'
  $msg = New-Label '' $Fnt.s $Pal.muted
  $lkMode = New-Link '' $Fnt.s $Pal.accent
  $lkTrial = New-Link '' $Fnt.s $Pal.muted; $lkTrial.TextAlign = 'TopRight'

  $layout = {
    $reg = -not $ui.login
    $hd.Text = $(if ($reg) { 'Đăng ký một lần để sử dụng' } else { 'Đăng nhập' })
    $sub.Text = $(if ($reg) { 'Miễn phí. Đăng ký xong, máy này dùng được cả khi không có mạng. Bản vẽ của bạn không bị gửi về máy chủ đăng ký.' } else { 'Dành cho người đã đăng ký: nhập email, nhận mã, xác nhận là xong.' })
    $lkMode.Text = $(if ($reg) { 'Đã đăng ký rồi? Đăng nhập' } else { 'Chưa có tài khoản? Đăng ký' })
    foreach ($c1 in $lNm, $tNm, $lPh, $tPh, $cb1, $cb2) { $c1.Visible = $reg }
    $y = 14
    [void](Put $hd 20 $y 400 26); $y += 28
    [void](Put $sub 20 $y 400 38); $y += 44
    [void](Put $lEm 20 $y 400 18); [void](Put $tEm 20 ($y + 19) 400 26); $y += 52
    if ($reg) {
      [void](Put $lNm 20 $y 230 18); [void](Put $tNm 20 ($y + 19) 230 26)
      [void](Put $lPh 262 $y 158 18); [void](Put $tPh 262 ($y + 19) 158 26); $y += 54
      [void](Put $cb1 20 $y 400 38); $y += 40
      [void](Put $cb2 20 $y 400 22); $y += 28
    }
    [void](Put $bSend 20 $y 400 34); $y += 46
    [void](Put $lCd 20 $y 400 18); [void](Put $tCd 20 ($y + 21) 230 26); [void](Put $bOk 262 ($y + 18) 158 32); $y += 60
    [void](Put $msg 20 $y 400 38); $y += 42
    [void](Put $lkMode 20 $y 190 18); [void](Put $lkTrial 212 $y 208 18)
    $left = Get-TrialLeft
    $lkTrial.Visible = [bool]$ui.trial
    $lkTrial.Text = $(if ($left -gt 0) { "Để sau (còn dùng tạm $left ngày)" } else { "Dùng tạm $($script:TrialDays) ngày" })
    $d.ClientSize = New-Object Drawing.Size (S 440), (S ($y + 30))
    $tCd.Enabled = [bool]$ui.sentTo; $bOk.Enabled = [bool]$ui.sentTo
    if ($bOk.Enabled) { Set-ButtonLook $bOk 'primary' }
    $bSend.Text = $(if ($ui.sentTo) { 'Gửi lại mã' } else { 'Gửi mã về email' })
    $d.AcceptButton = $(if ($ui.sentTo) { $bOk } else { $bSend })
  }
  $say = { param($t, $col) $msg.ForeColor = $col; $msg.Text = $t }
  $check = {   # first problem in the form, or ''
    if (-not (Test-EmailText $tEm.Text)) { return 'Email chưa đúng.' }
    if (-not $ui.login) {
      if ($tNm.Text.Trim().Length -lt 2) { return 'Vui lòng nhập họ và tên.' }
      if (-not (Test-PhoneText $tPh.Text)) { return 'Số điện thoại chưa đúng, ví dụ 0912 345 678.' }
      if (-not $cb1.Checked) { return 'Cần tích đồng ý lưu thông tin để đăng ký.' }
    }
    return ''
  }
  $inputs = @($tEm, $tNm, $tPh, $cb1, $cb2, $bSend, $lkMode, $lkTrial)
  $call = { param($body)
    $ui.busy = $true
    foreach ($c2 in ($inputs + @($bOk, $tCd))) { $c2.Enabled = $false }
    & $say 'Đang kết nối…' $Pal.muted
    try { $r = Invoke-Register $body }
    finally { $ui.busy = $false; foreach ($c2 in $inputs) { $c2.Enabled = $true } }
    if (-not $r.ok) {
      # a trial that is already used up is not offered again
      if ($r.error -in $script:RegTrialErrors -and -not (Get-Setting 'TrialStart' '')) { $ui.trial = $true }
      if ($r.error -eq 'profile') { $ui.login = $false }
      if ($r.error -eq 'expired') { $ui.sentTo = ''; $tCd.Text = '' }
    }
    & $layout
    if (-not $r.ok) { & $say $script:RegErrors[[string]$r.error] $(if ($r.error -eq 'profile') { $Pal.warn } else { $Pal.red }) }
    return $r
  }
  $bSend.add_Click({
    if ($ui.busy) { return }
    $bad = & $check; if ($bad) { & $say $bad $Pal.red; return }
    $em = $tEm.Text.Trim().ToLower()
    $r = & $call @{ action = 'send'; email = $em }
    if ($r.ok) { $ui.sentTo = $em; $tCd.Text = ''; & $layout; & $say "✓ Đã gửi mã tới $em. Mã có hiệu lực 10 phút." $Pal.green; [void]$tCd.Focus() }
  })
  $bOk.add_Click({
    if ($ui.busy) { return }
    $bad = & $check; if ($bad) { & $say $bad $Pal.red; return }
    $em = $tEm.Text.Trim().ToLower()
    if ($em -ne $ui.sentTo) { & $say 'Email đã đổi. Bấm Gửi lại mã.' $Pal.red; return }
    if ($tCd.Text.Trim() -notmatch '^\d{6}$') { & $say 'Mã gồm 6 chữ số.' $Pal.red; return }
    $body = @{ action = 'verify'; email = $em; code = $tCd.Text.Trim(); version = [string]$script:Version }
    if (-not $ui.login) { $body.name = $tNm.Text.Trim(); $body.phone = Get-PhoneText $tPh.Text; $body.consent = [bool]$cb1.Checked; $body.news = [bool]$cb2.Checked }
    $r = & $call $body
    if ($r.ok) { Save-Account $em ([string]$r.name); $d.Close() }
  })
  $lkMode.add_LinkClicked({ if (-not $ui.busy) { $ui.login = -not $ui.login; & $say '' $Pal.muted; & $layout } })
  $lkTrial.add_LinkClicked({ if (-not $ui.busy) { Start-Trial; $d.Close() } })
  $d.add_FormClosing({ param($s, $e) if ($ui.busy) { $e.Cancel = $true } })   # a call is running
  $d.Controls.AddRange(@($hd, $sub, $lEm, $tEm, $lNm, $tNm, $lPh, $tPh, $cb1, $cb2, $bSend, $lCd, $tCd, $bOk, $msg, $lkMode, $lkTrial))
  & $layout
  $script:RegUi = @{ d = $d; em = $tEm; nm = $tNm; ph = $tPh; c1 = $cb1; send = $bSend; code = $tCd; ok = $bOk; msg = $msg; ui = $ui; layout = $layout }   # tests
  [void]$d.ShowDialog($form)
  return (Test-AccessOk)
}
