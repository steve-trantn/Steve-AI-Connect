# The notice shown when a CAD starts (app\SteveAINotify.ps1). Run through run.ps1 (sandbox, STEVECAD_DRYRUN): no network,
# the release page is a file, the Setup is never started.
param([string]$root)
if (-not $env:STEVECAD_DRYRUN) { Write-Host 'Run it through run.ps1 (sandbox).'; exit 1 }
. (Join-Path $root 'app\core.ps1')
. (Join-Path $root 'app\update.ps1')
$script:LogSink = { param($m, $l) }
$bad = 0
function Check($n, [bool]$ok, $info = '') { if ($ok) { Write-Host "PASS  $n" } else { Write-Host "FAIL  $n $info"; $script:bad++ } }

# rules: GitHub at most every 30 minutes, "Để sau" for the rest of the day, switched off in the options
Set-Setting 'NoticeChecked' ''; Set-Setting 'UpdateNotice' $true
$t0 = [datetime]'2026-11-27T08:00:00'
Check 'thong bao: lan dau thi hoi GitHub' (Test-NoticeCheckDue $t0)
Check 'thong bao: chua du 30 phut thi khong hoi lai' (-not (Test-NoticeCheckDue $t0.AddMinutes(10)))
Check 'thong bao: sau 30 phut thi hoi lai' (Test-NoticeCheckDue $t0.AddMinutes(45))
Set-NoticeLater 'v9.9.9' $t0
Check 'thong bao: De sau thi het hom nay khong nhac' (-not (Test-NoticeDue 'v9.9.9' $t0.AddHours(5)))
Check 'thong bao: hom sau nhac lai' (Test-NoticeDue 'v9.9.9' $t0.AddDays(1))
Check 'thong bao: ban moi hon thi van nhac' (Test-NoticeDue 'v9.9.10' $t0.AddHours(1))
Set-Setting 'UpdateNotice' $false
Check 'thong bao: tat trong Tuy chon thi khong hoi' (-not (Test-NoticeCheckDue $t0.AddDays(2)))
Set-Setting 'UpdateNotice' $true; Set-Setting 'NoticeLater' ''

# the notice itself, against a saved release page
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('notice-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force $tmp | Out-Null
$rel = @{ tag_name = 'v9.9.9'; body = "## Steve AI Connect v9.9.9`n### Mới trong v9.9.9`n- **Điểm một:** chữ đậm`n- Điểm hai [link](https://x)`n- Điểm ba`n- Điểm bốn"
          assets = @(@{ name = 'Steve-AI-Connect-Setup-v9.9.9.exe'; browser_download_url = "$($script:RepoUrl)/releases/download/v9.9.9/Steve-AI-Connect-Setup-v9.9.9.exe"; digest = 'sha256:' + ('a' * 64) }) }
[IO.File]::WriteAllText("$tmp\rel.json", ($rel | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
$probe = "$tmp\probe.ps1"
[IO.File]::WriteAllText($probe, @'
$u = $script:NoticeUi
$out = @($u.form.Controls | ForEach-Object { $_.Text }) -join '|'
[Windows.Forms.Button].GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($u.no, @([EventArgs]::Empty))   # a click without showing the window
[IO.File]::WriteAllText($env:STEVECAD_NOTICEOUT, $out + '|later=' + (Get-Setting 'NoticeLater' ''), (New-Object Text.UTF8Encoding $false))
'@, (New-Object Text.UTF8Encoding $true))
$env:STEVECAD_NOTICEJSON = "$tmp\rel.json"; $env:STEVECAD_NOTICETEST = $probe; $env:STEVECAD_NOTICEOUT = "$tmp\out.txt"
$ps = { & powershell -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'app\SteveAINotify.ps1') -Cad zwcad }
& $ps
$o = if (Test-Path "$tmp\out.txt") { [IO.File]::ReadAllText("$tmp\out.txt") } else { '' }
Check 'thong bao: hien ban moi, ban dang dung, 3 diem moi (tieu de in dam)' ($o -match 'có bản mới v9\.9\.9' -and $o -match 'Bạn đang dùng v' -and $o -match '• Điểm một' -and $o -notmatch 'chữ đậm' -and $o -match '• Điểm hai link' -and $o -notmatch 'Điểm bốn') $o
Check 'thong bao: bam De sau thi ghi nho' ($o -match "later=v9\.9\.9\|$((Get-Date).ToString('yyyy-MM-dd'))") $o
Remove-Item "$tmp\out.txt" -ErrorAction SilentlyContinue
Set-Setting 'NoticeChecked' ''   # past the 30 minutes: only "Để sau" keeps it hidden
& $ps
Check 'thong bao: mo CAD lan nua trong ngay thi khong hien' (-not (Test-Path "$tmp\out.txt"))
Set-Setting 'NoticeChecked' ''; Set-Setting 'NoticeLater' ''
$rel.tag_name = 'v0.0.1'; [IO.File]::WriteAllText("$tmp\rel.json", ($rel | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
& $ps
Check 'thong bao: khong co ban moi thi khong hien' (-not (Test-Path "$tmp\out.txt"))
# "Cập nhật ngay": the download is replaced, the Setup is not started (DRYRUN); the notice must close by itself
Set-Setting 'NoticeChecked' ''; Set-Setting 'NoticeLater' ''
$rel.tag_name = 'v9.9.9'; [IO.File]::WriteAllText("$tmp\rel.json", ($rel | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText("$tmp\probe2.ps1", @'
function Save-Release($r) { return 'C:\x\Setup.exe' }
$u = $script:NoticeUi
$link = $u.more.Text
$ea = (New-Object Windows.Forms.LinkLabelLinkClickedEventArgs $u.more.Links[0]).psobject.BaseObject
[Windows.Forms.LinkLabel].GetMethod('OnLinkClicked', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($u.more, [object[]]@($ea))
[Windows.Forms.Button].GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($u.go, @([EventArgs]::Empty))
$out = "link=$link|opened=$($script:MoreOpened)|msg=$($u.msg.Text)|timer=$($u.timer.Enabled)|later=$(Get-Setting 'NoticeLater' '')"
[IO.File]::WriteAllText($env:STEVECAD_NOTICEOUT, $out, (New-Object Text.UTF8Encoding $false))
'@, (New-Object Text.UTF8Encoding $true))
$env:STEVECAD_NOTICETEST = "$tmp\probe2.ps1"
& $ps
$o = if (Test-Path "$tmp\out.txt") { [IO.File]::ReadAllText("$tmp\out.txt") } else { '' }
Check 'thong bao: co link Xem them mo trang cac ban phat hanh' ($o -match 'link=Xem thêm' -and $o -match 'opened=https://github\.com/steve-trantn/Steve-AI-Connect/releases\|') $o
Check 'thong bao: cap nhat xong thi tu dong khung, het hom khong nhac' ($o -match 'Đã mở bộ cài v9\.9\.9' -and $o -match 'tự đóng' -and $o -match 'timer=True' -and $o -match 'later=v9\.9\.9\|') $o
foreach ($n in 'NOTICEJSON', 'NOTICETEST', 'NOTICEOUT') { [Environment]::SetEnvironmentVariable("STEVECAD_$n", $null) }
Remove-Item $tmp -Recurse -Force
$l = [IO.File]::ReadAllText((Join-Path $root 'templates\SteveAI.lsp'))
Check 'thong bao: CAD goi kiem tra khi mo' ($l -match "steveai-update-notice" -and $l -match 'SteveAINotify\.ps1')
exit $(if ($bad) { 1 } else { 0 })
