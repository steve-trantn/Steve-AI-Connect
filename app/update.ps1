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

# ---------- share a skill the user made ----------
function Get-OwnSkills {
  $out = @()
  foreach ($d in Get-ChildItem (Join-Path $script:Workspace 'skills') -Directory -ErrorAction SilentlyContinue) {
    $f = Join-Path $d.FullName 'SKILL.md'; if (-not (Test-Path -LiteralPath $f)) { continue }
    $t = [IO.File]::ReadAllText($f); $h = @{ title = ''; description = '' }
    foreach ($n in 'title', 'description') { if ($t -match "(?m)^$n`:\s*(.+)$") { $h[$n] = $Matches[1].Trim() } }
    $out += @{ name = $d.Name; title = $h.title; desc = $h.description; dir = $d.FullName }
  }
  return $out
}
$script:PackTypes = '.md', '.lsp', '.txt', '.csv', '.xlsx', '.png', '.jpg', '.jpeg'
function Get-Sha256([byte[]]$b) { $h = [Security.Cryptography.SHA256]::Create(); try { return [BitConverter]::ToString($h.ComputeHash($b)).Replace('-', '').ToLower() } finally { $h.Dispose() } }
# things the sender should look at before sharing; pictures and Excel files cannot be read here
function Find-Private([string]$s) {
  $o = @()
  foreach ($r in @(@('email', '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'), @('số điện thoại', '(?<![\d.])(?:\+?84|0)[ .\-]?\d{2,3}[ .\-]?\d{3}[ .\-]?\d{3,4}(?![\d.])'),
      @('đường dẫn', '(?i)(?<![A-Za-z])[A-Z]:[\\/][^\r\n"''<>|*?]{2,60}'), @('khoá / mật khẩu', '(?i)(sk-|AIza|ghp_)[A-Za-z0-9_\-]{8,}|(password|mật khẩu|api[ _-]?key)\s*[:=]\s*\S+'))) {
    $m = [regex]::Match($s, $r[1]); if ($m.Success) { $o += "$($r[0]): $($m.Value.Trim())" }
  }
  return $o
}
# the whole skill folder, byte for byte -> @{ error; files; notes; zip; sha; text }. Same files -> same zip on this PC (fixed dates, sorted).
function New-SkillPack([string]$dir) {
  Add-Type -AssemblyName System.IO.Compression
  $strict = New-Object Text.UTF8Encoding $false, $true
  $p = @{ error = ''; files = @(); notes = @(); skipped = @(); zip = $null; sha = ''; text = '' }
  $root = (Get-Item -LiteralPath $dir -Force).FullName.TrimEnd('\'); $total = 0; $list = @(); $todo = New-Object Collections.Queue; $todo.Enqueue($root)
  if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { $p.error = 'Thư mục skill là liên kết (shortcut) nên không gửi được.'; return $p }
  while ($todo.Count) {   # links are never followed: they could pull in files from elsewhere
    foreach ($i in Get-ChildItem -LiteralPath $todo.Dequeue() -Force) {
      $rel = $i.FullName.Substring($root.Length + 1).Replace('\', '/')
      if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { $p.error = "Có liên kết trong thư mục, hãy bỏ ra rồi thử lại: $rel"; return $p }
      if ($i.PSIsContainer) { $todo.Enqueue($i.FullName); continue }
      if ($i.Name -match '(?i)\.(bak|tmp)$|^(thumbs\.db|desktop\.ini)$|^~\$') { $p.skipped += $rel; continue }
      if ($script:PackTypes -notcontains $i.Extension.ToLower()) { $p.error = "Loại file không cho phép, hãy bỏ ra rồi thử lại: $rel"; return $p }
      $total += $i.Length; $list += @{ rel = $rel; path = $i.FullName }
      if ($list.Count -gt 60) { $p.error = 'Quá nhiều file (tối đa 60).'; return $p }
      if ($total -gt 20MB) { $p.error = 'Thư mục skill quá lớn (tối đa 20 MB trước khi nén).'; return $p }
    }
  }
  $names = [string[]]@($list | ForEach-Object { $_.rel }); [Array]::Sort($names, [StringComparer]::Ordinal); $by = @{}; foreach ($x in $list) { $by[$x.rel] = $x.path }
  if ($names -cnotcontains 'SKILL.md') { $p.error = 'Thiếu file SKILL.md (đúng chữ hoa, thường).'; return $p }
  $ms = New-Object IO.MemoryStream; $za = New-Object IO.Compression.ZipArchive $ms, ([IO.Compression.ZipArchiveMode]::Create), $true   # no encoding given: .NET sets the UTF-8 flag for names with accents
  $body = New-Object Text.StringBuilder
  try {
    foreach ($n in $names) {
      $b = [IO.File]::ReadAllBytes($by[$n])
      $en = $za.CreateEntry($n, [IO.Compression.CompressionLevel]::Optimal); $en.LastWriteTime = New-Object DateTimeOffset 2020, 1, 1, 0, 0, 0, ([TimeSpan]::Zero)
      $st = $en.Open(); try { $st.Write($b, 0, $b.Length) } finally { $st.Dispose() }
      $p.files += "$n  ($([Math]::Ceiling($b.Length / 1KB)) KB)"
      if ($n -notmatch '(?i)\.(md|lsp|txt|csv)$') { $p.notes += "${n}: chưa soát được nội dung, hãy tự xem"; continue }
      try { $t = $strict.GetString($b) } catch {
        if ($n -match '(?i)\.md$') { $p.error = "$n chưa lưu ở dạng UTF-8 (chữ Việt sẽ hỏng). Mở bằng Notepad > Save as > UTF-8 rồi thử lại."; return $p }
        $t = [Text.Encoding]::Default.GetString($b)   # preview only; the bytes are sent unchanged
      }
      $t = $t.TrimStart([char]0xFEFF)
      foreach ($x in Find-Private $t) { $p.notes += "$n - $x" }
      [void]$body.Append("`n===== $n =====`n$t`n")
    }
  } finally { $za.Dispose() }
  $z = $ms.ToArray(); $ms.Dispose()
  if ($z.Length -gt 5MB) { $p.error = 'Gói quá lớn (tối đa 5 MB).'; return $p }
  $p.zip = $z; $p.sha = Get-Sha256 $z; $p.text = $body.ToString()
  return $p
}
function Show-ShareSkill {
  $own = @(Get-OwnSkills)
  if (-not $own) { [void][Windows.Forms.MessageBox]::Show($form, "Bạn chưa có skill riêng.`n`nMở Steve AI, bấm ＋ → Tạo skill để AI giúp bạn viết một skill, rồi quay lại đây chia sẻ.", $script:AppName, 'OK', 'Information'); return }
  $d = New-SmallDialog 'Chia sẻ skill' 520 566
  $ss = @{ busy = $false; pack = $null; sure = $false }
  $c1 = Put (New-Label 'Chia sẻ skill của bạn cho mọi người' $Fnt.h2 $Pal.text) 20 14 480 26
  $c2 = Put (New-Label 'Gửi nguyên cả thư mục skill. Steve đọc và duyệt; được chọn thì skill có trong bản cập nhật, ghi công bạn. Xem kỹ để không gửi tên dự án, khách hàng, mật khẩu.' $Fnt.s $Pal.muted) 20 42 480 34
  $cb = Put (New-Combo) 20 82 480 28; foreach ($o in $own) { [void]$cb.Items.Add($(if ($o.title) { "$($o.title)  ($($o.name))" } else { $o.name })) }
  $mk = { param($max) $b = New-Object Windows.Forms.TextBox; $b.BackColor = $Pal.input; $b.ForeColor = $Pal.text; $b.BorderStyle = 'FixedSingle'; $b.MaxLength = $max; $b }
  $pv = Put (& $mk 0) 20 118 480 240; $pv.Multiline = $true; $pv.ReadOnly = $true; $pv.ScrollBars = 'Vertical'
  $l1 = Put (New-Label 'Tên ghi công (để trống = ẩn danh)' $Fnt.s $Pal.muted) 20 366 234 18; $tA = Put (& $mk 80) 20 385 234 26
  $l2 = Put (New-Label 'Email để Steve phản hồi' $Fnt.s $Pal.muted) 266 366 234 18; $tM = Put (& $mk 120) 266 385 234 26
  $acc = Get-Setting 'Account'; if ($acc -and $acc.email) { $tM.Text = [string]$acc.email }
  $ck = New-Object Windows.Forms.CheckBox; $ck.Text = 'Nội dung này do tôi viết (hoặc tôi được phép chia sẻ) và tôi đồng ý phát hành theo giấy phép Apache 2.0'; $ck.Font = $Fnt.s; $ck.ForeColor = $Pal.text; $ck.CheckAlign = 'TopLeft'; $ck.TextAlign = 'TopLeft'
  [void](Put $ck 20 420 480 38)
  $sm = Put (New-Label '' $Fnt.s $Pal.muted) 20 462 480 48
  $lk = Put (New-Link 'Mở thư mục lưu gói' $Fnt.s $Pal.accent) 20 526 160 18; $lk.Visible = $false
  $outDir = Join-Path $script:Workspace 'skills-da-gui'
  $lk.add_LinkClicked({ Start-Process explorer.exe "`"$outDir`"" })
  $go = Put (New-Button 'Gửi cho Steve' 'primary') 262 516 130 36; $no = Put (New-Button 'Đóng') 400 516 100 36
  $load = {
    $ss.sure = $false; $sm.Text = ''; $lk.Visible = $false
    try { $p = New-SkillPack $own[$cb.SelectedIndex].dir } catch { $p = @{ error = "Không đọc được thư mục skill: $($_.Exception.Message)" } }
    $ss.pack = $p
    if ($p.error) { $pv.Text = "KHÔNG GỬI ĐƯỢC`r`n`r`n$($p.error)"; return }
    $t = "GÓI GỒM $($p.files.Count) FILE, $([Math]::Ceiling($p.zip.Length / 1KB)) KB`n" + (($p.files | ForEach-Object { "  $_" }) -join "`n")
    if ($p.skipped) { $t += "`nKhông gửi (file tạm, sao lưu): " + ($p.skipped -join ', ') }
    if ($p.notes) { $t += "`n`n⚠ XEM LẠI TRƯỚC KHI GỬI`n" + (($p.notes | ForEach-Object { "  $_" }) -join "`n") }
    $t += "`n`nSHA-256: $($p.sha)`n$($p.text)"
    $pv.Text = ($t -replace '\r?\n', "`r`n")
  }
  $cb.add_SelectedIndexChanged({ & $load }); $cb.SelectedIndex = 0
  $go.add_Click({
    if ($ss.busy) { return }
    $sm.ForeColor = $Pal.red; $p = $ss.pack; $o = $own[$cb.SelectedIndex]
    if ($p.error) { $sm.Text = $p.error; return }
    if (-not (Test-EmailText $tM.Text)) { $sm.Text = 'Email chưa đúng.'; return }
    if (-not $ck.Checked) { $sm.Text = 'Cần tích đồng ý giấy phép để chia sẻ.'; return }
    if ($o.name.Length -gt 40 -or $o.name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $sm.Text = 'Tên thư mục skill phải là chữ thường không dấu, số và dấu -, tối đa 40 ký tự.'; return }
    if ($p.notes -and -not $ss.sure) { $ss.sure = $true; $sm.Text = 'Có mục cần xem lại (⚠ ở khung trên). Vẫn muốn gửi thì bấm Gửi lần nữa.'; return }
    $ss.busy = $true; foreach ($x in $go, $no, $cb, $tA, $tM, $ck) { $x.Enabled = $false }; $sm.ForeColor = $Pal.muted; $sm.Text = 'Đang gửi…'
    $file = ''; $r = $null
    try {
      # the copy on this PC comes first: whatever happens on the way, nothing is lost
      try { New-Item -ItemType Directory -Force $outDir | Out-Null; $f0 = Join-Path $outDir "$($o.name)-$($p.sha.Substring(0, 8)).zip"; [IO.File]::WriteAllBytes($f0, $p.zip); $file = $f0; $lk.Visible = $true } catch {}
      $r = Invoke-Register @{ action = 'skillpack'; email = $tM.Text.Trim().ToLower(); name = $o.name; title = $o.title; desc = $o.desc; author = $tA.Text.Trim(); license = $true; version = [string]$script:Version; sha = $p.sha; zip = [Convert]::ToBase64String($p.zip) } 240
    } finally { $ss.busy = $false; foreach ($x in $go, $no, $cb, $tA, $tM, $ck) { $x.Enabled = $true }; Set-ButtonLook $go 'primary' }
    if ($r.ok -and [string]$r.sha -ceq $p.sha -and $r.receipt) {   # only the server's receipt counts as "sent"
      $sm.ForeColor = $Pal.green; $sm.Text = "✓ Đã gửi nguyên vẹn. Mã biên nhận: $($r.receipt). Steve sẽ xem và phản hồi qua email."
      try { if ($file) { [IO.File]::AppendAllText((Join-Path $outDir 'bien-nhan.txt'), "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $($r.receipt)  $($o.name)  SHA-256 $($p.sha)`r`n", $script:Utf8) } } catch {}
    } else {
      $sm.ForeColor = $Pal.red; $e = [string]$r.error; if ($r.ok) { $e = 'server' }
      $sm.Text = $script:RegErrors[$e] + $(if ($file) { ' Gói đã lưu trên máy: gửi lại sau, hoặc gửi file đó cho Steve qua Zalo.' } else { '' })
    }
  })
  $no.add_Click({ if (-not $ss.busy) { $d.DialogResult = 'Cancel' } })
  $d.add_FormClosing({ param($s, $e) if ($ss.busy) { $e.Cancel = $true } })
  $d.Controls.AddRange(@($c1, $c2, $cb, $pv, $l1, $tA, $l2, $tM, $ck, $sm, $lk, $go, $no)); $d.CancelButton = $no
  $script:ShareUi = @{ d = $d; go = $go; ck = $ck; mail = $tM; msg = $sm; ui = $ss; pv = $pv; cb = $cb }   # tests
  [void]$d.ShowDialog($form)
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
