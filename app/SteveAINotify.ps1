# Steve AI Connect - started hidden by SteveAI.lsp when a CAD (ZWCAD, ADSCivil, AutoCAD, Civil 3D) opens: asks GitHub
# whether there is a newer release and, when there is, shows a small notice in the bottom right corner of the screen
# with "Cập nhật ngay" (download, check SHA-256, run the Setup) and "Để sau" (not again today). No network: nothing shown.
param([string]$Cad = '', [switch]$Show)   # -Show: tests / support, skip the 30-minute limit
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'update.ps1')
$script:LogSink = { param($m, $lvl) }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# one notice at a time, however many CADs and drawings start together
$mutex = New-Object Threading.Mutex($false, 'Local\SteveAIUpdateNotice')
if (-not $mutex.WaitOne(0)) { exit 0 }
try {
  if (-not $Show -and -not (Test-NoticeCheckDue)) { exit 0 }
  # tests: a release page saved on disk instead of GitHub (only together with STEVECAD_DRYRUN)
  if ($env:STEVECAD_DRYRUN -and $env:STEVECAD_NOTICEJSON) { $rel = Read-Release ([IO.File]::ReadAllText($env:STEVECAD_NOTICEJSON)) }
  else { try { $rel = Get-NewRelease } catch { exit 0 } }
  if (-not $rel -or -not (Test-NoticeDue $rel.tag)) { exit 0 }

  # a window that does not take the keyboard away from the CAD
  if (-not ('SteveAI.NoticeForm' -as [type])) {
    Add-Type -WarningAction SilentlyContinue -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
namespace SteveAI {
  public class NoticeForm : System.Windows.Forms.Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override System.Windows.Forms.CreateParams CreateParams {
      get { var p = base.CreateParams; p.ExStyle |= 0x00000008; return p; }   // WS_EX_TOPMOST
    }
  }
}
'@
  }
  $bg = [Drawing.Color]::FromArgb(24, 36, 58); $fg = [Drawing.Color]::FromArgb(230, 237, 246); $mut = [Drawing.Color]::FromArgb(148, 163, 184)
  $f = New-Object SteveAI.NoticeForm
  $f.FormBorderStyle = 'None'; $f.ShowInTaskbar = $false; $f.BackColor = $bg; $f.Size = New-Object Drawing.Size 380, 196
  $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $f.StartPosition = 'Manual'; $f.Location = New-Object Drawing.Point ($wa.Right - $f.Width - 16), ($wa.Bottom - $f.Height - 16)
  $f.add_Paint({ param($s, $e) $e.Graphics.DrawRectangle((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(0, 104, 236)), 2), 1, 1, $s.Width - 3, $s.Height - 3) })
  function Add-Text($text, $x, $y, $w, $h, $size, $color, $bold) {
    $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.ForeColor = $color; $l.BackColor = $bg; $l.AutoEllipsis = $true
    $l.Font = New-Object Drawing.Font 'Segoe UI', $size, $(if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular })
    $l.SetBounds($x, $y, $w, $h); $f.Controls.Add($l); return $l
  }
  [void](Add-Text "Steve AI Connect có bản mới $($rel.tag)" 16 12 348 24 11 $fg $true)
  [void](Add-Text "Bạn đang dùng $($script:Version). Cấu hình và đăng ký được giữ nguyên." 16 38 348 20 9 $mut $false)
  # the first points of the release notes, each by its bold title when it has one ("**Kiểm tra KCS ...:** ...")
  $news = $rel.notes   # only the "Mới trong ..." section when the notes have one, not the general part below it
  if ($news -match '(?s)###\s*Mới trong[^\n]*\n(.*?)(\r?\n\s*\r?\n\*\*|\r?\n###|$)') { $news = $Matches[1] }
  $pts = @((($news -split '\r?\n') | Where-Object { $_ -match '^\s*-\s' } | Select-Object -First 3) | ForEach-Object {
    $x = $_ -replace '^\s*-\s*', ''
    if ($x -match '^\*\*(.+?):?\*\*') { $x = $Matches[1].TrimEnd(':') }
    '• ' + (($x -replace '[*`#>]', '') -replace '\[([^\]]+)\]\([^)]+\)', '$1').Trim() })
  $msg = Add-Text ($pts -join "`n") 16 62 348 56 9 $fg $false
  # everything else (and the versions in between, when several were skipped) is one click away, not in the notice
  $more = New-Object Windows.Forms.LinkLabel; $more.Text = 'Xem thêm các thay đổi…'; $more.BackColor = $bg
  $more.LinkColor = [Drawing.Color]::FromArgb(96, 165, 250); $more.ActiveLinkColor = $more.LinkColor; $more.Font = New-Object Drawing.Font 'Segoe UI', 9
  $more.SetBounds(16, 120, 200, 20); $f.Controls.Add($more)
  $script:MoreUrl = "$($script:RepoUrl)/releases"
  $more.add_LinkClicked({ if ($env:STEVECAD_DRYRUN) { $script:MoreOpened = $script:MoreUrl } else { Start-Process $script:MoreUrl } })
  $go = New-Object Windows.Forms.Button; $go.Text = 'Cập nhật ngay'; $go.SetBounds(150, 148, 120, 34)
  $go.FlatStyle = 'Flat'; $go.BackColor = [Drawing.Color]::FromArgb(0, 104, 236); $go.ForeColor = [Drawing.Color]::White; $go.FlatAppearance.BorderSize = 0
  $go.Font = New-Object Drawing.Font 'Segoe UI', 9.5, ([Drawing.FontStyle]::Bold)
  $no = New-Object Windows.Forms.Button; $no.Text = 'Để sau'; $no.SetBounds(278, 148, 86, 34)
  $no.FlatStyle = 'Flat'; $no.BackColor = $bg; $no.ForeColor = $fg; $no.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(43, 60, 90)
  $no.Font = New-Object Drawing.Font 'Segoe UI', 9.5
  $f.Controls.AddRange(@($go, $no))
  $state = @{ busy = $false }
  $no.add_Click({ if ($state.busy) { return }; Set-NoticeLater $rel.tag; $f.Close() })
  # once the Setup is started the notice closes by itself (and is not shown again today for this version)
  $script:CloseTimer = New-Object Windows.Forms.Timer; $script:CloseTimer.Interval = 5000
  $script:CloseTimer.add_Tick({ $script:CloseTimer.Stop(); $f.Close() })
  $go.add_Click({
    if ($state.busy) { return }
    $state.busy = $true; $go.Enabled = $false; $no.Enabled = $false; $more.Visible = $false
    $msg.ForeColor = $fg; $msg.Text = 'Đang tải bản mới…'; $f.Refresh()
    try {
      $script:IsGui = $true   # Wait-Task keeps this notice responsive while downloading
      $file = Save-Release $rel
      Start-Release $file
      Set-NoticeLater $rel.tag
      $msg.Text = "Đã mở bộ cài $($rel.tag). Cài xong: lưu bản vẽ, đóng hẳn CAD rồi mở lại để dùng bản mới. Khung này tự đóng."
      $script:CloseTimer.Start()
    } catch {
      $msg.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113); $msg.Text = $_.Exception.Message
      $go.Enabled = $true; $no.Enabled = $true; $state.busy = $false
    }
  })
  $script:NoticeUi = @{ form = $f; go = $go; no = $no; msg = $msg; more = $more; timer = $script:CloseTimer }   # tests
  if ($env:STEVECAD_NOTICETEST) { . $env:STEVECAD_NOTICETEST; exit 0 }
  [Windows.Forms.Application]::Run($f)
} finally {
  $mutex.ReleaseMutex(); $mutex.Dispose()
}
