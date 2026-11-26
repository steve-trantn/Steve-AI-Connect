# Steps run inside the real window (STEVECAD_REGTEST, see run.ps1): share a skill, -Open, ribbon, report, help, one window per build.
$script:RegisterUrl = 'http://127.0.0.1:8767/'
$script:Workspace = $env:STEVECAD_WS
$sk = Join-Path $script:Workspace 'skills'
$wb = New-Object Net.WebClient; $wb.Encoding = [Text.Encoding]::UTF8
function Get-St { $wb.DownloadString('http://127.0.0.1:8767/state') | ConvertFrom-Json }
function Set-Mode($m) { [void]$wb.DownloadString("http://127.0.0.1:8767/mode?m=$m") }
$u8 = New-Object Text.UTF8Encoding $false
function New-Skill($n, $md) { $p = Join-Path $sk $n; New-Item -ItemType Directory -Force $p | Out-Null; [IO.File]::WriteAllText("$p\SKILL.md", $md, $u8); $p }
$base = "---`nname: thu`ntitle: Thử nghiệm đường cong`ndescription: Mô tả thử tiếng Việt`n---`n`nBước 1. Gọi info`tđọc `"bản vẽ`" ạ ệ ữ`r`nBước 2`n"
$a = New-Skill 'a-thu' $base
New-Item -ItemType Directory -Force "$a\phu lục" | Out-Null
[IO.File]::WriteAllBytes("$a\phu lục\mẫu.lsp", [byte[]](40, 100, 0xE0, 0xFF, 0x80, 41))      # not UTF-8
$rnd = New-Object byte[] 900000; (New-Object Random 5).NextBytes($rnd); [IO.File]::WriteAllBytes("$a\anh.png", $rnd)
[IO.File]::WriteAllText("$a\SKILL.md.bak", 'old', $u8)
$x = New-Skill 'b-exe' $base; [IO.File]::WriteAllText("$x\chay.exe", 'x')
$x = New-Skill 'c-ansi' $base; [IO.File]::WriteAllBytes("$x\SKILL.md", [byte[]](0x2D, 0xE0, 0xEA, 0x2D))
$x = New-Skill 'd-rieng' ($base + "Liên hệ khach@congty.vn 0987 779 228, D:\DuAn\abc.dwg, mật khẩu: 123`n")
$x = New-Skill 'e-link' $base; cmd /c mklink /J "$x\lk" "$env:WINDIR\Help" | Out-Null
$x = New-Skill 'f-dai' ($base + ('dòng dài ' * 9000))
$x = New-Skill 'g-to' $base; $r2 = New-Object byte[] 5300000; (New-Object Random 6).NextBytes($r2); [IO.File]::WriteAllBytes("$x\a.png", $r2)
$x = New-Skill 'h-gan5mb' $base; $r3 = New-Object byte[] 5150000; (New-Object Random 7).NextBytes($r3); [IO.File]::WriteAllBytes("$x\a.png", $r3)
function Pk($n) { New-SkillPack (Join-Path $sk $n) }

# drive the real dialog: pick a skill, click Send the given number of times, return the last message
function Send-Ui($n, $clicks = 1) {
  $script:uM = ''; $script:uI = 0; $script:uN = $n; $script:uC = $clicks; $script:uErr = ''
  $tm = New-Object Windows.Forms.Timer; $tm.Interval = 300
  $tm.add_Tick({ $u = $script:ShareUi; if (-not $u -or $u.ui.busy) { return }
    try {
      if ($script:uI -eq 0) { $ix = -1; for ($q = 0; $q -lt $u.cb.Items.Count; $q++) { if ("$($u.cb.Items[$q])" -like "*($script:uN)") { $ix = $q } }; $u.cb.SelectedIndex = $ix; $u.mail.Text = 'a@b.vn'; $u.ck.Checked = $true }
      elseif ($script:uI -le $script:uC) { $u.go.PerformClick() }
      else { $script:uM = $u.msg.Text; $this.Stop(); $u.d.Close(); return }
      $script:uI++
    } catch { $script:uErr = "$_"; $this.Stop(); $u.d.Close() } })
  $script:ShareUi = $null; $tm.Start(); Show-ShareSkill; $tm.Stop(); if ($script:uErr) { throw $script:uErr }
  return $script:uM
}
function Unzip-B64($b64) {
  Add-Type -AssemblyName System.IO.Compression
  $m = New-Object IO.MemoryStream (, [Convert]::FromBase64String($b64)); $zz = New-Object IO.Compression.ZipArchive $m
  $h = @{}; foreach ($e in $zz.Entries) { $s0 = $e.Open(); $o = New-Object IO.MemoryStream; $s0.CopyTo($o); $h[$e.FullName] = Get-Sha256 $o.ToArray() }; return $h
}
& $try 'PACK đóng gói lặp lại ra cùng SHA' { if ((Pk 'a-thu').sha -ne (Pk 'a-thu').sha) { throw 'x' } }
& $try 'PACK chặn exe' { if ((Pk 'b-exe').error -notlike '*không cho phép*') { throw 'x' } }
& $try 'PACK chặn md không UTF-8' { if ((Pk 'c-ansi').error -notlike '*UTF-8*') { throw (Pk 'c-ansi').error } }
& $try 'PACK chặn liên kết' { if ((Pk 'e-link').error -notlike '*liên kết*') { throw 'x' } }
& $try 'PACK chặn quá 5MB' { if ((Pk 'g-to').error -notlike '*5 MB*') { throw (Pk 'g-to').error } }
& $try 'PACK cảnh báo thông tin riêng (4 loại)' { $k = (Pk 'd-rieng').notes; if (@($k).Count -ne 4) { throw ($k -join ' | ') } }
& $try 'UI phải bấm lần hai khi có cảnh báo' { $m = Send-Ui 'd-rieng' 1; if ($m -notlike '*lần nữa*') { throw $m } }
& $try 'UI gửi, giữ nguyên từng byte' {
  $m = Send-Ui 'a-thu' 2; if ($m -notlike '*Mã biên nhận: SK-*') { throw $m }
  $s = Get-St; $f = @($s.drive)[0]; $h = Unzip-B64 $f.zip
  foreach ($n in 'SKILL.md', 'phu lục/mẫu.lsp', 'anh.png') { $d0 = Get-Sha256 ([IO.File]::ReadAllBytes((Join-Path "$sk\a-thu" $n))); if ($h[$n] -ne $d0) { throw "$n khác" } }
  if ($h.Count -ne 3) { throw "số file $($h.Count)" }
  if (@($s.rows).Count -ne 2 -or $s.rows[1][10] -notlike '*phu lục/mẫu.lsp*' -or $s.rows[1][13] -ne 'Mới') { throw ($s.rows | ConvertTo-Json -Compress) }
  $z = @(Get-ChildItem "$script:Workspace\skills-da-gui\*.zip"); if ($z.Count -ne 1 -or (Get-Sha256 ([IO.File]::ReadAllBytes($z[0].FullName))) -ne $s.rows[1][12]) { throw 'bản sao' }
  if (-not (Test-Path "$script:Workspace\skills-da-gui\bien-nhan.txt")) { throw 'biên nhận' } }
& $try 'UI gửi lại không tạo trùng' { $m = Send-Ui 'a-thu' 2; if ($m -notlike '*SK-*') { throw $m }; $s = Get-St; if (@($s.drive).Count -ne 1 -or @($s.rows).Count -ne 2) { throw 'trùng' } }
& $try 'UI gửi skill dài > 60.000 ký tự' { $m = Send-Ui 'f-dai' 1; if ($m -notlike '*SK-*') { throw $m } }
& $try 'UI gửi gói gần 5MB' { $m = Send-Ui 'h-gan5mb' 2; if ($m -notlike '*SK-*') { throw $m } }
[void]$wb.DownloadString('http://127.0.0.1:8767/reset')
& $try 'MẠNG mất trả lời: báo lỗi, gửi lại không trùng' {
  [void](New-Skill 'i-mang' ($base + 'i')); Set-Mode 'drop'; $c0 = @((Get-St).drive).Count; $m = Send-Ui 'i-mang' 1; if ($m -like '*Đã gửi*' -or $m -notlike '*lưu trên máy*') { throw $m }
  Set-Mode ''; $m = Send-Ui 'i-mang' 1; if ($m -notlike '*SK-*') { throw $m }; if (@((Get-St).drive).Count -ne $c0 + 1) { throw 'trùng' } }
& $try 'MÁY CHỦ không trả biên nhận thì không báo đã gửi' { [void](New-Skill 'j-bn' ($base + 'j')); Set-Mode 'noreceipt'; $m = Send-Ui 'j-bn' 1; Set-Mode ''; if ($m -like '*Đã gửi*') { throw $m } }
& $try 'MÁY CHỦ Drive ghi hỏng: bỏ file, báo lỗi' { [void](New-Skill 'k-hong' ($base + 'k')); Set-Mode 'corrupt'; $m = Send-Ui 'k-hong' 1; Set-Mode ''; if ($m -like '*Đã gửi*') { throw $m }; if (-not @((Get-St).drive)[-1].trashed) { throw 'chưa bỏ' } }
& $try 'MÁY CHỦ ghi dòng lỗi: bỏ file' { Set-Mode 'rowfail'; $m = Send-Ui 'k-hong' 1; Set-Mode ''; if ($m -like '*Đã gửi*') { throw $m }; if (-not @((Get-St).drive)[-1].trashed) { throw 'chưa bỏ' } }
& $try 'MÁY CHỦ đầy' { Set-Mode 'full'; $m = Send-Ui 'k-hong' 1; Set-Mode ''; if ($m -notlike '*đang đầy*') { throw $m } }
& $try 'MÁY CHỦ từ chối sai SHA, zip lạ, loại file lạ' {
  $mkz = { param($names) $q = New-Object IO.MemoryStream; $w = New-Object IO.Compression.ZipArchive $q, 'Create', $true; foreach ($n in $names) { $g = $w.CreateEntry($n).Open(); $g.WriteByte(65); $g.Dispose() }; $w.Dispose(); , $q.ToArray() }
  $send = { param([byte[]]$z, $sha) if (-not $sha) { $sha = Get-Sha256 $z }; (Invoke-Register @{ action = 'skillpack'; email = 'a@b.vn'; name = 'x'; license = $true; sha = $sha; zip = [Convert]::ToBase64String($z) }).error }
  $g = & $mkz @('SKILL.md')
  if ((& $send $g ('0' * 64)) -ne 'sha') { throw 'sha' }
  foreach ($bad in @(, @('SKILL.md', 'a.exe')), @(, @('SKILL.md', '../a.md')), @(, @('a.md')), @(, @('SKILL.md', 'C:\a.md'))) { $e = & $send (& $mkz $bad[0]); if ($e -ne 'file') { throw "$($bad[0]) -> $e" } }
  if ((& $send ([byte[]](1..60))) -ne 'file') { throw 'rác' } }
& $try 'MÁY CHỦ chỉ tạo một thư mục' { if ((Get-St).folders -ne 1) { throw 'x' } }

$me = Join-Path $script:Root 'app\SteveCADConnect.ps1'
$script:Workspace = $env:STEVECAD_WS
function Req($part) {   # a second start, exactly like the CAD command; returns seconds until it left and what was open
  $script:seen = ''; $script:hits = @()
  $p = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$me`" -Open $part" -PassThru -WindowStyle Hidden
  $script:proc = $p
  $tm = New-Object Windows.Forms.Timer; $tm.Interval = 300
  $tm.add_Tick({ $o = @($form.OwnedForms | Where-Object { $_.Visible })[0]; if ($o) { $script:seen = $o.Text; if ($script:proc.HasExited) { $o.Close() } } })
  $tm.Start(); $end = [DateTime]::Now.AddSeconds(15)
  while ([DateTime]::Now -lt $end -and -not $p.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
  $e2 = [DateTime]::Now.AddSeconds(2); while ([DateTime]::Now -lt $e2) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
  $tm.Stop()
  if (-not $p.HasExited) { $p.Kill(); throw 'tiến trình thứ hai không thoát' }
  if ([IO.File]::Exists($script:OpenFile)) { throw 'còn file yêu cầu' }
}
$oldRep = ${function:Show-Report}
function script:Show-Report { $script:hits += 'diag' }
function script:Invoke-UpdateCheckNow { $script:hits += 'update' }
& $try 'OPEN share' { Req 'share'; if ($script:seen -ne 'Chia sẻ skill') { throw "thấy '$($script:seen)'" } }
& $try 'OPEN feature' { Req 'feature'; if ($script:seen -ne 'Đề xuất tính năng') { throw "thấy '$($script:seen)'" } }
& $try 'OPEN diag' { Req 'diag'; if ("$($script:hits)" -ne 'diag') { throw "$($script:hits)" } }
& $try 'OPEN update' { Req 'update'; if ("$($script:hits)" -ne 'update') { throw "$($script:hits)" } }
& $try 'OPEN help' { Req 'help'; if ($script:seen -notlike 'Hướng dẫn*') { throw "thấy '$($script:seen)'" } }
& $try 'OPEN options mở menu' { $script:mo = $false; $h = { $script:mo = $true }; $menu.add_Opened($h); Req 'options'; $menu.Close(); if (-not $script:mo) { throw 'menu không mở' } }
& $try 'OPEN home khi đang thu nhỏ' { Show-Page 'tools'; $form.WindowState = 'Minimized'; Req 'home'; if ($form.WindowState -ne 'Normal' -or $script:Page -ne 'home') { throw "$($form.WindowState) $($script:Page)" } }
& $try 'OPEN khi đang bận: không mở gì' { $script:Busy = $true; try { Req 'diag' } finally { $script:Busy = $false }; if ($script:hits.Count) { throw 'đã mở' } }
& $try 'OPEN lần đầu (-Open khi chưa có cửa sổ)' { $script:hits = @(); $script:OpenNext = 'diag'; $e = [DateTime]::Now.AddSeconds(2); while ([DateTime]::Now -lt $e) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }; if ("$($script:hits)" -ne 'diag') { throw 'x' } }
& $try 'OPEN giá trị lạ bị từ chối' { $q = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$me`" -Open xyz" -PassThru -WindowStyle Hidden -Wait; if ($q.ExitCode -eq 0) { throw 'nhận' } }
& $try 'RIBBON sinh menu: XML hợp lệ, 7 nút, icon, lệnh có thật' {
  Write-CadMenu
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($script:CadMenu); $uids = @()
  try { foreach ($e in $z.Entries) { if ($e.FullName -notlike '*.cui') { continue }; $r = New-Object IO.StreamReader $e.Open(); $x = [xml]$r.ReadToEnd(); $r.Dispose()
      foreach ($n in $x.SelectNodes('//RibbonCommandButton|//RibbonRowPanel|//RibbonRow|//MenuMacro|//PopMenuItem')) { $uids += $n.UID }
      if ($e.FullName -like '*RibbonRoot*') { $n7 = @($x.SelectNodes("//RibbonPanelSource[@UID='RBN_SAI_P_CONN']//RibbonCommandButton")).Count; $miss = @($x.SelectNodes('//RibbonCommandButton') | ForEach-Object { $_.MenuMacroID }) }
      if ($e.FullName -like '*MenuGroup*') { $mm = @($x.SelectNodes('//MenuMacro') | ForEach-Object { $_.UID }) } } } finally { $z.Dispose() }
  if ($n7 -ne 7) { throw "nút: $n7" }
  if (@($uids | Group-Object | Where-Object { $_.Count -gt 1 }).Count) { throw 'UID trùng' }
  foreach ($m in $miss) { if ($mm -notcontains $m) { throw "thiếu macro $m" } }
  $lsp = [IO.File]::ReadAllText((Join-Path $script:Root 'templates\SteveAI.lsp'))
  $rows = @([IO.File]::ReadAllLines((Join-Path $script:AppHome 'ribbon.txt')) | Where-Object { $_ -like "Hỗ trợ`t*" })
  $tit = @([IO.File]::ReadAllLines((Join-Path $script:AppHome 'ribbon.txt')) | ForEach-Object { ($_ -split "`t")[0] } | Select-Object -Unique)
  if (($tit -join '|') -ne 'Trợ lý AI|Bản vẽ|Khối lượng|Mô hình 3D / BIM|Kiểm tra KCS|Chuyển đổi|Skill của tôi|Hỗ trợ') { throw "nhóm: $($tit -join '|')" }
  if (@($miss).Count -ne @([IO.File]::ReadAllLines((Join-Path $script:AppHome 'ribbon.txt'))).Count) { throw 'ribbon.txt và cuix khác số nút' }
  if ($rows.Count -ne 7) { throw "ribbon.txt $($rows.Count)" }
  foreach ($l in $rows) { $f = $l -split "`t"; $c = ($f[4] -split ' ')[-1]; if (-not $lsp.Contains("(defun c:$c ")) { throw "thiếu lệnh $c" }; if (-not (Test-Path (Join-Path $script:AppHome "icons\$($f[5])16.png"))) { throw "thiếu icon $($f[5])" } }
  $d = 0; foreach ($ch in ($lsp -replace '(?m);.*$', '' -replace '"(\\.|[^"\\])*"', '').ToCharArray()) { if ($ch -eq '(') { $d++ } elseif ($ch -eq ')') { $d-- } }; if ($d) { throw "ngoặc LISP lệch $d" }
  # sheet of the new icons, for a look
  $b = New-Object Drawing.Bitmap 720, 150; $g = [Drawing.Graphics]::FromImage($b); $g.Clear([Drawing.Color]::FromArgb(59, 68, 83)); $g.FillRectangle([Drawing.Brushes]::WhiteSmoke, 360, 0, 360, 150); $i = 0
  foreach ($n in 'connect', 'update', 'options', 'share', 'feature', 'diag', 'help') { foreach ($ox in 0, 360) { $g.DrawImage((New-DrawnIcon $n 32), ($ox + 8 + $i * 50), 20, 48, 48); $g.DrawImage((New-DrawnIcon $n 16), ($ox + 14 + $i * 50), 100, 16, 16) }; $i++ }
  $b.Save("$env:STEVECAD_WS\icons.png"); $g.Dispose(); $b.Dispose()
}

Set-Item function:script:Show-Report $oldRep
$saved = $script:RegisterUrl
$wb2 = New-Object Net.WebClient; $wb2.Encoding = [Text.Encoding]::UTF8
function Feat { $wb2.DownloadString('http://127.0.0.1:8767/feat') | ConvertFrom-Json }
# run a dialog function while a timer does the steps; every step is a scriptblock
function Drive([scriptblock]$open, [scriptblock[]]$steps, $uiName) {
  $script:dI = 0; $script:dE = ''; $script:dS = $steps; $script:dU = $uiName
  Set-Variable -Scope Script -Name $uiName -Value $null
  $tm = New-Object Windows.Forms.Timer; $tm.Interval = 300
  $tm.add_Tick({ $u = (Get-Variable -Scope Script -Name $script:dU).Value; if (-not $u -or ($u.ui -and $u.ui.busy)) { return }
    try { if ($script:dI -lt $script:dS.Count) { & $script:dS[$script:dI] $u; $script:dI++ } else { $this.Stop(); if ($u.d.Visible) { $u.d.Close() } } } catch { $script:dE = "$_"; $this.Stop(); $u.d.Close() } })
  $tm.Start(); & $open; $tm.Stop(); if ($script:dE) { throw $script:dE }
}
& $try 'BÁO LỖI mất mạng: giữ nội dung' {
  $script:RegisterUrl = 'http://127.0.0.1:9/'; Set-Setting 'ReportDraft' ''
  Drive { Show-Report } @({ param($u) $u.say.Text = 'ngắn'; $u.mail.Text = 'a@b.vn'; $u.go.PerformClick(); if ($u.msg.Text -notlike '*15 ký tự*') { throw $u.msg.Text } },
    { param($u) $u.say.Text = "Bấm bóc khối lượng`r`nthì treo, lỗi ạ"; $u.go.PerformClick() }, { param($u) if ($u.msg.Text -notlike '*giữ lại*') { throw $u.msg.Text } }) 'RepUi'
  if ((Get-Setting 'ReportDraft' '') -notlike '*bóc khối*') { throw 'mất nháp' } }
$script:RegisterUrl = 'http://127.0.0.1:8767/'
& $try 'BÁO LỖI gửi: đúng nội dung xem trước, đã lọc, xoá nháp, không gửi đôi' {
  Add-ErrorLog 'test' "Loi o C:\Users\$env:USERNAME\DuAn\mat.dwg lien he ong@x.vn"
  Drive { Show-Report } @({ param($u) if ($u.say.Text -notlike '*bóc khối*') { throw 'không có nháp' }; $u.mail.Text = 'a@b.vn'; $script:pvT = $u.pv.Text -replace "`r`n", "`n"; $u.go.PerformClick() },
    { param($u) if ($u.msg.Text -notlike '*Đã gửi*') { throw $u.msg.Text }; $u.go.PerformClick() }, { param($u) if ($u.msg.Text -notlike '*đã gửi rồi*') { throw $u.msg.Text } }) 'RepUi'
  $z = Feat; if ($z.Count -ne 2) { throw "dòng $($z.Count)" }; $r = $z[1]
  if ($r[4] -ne 'Báo lỗi' -or $r[6] -notlike 'Báo lỗi: Bấm bóc*' -or $r[7] -cne $script:pvT.Trim()) { throw "khác: $($r[7])" }
  if ($r[7] -match 'mat\.dwg|ong@x|DuAn' -or $r[7] -notlike '*Lỗi gần đây*' -or $r[7] -notlike '*--- Chẩn đoán ---*Steve AI Connect v*') { throw $r[7] }
  if (Get-Setting 'ReportDraft' '') { throw 'còn nháp' } }
& $try 'BÁO LỖI bỏ tích thì không kèm' { Drive { Show-Report } @({ param($u) $u.say.Text = 'abc'; $u.kD.Checked = $false; if ($u.pv.Text -like '*--- Chẩn đoán*') { throw 'còn' } }) 'RepUi' }
& $try 'BÁO LỖI dài: rút gọn đúng 3000' { $t = Get-ReportText ('x' * 1200) @(1..200 | ForEach-Object { "dòng chẩn đoán $_" }) @('loi: a'); if ($t.Length -gt 3000 -or $t -notlike '*đã rút gọn)' -or $t -notlike '*loi: a*') { throw $t.Length } }
& $try 'HƯỚNG DẪN không có QR' { Drive { Show-Help } @({ param($u) if (@($u.d.Controls | Where-Object { $_ -is [Windows.Forms.PictureBox] }).Count) { throw 'có ảnh' } }) 'HelpUi' }
& $try 'HƯỚNG DẪN bấm mời cà phê mới mở QR' {
  $script:cof = 0; function script:Show-Coffee { $script:cof++ }
  Drive { Show-Help } @({ param($u) }) 'HelpUi'; if ($script:cof) { throw 'tự mở' }
  Drive { Show-Help } @({ param($u) $m = $u.cf.GetType().GetMethod('OnLinkClicked', [Reflection.BindingFlags]'Instance,NonPublic'); [void]$m.Invoke($u.cf, [object[]]@([Windows.Forms.LinkLabelLinkClickedEventArgs]::new($u.cf.Links[0]))) }) 'HelpUi'; if ($script:cof -ne 1) { throw 'không mở' } }
& $try 'HƯỚNG DẪN nút Báo lỗi mở hộp báo lỗi' { $script:rp = 0; $old = ${function:Show-Report}; function script:Show-Report { $script:rp++ }; try { Drive { Show-Help } @({ param($u) $u.report.PerformClick() }) 'HelpUi' } finally { Set-Item function:script:Show-Report $old }; if ($script:rp -ne 1) { throw 'x' } }
$script:RegisterUrl = $saved
& $try 'LỌC giữ phiên bản Windows, vẫn che SĐT' {
  if ((Protect-Text 'Windows 10.0.26200.0 64-bit=True') -ne 'Windows 10.0.26200.0 64-bit=True') { throw (Protect-Text 'Windows 10.0.26200.0 64-bit=True') }
  foreach ($q in 'goi 0987 779 228 nhe', 'sdt.0987779228', '+84 987 779 228', 'SDT:0987-779-228', '0987.779.228') { if ((Protect-Text $q) -notlike '*phone*') { throw $q } } }
function Plain([string]$args2, [int]$sec) {   # start this copy again; $true when it left by itself in time
  $p = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$me`" $args2" -PassThru -WindowStyle Hidden
  $e = [DateTime]::Now.AddSeconds($sec); while ([DateTime]::Now -lt $e -and -not $p.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
  if (-not $p.HasExited) { $p.Kill(); return $false }; return $true
}
$keepS = $env:STEVECAD_SELFTEST; $keepR = $env:STEVECAD_REGTEST
& $try 'MỘT CỬA SỔ mở lần hai thì dùng lại' {
  Show-Page 'tools'; $env:STEVECAD_SELFTEST = ''; $env:STEVECAD_REGTEST = ''
  try { $ok = Plain '' 14 } finally { $env:STEVECAD_SELFTEST = $keepS; $env:STEVECAD_REGTEST = $keepR }
  if (-not $ok) { throw 'mở cửa sổ thứ hai' }; if ($script:Page -ne 'home') { throw $script:Page } }
& $try 'MỘT CỬA SỔ chưa cài gì thì không báo cũ' { if (Test-Stale) { throw 'báo nhầm' } }
& $try 'BẢN CŨ không nhận yêu cầu, bản mới tự mở' {
  $g = Join-Path $script:Root 'app\gui.ps1'; [IO.File]::SetLastWriteTimeUtc($g, [DateTime]::UtcNow)
  $script:hits = @(); $o2 = "$keepS.child"; $env:STEVECAD_SELFTEST = $o2; $env:STEVECAD_REGTEST = ''; $env:STEVECAD_OPENTEST = ''
  $old = ${function:Show-Report}; function script:Show-Report { $script:hits += 'diag' }
  try { $ok = Plain '-Open diag' 120 } finally { $env:STEVECAD_SELFTEST = $keepS; $env:STEVECAD_REGTEST = $keepR; Set-Item function:script:Show-Report $old }
  if (-not $ok) { throw 'bản mới không thoát' }; if ($script:hits.Count) { throw 'bản cũ đã nhận' }
  if (-not (Test-Path $o2) -or -not @(Get-Content $o2 | Where-Object { $_ -like 'PASS*' }).Count) { throw 'bản mới không tự mở' } }
& $try 'BẢN CŨ hiện nhắc mở lại, không bị tin cập nhật đè' {
  if (-not (Test-Stale) -or -not $updLink.Visible -or $updLink.Text -notlike '*mở lại*') { throw $updLink.Text }
  Set-NewRelease @{ tag = 'v9.9.9'; notes = '' }; if ($updLink.Text -notlike '*mở lại*') { throw 'bị đè' } }
& $try 'MỞ LẠI nhả khoá trước khi chạy bản mới' {
  $script:sp = ''; function script:Start-Process { $x = $null; $script:sp = $(try { $x = [Threading.Mutex]::OpenExisting("Local\SteveAIConnectWindow-$($script:BuildStamp)"); $x.Dispose(); 'còn khoá' } catch { 'đã nhả' }) }
  $script:WindowMutex.Dispose(); $script:WindowMutex = New-Object Threading.Mutex $false, "Local\SteveAIConnectWindow-$($script:BuildStamp)"
  $script:cl = 0; $h = [Windows.Forms.FormClosingEventHandler] { param($s, $e) $script:cl++; $e.Cancel = $true }; $form.add_FormClosing($h)
  try { Restart-Self } finally { $form.remove_FormClosing($h); Remove-Item function:script:Start-Process }
  if ($script:sp -ne 'đã nhả' -or -not $script:cl) { throw "$($script:sp) $($script:cl)" } }
