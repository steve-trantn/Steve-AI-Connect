# Steve AI Connect - giao diện (WinForms). Dot-sourced by SteveCADConnect.ps1 after core.ps1.
# Three pages:
#   Bắt đầu        - daily use: start a CAD (pick the version when several are installed), open Steve AI
#   Kết nối        - one-time setup: which CAD talks to which assistant, log
#   Công cụ & Skill - searchable list of the MCP tools and skills
. (Join-Path $PSScriptRoot 'catalog.ps1')
. (Join-Path $PSScriptRoot 'update.ps1')

# crisp text on high-DPI screens (we scale every coordinate ourselves), dark title bar, dark scrollbars
Add-Type -Namespace SteveCad -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, string l);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string idList);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint PrivateExtractIcons(string f, int i, int cx, int cy, IntPtr[] h, int[] id, uint n, uint flags);
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
'@
try { [void][SteveCad.Win]::SetProcessDPIAware() } catch {}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:IsGui = $true

$gr0 = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:K = $gr0.DpiX / 96.0; $gr0.Dispose()
function S([double]$v) { [int][Math]::Round($v * $script:K) }
function Put($c, $x, $y, $w, $h) { $c.SetBounds((S $x), (S $y), (S $w), (S $h)); return $c }

# ---------- theme ----------
# Setting 'Theme': 'dark' | 'light'. Dark by default; the ☀ / ☾ button on the tab bar switches and remembers it.
function Get-ThemeName {
  $t = [string](Get-Setting 'Theme' '')
  if ($env:STEVECAD_THEME) { $t = $env:STEVECAD_THEME }   # screenshots
  if ($t -in 'dark', 'light') { return $t }
  return 'dark'
}
$script:Theme = Get-ThemeName
$script:Dark = $script:Theme -eq 'dark'
function Rgb($r, $g, $b) { [Drawing.Color]::FromArgb($r, $g, $b) }
if ($script:Dark) {
  $Pal = @{
    header = (Rgb 17 24 39); headSub = (Rgb 255 196 0); headMuted = (Rgb 148 163 184); onAccent = [Drawing.Color]::White
    accent = (Rgb 96 165 250); accentBtn = (Rgb 37 99 235); accentHover = (Rgb 59 130 246); accentSoft = (Rgb 30 41 59)
    page = (Rgb 24 25 28); surface = (Rgb 36 38 42); input = (Rgb 46 48 53); line = (Rgb 60 63 69); hover = (Rgb 44 46 51)
    text = (Rgb 236 238 241); muted = (Rgb 170 175 183); faint = (Rgb 115 120 128)
    green = (Rgb 74 222 128); greenSoft = (Rgb 22 48 34)
    gold = (Rgb 255 196 0); goldHover = (Rgb 255 210 60); goldSoft = (Rgb 45 40 25); goldLine = (Rgb 120 96 30)
    red = (Rgb 248 113 113); warn = (Rgb 251 191 36); disabled = (Rgb 31 32 36); disabledLine = (Rgb 48 50 55)
  }
} else {
  $Pal = @{
    header = (Rgb 15 23 42); headSub = (Rgb 255 196 0); headMuted = (Rgb 148 163 184); onAccent = [Drawing.Color]::White
    accent = (Rgb 29 78 216); accentBtn = (Rgb 29 78 216); accentHover = (Rgb 30 64 175); accentSoft = (Rgb 239 245 255)
    page = (Rgb 244 246 249); surface = [Drawing.Color]::White; input = [Drawing.Color]::White; line = (Rgb 222 226 232); hover = (Rgb 248 250 252)
    text = (Rgb 17 24 39); muted = (Rgb 90 98 110); faint = (Rgb 150 157 167)
    green = (Rgb 22 140 70); greenSoft = (Rgb 232 246 237)
    gold = (Rgb 255 196 0); goldHover = (Rgb 255 210 60); goldSoft = (Rgb 255 250 235); goldLine = (Rgb 240 208 120)
    red = (Rgb 200 40 40); warn = (Rgb 190 105 0); disabled = (Rgb 246 247 249); disabledLine = (Rgb 232 234 238)
  }
}
$Fnt = @{
  n = (New-Object Drawing.Font 'Segoe UI', 9.5); b = (New-Object Drawing.Font 'Segoe UI Semibold', 10)
  s = (New-Object Drawing.Font 'Segoe UI', 8.75); cap = (New-Object Drawing.Font 'Segoe UI Semibold', 8.25)
  h1 = (New-Object Drawing.Font 'Segoe UI Semibold', 14); h2 = (New-Object Drawing.Font 'Segoe UI Semibold', 11.5)
  tab = (New-Object Drawing.Font 'Segoe UI Semibold', 10); btn = (New-Object Drawing.Font 'Segoe UI Semibold', 10)
  big = (New-Object Drawing.Font 'Segoe UI Semibold', 12)
}
$Url = @{ claude = 'https://claude.ai/download'; claudecode = 'https://claude.com/claude-code'
          codex = 'ms-windows-store://search/?query=Codex'; gemini = 'https://aistudio.google.com/apikey' }
# badge colours (initials on a rounded square), same as the ribbon icons in CAD
$Badge = @{
  zwcad = @('ZW', (Rgb 0 120 200), [Drawing.Color]::White); autocad = @('A', (Rgb 196 40 48), [Drawing.Color]::White)
  adscivil = @('ADS', (Rgb 255 196 0), (Rgb 17 24 39))
  claude = @('C', (Rgb 204 120 92), [Drawing.Color]::White); claudecode = @('CC', (Rgb 204 120 92), [Drawing.Color]::White)
  codex = @('GPT', (Rgb 16 163 127), [Drawing.Color]::White); gemini = @('G', (Rgb 66 133 244), [Drawing.Color]::White)
}

function Set-DarkScroll($ctl) { if ($script:Dark) { try { [void][SteveCad.Win]::SetWindowTheme($ctl.Handle, 'DarkMode_Explorer', $null) } catch {} } }
function New-Label($text, $font, $color) {
  $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Font = $font; $l.ForeColor = $color
  $l.BackColor = [Drawing.Color]::Transparent; $l.AutoSize = $false; $l.UseMnemonic = $false; return $l
}
function New-Link($text, $font, $color) {
  $l = New-Object Windows.Forms.LinkLabel; $l.Text = $text; $l.Font = $font; $l.UseMnemonic = $false
  $l.LinkColor = $color; $l.ActiveLinkColor = $color; $l.VisitedLinkColor = $color
  $l.LinkBehavior = 'HoverUnderline'; $l.BackColor = [Drawing.Color]::Transparent; return $l
}
# kind: primary | gold | ghost (outlined) | seg (segmented toggle)
function Set-ButtonLook($b, [string]$kind, [bool]$on = $false) {
  # the kind is kept in AccessibleDescription, NOT in Tag: Tag belongs to the button's owner (the CAD launch
  # buttons keep their card there, and a click with a lost Tag failed with "array index evaluated to null")
  $b.AccessibleDescription = $kind
  if (-not $b.Enabled) {
    $b.BackColor = $Pal.disabled; $b.ForeColor = $Pal.faint; $b.FlatAppearance.BorderColor = $Pal.disabledLine; return
  }
  switch ($kind) {
    'primary' { $b.BackColor = $Pal.accentBtn; $b.ForeColor = $Pal.onAccent; $b.FlatAppearance.BorderColor = $Pal.accentBtn; $b.FlatAppearance.MouseOverBackColor = $Pal.accentHover }
    'gold'    { $b.BackColor = $Pal.gold; $b.ForeColor = (Rgb 17 24 39); $b.FlatAppearance.BorderColor = $Pal.gold; $b.FlatAppearance.MouseOverBackColor = $Pal.goldHover }
    'seg'     {
      if ($on) { $b.BackColor = $Pal.accentBtn; $b.ForeColor = $Pal.onAccent; $b.FlatAppearance.BorderColor = $Pal.accentBtn; $b.FlatAppearance.MouseOverBackColor = $Pal.accentHover }
      else { $b.BackColor = $Pal.surface; $b.ForeColor = $Pal.text; $b.FlatAppearance.BorderColor = $Pal.line; $b.FlatAppearance.MouseOverBackColor = $Pal.accentSoft }
    }
    default   { $b.BackColor = $Pal.surface; $b.ForeColor = $Pal.accent; $b.FlatAppearance.BorderColor = $Pal.line; $b.FlatAppearance.MouseOverBackColor = $Pal.accentSoft }
  }
}
function New-Button($text, [string]$kind = 'ghost') {
  $b = New-Object Windows.Forms.Button
  $b.Text = $text; $b.Font = $Fnt.btn; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.UseMnemonic = $false
  $b.FlatAppearance.BorderSize = 1
  # disabled flat buttons get grey text from Windows; re-apply our colours when the state changes
  $b.add_EnabledChanged({ Set-ButtonLook $this ([string]$this.AccessibleDescription) ($this.BackColor -eq $Pal.accentBtn) })
  Set-ButtonLook $b $kind
  return $b
}
function New-Combo {
  $c = New-Object Windows.Forms.ComboBox; $c.DropDownStyle = 'DropDownList'; $c.FlatStyle = 'Flat'
  $c.BackColor = $Pal.input; $c.ForeColor = $Pal.text; $c.Font = $Fnt.n
  $c.DrawMode = 'OwnerDrawFixed'; $c.ItemHeight = (S 22)
  $c.add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    $sel = ($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0
    $edit = ($e.State -band [Windows.Forms.DrawItemState]::ComboBoxEdit) -ne 0
    $bg = if ($sel -and -not $edit) { $Pal.accentBtn } else { $Pal.input }
    $e.Graphics.FillRectangle((New-Object Drawing.SolidBrush $bg), $e.Bounds)
    $r = New-Object Drawing.Rectangle ($e.Bounds.X + (S 6)), $e.Bounds.Y, ($e.Bounds.Width - (S 6)), $e.Bounds.Height
    $fg = if ($sel -and -not $edit) { $Pal.onAccent } else { $Pal.text }
    [Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$s.Items[$e.Index], $s.Font, $r, $fg, [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
  })
  return $c
}
# a card: outer panel = 1px border, inner panel = fill
function New-Card($parent, $x, $y, $w, $h, $fill = $null, $border = $null) {
  $o = Put (New-Object Windows.Forms.Panel) $x $y $w $h; $o.BackColor = $(if ($border) { $border } else { $Pal.line })
  $i = New-Object Windows.Forms.Panel; $i.SetBounds(1, 1, $o.Width - 2, $o.Height - 2); $i.BackColor = $(if ($fill) { $fill } else { $Pal.surface })
  $o.Controls.Add($i); $parent.Controls.Add($o)
  return @{ outer = $o; inner = $i }
}
function New-BadgeBox($key, $size) {
  $b = $Badge[$key]
  $pb = New-Object Windows.Forms.PictureBox; $pb.BackColor = [Drawing.Color]::Transparent; $pb.SizeMode = 'Zoom'
  $ms = New-Object IO.MemoryStream (, (New-MenuIcon $b[0] $b[1] $b[2] (S $size)))
  $pb.Image = [Drawing.Image]::FromStream($ms)
  return $pb
}
function Add-Caption($parent, $text, $x, $y, $w = 400) {
  $l = Put (New-Label $text.ToUpper() $Fnt.cap $Pal.muted) $x $y $w 18; $parent.Controls.Add($l); return $l
}

# ---------- form ----------
$W = 760; $HPage = 492
$form = New-Object Windows.Forms.Form
$form.Text = "$($script:AppName) $($script:Version)"
$form.AutoScaleMode = 'None'
$form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.ClientSize = New-Object Drawing.Size (S $W), (S (44 + $HPage + 32))
$form.Font = $Fnt.n; $form.BackColor = $Pal.page; $form.ForeColor = $Pal.text
try { $form.Icon = New-AppIcon } catch {}
$tip = New-Object Windows.Forms.ToolTip; $tip.AutoPopDelay = 15000; $tip.InitialDelay = 400
$script:Conn = @{}; $script:AiChoices = @(); $script:AiPick = ''

# No header band inside the window: the Windows title bar already shows the icon, the name and the version.
# On Windows 11 the title bar takes the app's dark navy (DWM caption colour), so it reads as the app's header.
$form.add_HandleCreated({
  try { $cap = [int]($Pal.header.R) -bor ([int]($Pal.header.G) -shl 8) -bor ([int]($Pal.header.B) -shl 16); [void][SteveCad.Win]::DwmSetWindowAttribute($form.Handle, 35, [ref]$cap, 4) } catch {}
  try { $txt = 0x00FFFFFF; [void][SteveCad.Win]::DwmSetWindowAttribute($form.Handle, 36, [ref]$txt, 4) } catch {}
})

# tab bar
$nav = Put (New-Object Windows.Forms.Panel) 0 0 $W 44; $nav.BackColor = $Pal.surface
$navLine = Put (New-Object Windows.Forms.Panel) 0 43 $W 1; $navLine.BackColor = $Pal.line
$ink = New-Object Windows.Forms.Panel; $ink.BackColor = $Pal.accent
$nav.Controls.AddRange(@($navLine, $ink)); $form.Controls.Add($nav)
$script:Tabs = @{}
function New-Tab($key, $text, $x, $w) {
  $t = Put (New-Label $text $Fnt.tab $Pal.muted) $x 0 $w 42; $t.TextAlign = 'MiddleCenter'; $t.Cursor = 'Hand'; $t.Tag = $key
  $t.add_Click({ Show-Page $this.Tag })
  $nav.Controls.Add($t); $script:Tabs[$key] = $t; return $t
}
$tabHome  = New-Tab 'home' 'Bắt đầu' 14 104
# the advanced connect page has no tab: it opens from ⚙ Tùy chọn nâng cao (footer), people new to this never need it
$tabTools = New-Tab 'tools' 'Công cụ & Skill' 122 160
# right side of the tab bar: what it connects, and the light / dark switch
$tagline = Put (New-Label 'ZWCAD · AutoCAD · ADSCivil  ⇄  Claude · ChatGPT · Gemini' $Fnt.s $Pal.faint) ($W - 412) 13 350 18; $tagline.TextAlign = 'TopRight'
$themeBtn = Put (New-Object Windows.Forms.Button) ($W - 50) 6 34 32
$themeBtn.FlatStyle = 'Flat'; $themeBtn.FlatAppearance.BorderSize = 0; $themeBtn.Cursor = 'Hand'; $themeBtn.TabStop = $false
$themeBtn.BackColor = $Pal.surface; $themeBtn.FlatAppearance.MouseOverBackColor = $Pal.accentSoft; $themeBtn.ForeColor = $Pal.muted
$themeBtn.Font = New-Object Drawing.Font 'Segoe UI Symbol', 11; $themeBtn.Text = $(if ($script:Dark) { '☀' } else { '☾' })
$tip.SetToolTip($themeBtn, $(if ($script:Dark) { 'Chuyển sang giao diện sáng' } else { 'Chuyển sang giao diện tối' }))
$nav.Controls.AddRange(@($tagline, $themeBtn))
# replaces the tagline when a newer release exists (update.ps1)
$updLink = Put (New-Link '' $Fnt.s $Pal.gold) ($W - 412) 13 350 18; $updLink.TextAlign = 'TopRight'; $updLink.Visible = $false
$updLink.add_LinkClicked({ if ($script:NewRelease -and -not $script:Busy) { Show-Update $script:NewRelease } })
$nav.Controls.Add($updLink)
$themeBtn.add_Click({
  Set-Setting 'Theme' $(if ($script:Dark) { 'light' } else { 'dark' })
  Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$(Join-Path $PSScriptRoot 'SteveCADConnect.ps1')`"" -WindowStyle Hidden
  $form.Close()
})

$pages = @{}
foreach ($pk in 'home', 'conn', 'tools') {   # not $k: PowerShell names ignore case, $k would overwrite the DPI scale $K
  $p = Put (New-Object Windows.Forms.Panel) 0 44 $W $HPage; $p.BackColor = $Pal.page; $p.Visible = $false
  $form.Controls.Add($p); $pages[$pk] = $p
}
$pgHome = $pages.home; $pgConn = $pages.conn; $pgTools = $pages.tools
function Show-Page($which) {
  foreach ($pk in $pages.Keys) { $pages[$pk].Visible = ($pk -eq $which) }
  $act = $script:Tabs[$which]   # none for the advanced page
  foreach ($t in $script:Tabs.Values) { $t.ForeColor = $(if ($t -eq $act) { $Pal.accent } else { $Pal.muted }) }
  $ink.Visible = [bool]$act
  if ($act) { $ink.SetBounds($act.Left + (S 14), (S 40), $act.Width - (S 28), (S 3)); $ink.BringToFront() }
  $script:Page = $which
}

# footer
$foot = Put (New-Object Windows.Forms.Panel) 0 (44 + $HPage) $W 32; $foot.BackColor = $Pal.surface
$footLine = Put (New-Object Windows.Forms.Panel) 0 0 $W 1; $footLine.BackColor = $Pal.line
$fl1 = Put (New-Link 'Thư mục làm việc AI' $Fnt.s $Pal.accent) 16 8 124 18
$fl1.add_LinkClicked({ New-Item -ItemType Directory -Force $script:Workspace | Out-Null; Start-Process explorer.exe $script:Workspace })
$fl2 = Put (New-Link '✎  Đề xuất tính năng' $Fnt.s $Pal.accent) 142 8 124 18
$fl2.add_LinkClicked({ Show-Feature })
$adv = Put (New-Link '⚙  Tùy chọn nâng cao' $Fnt.s $Pal.accent) 268 8 134 18
$fl3 = Put (New-Label "Hỗ trợ: $($script:Contact)" $Fnt.s $Pal.muted) ($W - 226) 8 210 18; $fl3.TextAlign = 'TopRight'
# a small, quiet "buy me a coffee" in the footer; the QR only shows when someone clicks it
$coffee = Put (New-Link '☕  Mời Steve ly cà phê' $Fnt.s $Pal.muted) 404 8 130 18
$coffee.add_LinkClicked({ Show-Coffee })
$foot.Controls.AddRange(@($footLine, $fl1, $fl2, $adv, $coffee, $fl3)); $form.Controls.Add($foot)

function New-SmallDialog([string]$title, [int]$w, [int]$h) {
  $d = New-Object Windows.Forms.Form; $d.Text = $title; $d.AutoScaleMode = 'None'
  $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.StartPosition = 'CenterParent'; $d.ShowInTaskbar = $false
  $d.ClientSize = New-Object Drawing.Size (S $w), (S $h); $d.BackColor = $Pal.page; $d.ForeColor = $Pal.text; $d.Font = $Fnt.n
  try { $d.Icon = $form.Icon } catch {}
  if ($script:Dark) { $d.add_HandleCreated({ try { $v = 1; [void][SteveCad.Win]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) } catch {} }) }
  return $d
}
function Show-Coffee {
  $d = New-SmallDialog 'Mời Steve ly cà phê' 380 590
  $t1 = Put (New-Label 'Steve AI Connect miễn phí cho mọi người.' $Fnt.b $Pal.text) 20 16 340 22
  $t2 = Put (New-Label 'Nếu công cụ giúp ích cho công việc của bạn, có thể mời Steve một ly cà phê để có thêm động lực làm tiếp. Cảm ơn bạn!' $Fnt.n $Pal.muted) 20 40 340 56
  $qrFile = Join-Path $PSScriptRoot 'donate-qr.png'
  $pb = Put (New-Object Windows.Forms.PictureBox) 80 102 220 220; $pb.SizeMode = 'Zoom'; $pb.BackColor = [Drawing.Color]::White
  if (Test-Path $qrFile) { $pb.Image = [Drawing.Image]::FromFile($qrFile) }
  $t3 = Put (New-Label 'Quét bằng MoMo hoặc app ngân hàng bất kỳ' $Fnt.s $Pal.muted) 20 328 340 18; $t3.TextAlign = 'TopCenter'
  $ln = Put (New-Object Windows.Forms.Panel) 20 356 340 1; $ln.BackColor = $Pal.line
  $t4 = Put (New-Label 'Hoặc bạn có thể mua phần mềm ủng hộ mình, mình có bán những món này nhé hihi ^_^' $Fnt.n $Pal.text) 20 366 340 40
  $t5 = Put (New-Label (($script:Products | ForEach-Object { "•  $_" }) -join "`r`n") $Fnt.n $Pal.muted) 32 408 190 130
  $t6 = Put (New-Label "Liên hệ:`r`n$($script:Author)`r`n$($script:Phone)" $Fnt.b $Pal.accent) 232 408 130 66
  $ok = Put (New-Button 'Đóng') 140 544 100 34; $ok.DialogResult = 'OK'
  $d.Controls.AddRange(@($t1, $t2, $pb, $t3, $ln, $t4, $t5, $t6, $ok)); $d.AcceptButton = $ok; $d.CancelButton = $ok
  [void]$d.ShowDialog($form)
  if ($pb.Image) { $pb.Image.Dispose() }
}
# credit text people paste when they reuse or share the tool (Apache 2.0 asks them to keep the NOTICE)
function Get-CreditText { "Dựa trên Steve AI Connect $($script:Version) của Steve Tran - $($script:RepoUrl) (giấy phép Apache 2.0)." }
function Show-About {
  $d = New-SmallDialog 'Giới thiệu & ghi nguồn' 480 318
  $logo2 = Put (New-Object Windows.Forms.PictureBox) 20 18 44 44; $logo2.SizeMode = 'Zoom'; try { $logo2.Image = (New-AppIcon).ToBitmap() } catch {}
  $a1 = Put (New-Label "$($script:AppName) $($script:Version)" $Fnt.h2 $Pal.text) 76 16 380 24
  $a2 = Put (New-Label "Tác giả: Steve Tran  ·  $($script:Phone)" $Fnt.n $Pal.muted) 76 42 380 20
  $acc = Get-Setting 'Account'
  $a5 = Put (New-Label $(if ($acc -and $acc.email) { "Đã đăng ký: $($acc.email)" } else { '' }) $Fnt.s $Pal.muted) 20 280 330 18
  $a3 = Put (New-Link $script:RepoUrl $Fnt.n $Pal.accent) 76 64 380 20; $a3.add_LinkClicked({ Start-Process $script:RepoUrl })
  $a4 = Put (New-Label 'Miễn phí, mã nguồn mở theo giấy phép Apache 2.0. Bạn được dùng, sửa và chia sẻ lại, với điều kiện ghi nguồn tác giả. Khi chia sẻ hoặc dùng lại, vui lòng dán dòng sau:' $Fnt.n $Pal.text) 20 98 440 60
  $tb = Put (New-Object Windows.Forms.TextBox) 20 162 440 50; $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.Text = Get-CreditText
  $tb.BackColor = $Pal.input; $tb.ForeColor = $Pal.text; $tb.BorderStyle = 'FixedSingle'
  $cp = Put (New-Button '⧉  Chép thông tin ghi nguồn' 'primary') 20 226 220 36
  $msg = Put (New-Label '' $Fnt.s $Pal.green) 250 236 210 20
  $cp.add_Click({ [Windows.Forms.Clipboard]::SetText((Get-CreditText)); $msg.Text = '✓ Đã chép, dán (Ctrl+V) vào bài viết.' })
  $ok = Put (New-Button 'Đóng') 360 272 100 34; $ok.DialogResult = 'OK'
  $d.Controls.AddRange(@($logo2, $a1, $a2, $a3, $a4, $a5, $tb, $cp, $msg, $ok)); $d.AcceptButton = $ok; $d.CancelButton = $ok
  [void]$d.ShowDialog($form)
}

# advanced options: footer menu, away from the main flow; "Gỡ cài đặt" is the last item
$menu = New-Object Windows.Forms.ContextMenuStrip; $menu.Font = $Fnt.n; $menu.ShowCheckMargin = $true
$menu.BackColor = $Pal.surface; $menu.ForeColor = $Pal.text
$mi26 = New-Object Windows.Forms.ToolStripMenuItem 'ADSCivil 2026: tự nạp trợ lý ADSAI khi khởi động'; $mi26.CheckOnClick = $true
$miScript = New-Object Windows.Forms.ToolStripMenuItem 'Cho AI chạy script Python trong ZWCAD/AutoCAD (nâng cao)'; $miScript.CheckOnClick = $true
$bUninstall = New-Object Windows.Forms.ToolStripMenuItem 'Gỡ cài đặt Steve AI Connect…'
$miConn = New-Object Windows.Forms.ToolStripMenuItem 'Kết nối từng mục, kiểm tra, ngắt kết nối, nhật ký…'
$miConn.ForeColor = $Pal.text; [void]$menu.Items.Add($miConn); [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$miConn.add_Click({ $menu.Close(); Show-Page 'conn' })
foreach ($m in $mi26, $miScript) { $m.ForeColor = $Pal.text; [void]$menu.Items.Add($m) }
$miTrust = New-Object Windows.Forms.ToolStripMenuItem 'AutoCAD / Civil 3D: thêm Steve AI vào Trusted Locations'; $miTrust.CheckOnClick = $true; $miTrust.ForeColor = $Pal.text
$miTrust.Checked = [bool](Get-Setting 'TrustAcad' $false); [void]$menu.Items.Add($miTrust)
$miTrust.add_Click({ Set-Trust ([bool]$miTrust.Checked) })
function Set-Trust([bool]$on) {
  Set-Setting 'TrustAcad' $on; $miTrust.Checked = $on
  $done = Set-AcadTrust $on
  if (-not $done) { [void][Windows.Forms.MessageBox]::Show($form, 'AutoCAD / Civil 3D đang mở. Đóng hết rồi mở lại Steve AI Connect để áp dụng.', $script:AppName, 'OK', 'Information') }
}
$miTerm = New-Object Windows.Forms.ToolStripMenuItem 'Mở Steve AI bằng cửa sổ terminal (kiểu cũ)'; $miTerm.CheckOnClick = $true; $miTerm.ForeColor = $Pal.text
$miTerm.Checked = [bool](Get-Setting 'UseTerminal' $false); [void]$menu.Items.Add($miTerm)
$miTerm.add_Click({ Set-Setting 'UseTerminal' ([bool]$miTerm.Checked) })
[void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$miShare = New-Object Windows.Forms.ToolStripMenuItem 'Chia sẻ skill của tôi…'; $miShare.ForeColor = $Pal.text; [void]$menu.Items.Add($miShare)
$miShare.add_Click({ $menu.Close(); Show-ShareSkill })
$miUpd = New-Object Windows.Forms.ToolStripMenuItem 'Kiểm tra bản cập nhật…'; $miUpd.ForeColor = $Pal.text; [void]$menu.Items.Add($miUpd)
$miUpd.add_Click({ $menu.Close(); if (-not $script:Busy) { Invoke-UpdateCheckNow } })
$miAuto = New-Object Windows.Forms.ToolStripMenuItem 'Tự động cập nhật khi có bản mới'; $miAuto.CheckOnClick = $true; $miAuto.ForeColor = $Pal.text
$miAuto.Checked = [bool](Get-Setting 'AutoUpdate' $false); [void]$menu.Items.Add($miAuto)
$miAuto.add_Click({ Set-Setting 'AutoUpdate' ([bool]$miAuto.Checked) })
$miAbout = New-Object Windows.Forms.ToolStripMenuItem 'Giới thiệu & ghi nguồn…'; $miAbout.ForeColor = $Pal.text; [void]$menu.Items.Add($miAbout)
$miErr = New-Object Windows.Forms.ToolStripMenuItem 'Tự gửi báo lỗi ẩn danh cho Steve'; $miErr.CheckOnClick = $true; $miErr.ForeColor = $Pal.text
$miErr.Checked = ((Get-Setting 'SendErrors' $false) -eq $true); [void]$menu.Items.Add($miErr)
$miErr.add_Click({ Set-Setting 'SendErrors' ([bool]$miErr.Checked) })
# errors inside event handlers (PowerShell swallows them): keep them for the report
[Windows.Forms.Application]::add_ThreadException({ param($s, $e) Add-ErrorLog 'window' $e.Exception.Message ([string]$e.Exception.StackTrace) })
$miDiag = New-Object Windows.Forms.ToolStripMenuItem 'Chép thông tin chẩn đoán (gửi hỗ trợ)'; $miDiag.ForeColor = $Pal.text; [void]$menu.Items.Add($miDiag)
$miDiag.add_Click({
  $menu.Close(); $form.Cursor = 'WaitCursor'
  try { [Windows.Forms.Clipboard]::SetText((Get-Diagnostics)); $t = 'Đã chép. Dán (Ctrl+V) vào Zalo hoặc email để gửi hỗ trợ. Không có thông tin cá nhân hay tên bản vẽ.' } catch { $t = $_.Exception.Message } finally { $form.Cursor = 'Default' }
  [void][Windows.Forms.MessageBox]::Show($form, $t, $script:AppName, 'OK', 'Information')
})
$miAbout.add_Click({ $menu.Close(); Show-About })
$bUninstall.ForeColor = $Pal.red; [void]$menu.Items.Add($bUninstall)
$menu.add_Closing({ param($s, $e) if ($e.CloseReason -eq 'ItemClicked') { $e.Cancel = $true } })   # keep open while ticking options
$adv.add_LinkClicked({ $menu.Show($adv, (New-Object Drawing.Point 0, 0), [Windows.Forms.ToolStripDropDownDirection]::AboveRight) })
$miScript.add_CheckedChanged({ if (-not $script:Filling) { Set-Setting 'AllowScript' ([bool]$miScript.Checked) } })

# =====================================================================
# Page 1: Bắt đầu - a guided 3-step workflow for people who do not want to learn the tool:
#   1 Kết nối (one click, everything found on the PC)  ->  2 Mở phần mềm CAD  ->  3 Hỏi AI
# The page opens on the first step that is not done yet; finished steps show a green check.
# =====================================================================
# real program icons (the installed exe's own icon, or the shipped Gemini logo), falls back to a lettered badge.
# For an AI assistant pass $file = '' and the key (claude, claudecode, codex, gemini): the source is looked up.
function Get-ProgramImage([string]$file, [string]$key, [int]$size) {
  $px = S $size
  if (-not $file -and $key -in $script:ClientList) { $file = Get-AiIconSource $key }
  $bmp = Get-IconBitmap $file $px
  if ($bmp) { return $bmp }
  $b = $Badge[$key]; if (-not $b) { $b = @('?', $Pal.faint, $Pal.onAccent) }
  $ms = New-Object IO.MemoryStream (, (New-MenuIcon $b[0] $b[1] $b[2] $px))
  return [Drawing.Image]::FromStream($ms)
}
function New-Pic($img) { $pb = New-Object Windows.Forms.PictureBox; $pb.SizeMode = 'Zoom'; $pb.BackColor = [Drawing.Color]::Transparent; $pb.Image = $img; return $pb }

# ---------- stepper ----------
$script:Step = 1; $script:Done = @{ 1 = $false; 2 = $false; 3 = $false }
$stepInfo = @{ 1 = @('Kết nối', 'làm một lần'); 2 = @('Mở phần mềm CAD', 'chọn phiên bản'); 3 = @('Hỏi AI', 'gõ bằng tiếng Việt') }
$stepUi = @{}
# connector lines between the circles, in separate pieces so nothing is drawn across a circle
$rails = @{}
foreach ($n in 1, 2) { $rails[$n] = Put (New-Object Windows.Forms.Panel) (132 + ($n - 1) * 248 + 26) 27 196 2; $rails[$n].BackColor = $Pal.line; $pgHome.Controls.Add($rails[$n]) }
foreach ($n in 1, 2, 3) {
  $cx = 132 + ($n - 1) * 248
  $dot = Put (New-Object Windows.Forms.Panel) ($cx - 17) 11 34 34; $dot.BackColor = $Pal.page; $dot.Cursor = 'Hand'; $dot.Tag = $n
  $dot.add_Paint({
    param($s, $e)
    $n = [int]$s.Tag; $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $r = New-Object Drawing.Rectangle 1, 1, ($s.Width - 3), ($s.Height - 3)
    $cur = $n -eq $script:Step; $ok = $script:Done[$n]
    if ($cur) { $fill = $Pal.accentBtn; $fg = $Pal.onAccent } elseif ($ok) { $fill = $Pal.green; $fg = $Pal.onAccent } else { $fill = $Pal.surface; $fg = $Pal.muted }
    $g.FillEllipse((New-Object Drawing.SolidBrush $fill), $r)
    if (-not $cur -and -not $ok) { $g.DrawEllipse((New-Object Drawing.Pen $Pal.line, ([float](S 1.5))), $r) }
    $txt = if ($ok -and -not $cur) { '✓' } else { "$n" }
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString($txt, $Fnt.b, (New-Object Drawing.SolidBrush $fg), (New-Object Drawing.RectangleF 0, 1, $s.Width, $s.Height), $sf)
  })
  $t1 = Put (New-Label $stepInfo[$n][0] $Fnt.b $Pal.text) ($cx - 118) 50 236 20; $t1.TextAlign = 'TopCenter'; $t1.Cursor = 'Hand'; $t1.Tag = $n
  $t2 = Put (New-Label $stepInfo[$n][1] $Fnt.s $Pal.muted) ($cx - 118) 70 236 18; $t2.TextAlign = 'TopCenter'; $t2.Tag = $n
  foreach ($c in $dot, $t1, $t2) { $c.add_Click({ Show-Step ([int]$this.Tag) }) }
  $pgHome.Controls.AddRange(@($dot, $t1, $t2)); $dot.BringToFront()
  $stepUi[$n] = @{ dot = $dot; t1 = $t1; t2 = $t2 }
}
$sep = Put (New-Object Windows.Forms.Panel) 14 98 732 1; $sep.BackColor = $Pal.line; $pgHome.Controls.Add($sep)

# one panel per step
$stepPg = @{}
foreach ($n in 1, 2, 3) { $p = Put (New-Object Windows.Forms.Panel) 0 106 $W 336; $p.BackColor = $Pal.page; $p.Visible = $false; $pgHome.Controls.Add($p); $stepPg[$n] = $p }
function Add-StepTitle($p, $title, $text) {
  $a = Put (New-Label $title $Fnt.h2 $Pal.text) 16 2 600 24
  $b = Put (New-Label $text $Fnt.n $Pal.muted) 16 28 728 40
  $p.Controls.AddRange(@($a, $b))
}

# navigation
$bBack = Put (New-Button '←  Quay lại') 14 450 130 36
$bNext = Put (New-Button 'Tiếp tục  →' 'primary') 616 450 130 36
$homeNote = Put (New-Label '' $Fnt.s $Pal.muted) 154 458 452 20; $homeNote.AutoEllipsis = $true; $homeNote.TextAlign = 'TopCenter'
$pgHome.Controls.AddRange(@($bBack, $bNext, $homeNote))
$bBack.add_Click({ Show-Step ($script:Step - 1) }); $bNext.add_Click({ Show-Step ($script:Step + 1) })
function Set-HomeNote([string]$m, [string]$lvl = '') {
  $homeNote.Text = $m
  $col = @{ ok = $Pal.green; warn = $Pal.warn; error = $Pal.red; title = $Pal.accent }[$lvl]
  $homeNote.ForeColor = $(if ($col) { $col } else { $Pal.muted })
}
function Show-Step([int]$n) {
  $n = [Math]::Max(1, [Math]::Min(3, $n)); $script:Step = $n
  foreach ($k2 in 1, 2) { $rails[$k2].BackColor = $(if ($script:Done[$k2]) { $Pal.green } else { $Pal.line }) }
  foreach ($k2 in 1, 2, 3) { $stepPg[$k2].Visible = ($k2 -eq $n); $stepUi[$k2].dot.Invalidate(); $stepUi[$k2].t1.ForeColor = $(if ($k2 -eq $n) { $Pal.accent } else { $Pal.text }) }
  $bBack.Visible = $n -gt 1; $bNext.Visible = $n -lt 3
  # "Tiếp tục" is the main button once the step is done; before that it is a quiet "Bỏ qua"
  if ($script:Done[$n]) { $bNext.Text = 'Tiếp tục  →'; Set-ButtonLook $bNext 'primary' } else { $bNext.Text = 'Bỏ qua  →'; Set-ButtonLook $bNext 'ghost' }
  Set-HomeNote $(switch ($n) {
    1 { if ($script:Done[1]) { 'Đã kết nối. Bấm Tiếp tục.' } else { 'Bấm nút xanh “Kết nối tự động”. Lần đầu mất khoảng 1-3 phút.' } }
    2 { if ($script:Done[2]) { 'CAD đã mở. Mở bản vẽ cần làm rồi bấm Tiếp tục.' } else { 'Bấm Khởi động ở phần mềm bạn muốn dùng.' } }
    3 { 'Bấm “Mở Steve AI”, rồi gõ yêu cầu vào cửa sổ chat.' }
  })
}

# ---------- step 1: connect everything in one click ----------
$s1 = $stepPg[1]
Add-StepTitle $s1 'Nối phần mềm CAD với trợ lý AI' 'Chỉ cần làm một lần. Công cụ đã tự tìm các phần mềm có trên máy bạn: chỉ việc bấm “Kết nối tự động”.'
function New-ListCard($p, $title, $x, $keys, $labels) {
  $cd = New-Card $p $x 74 360 158
  $cap = Put (New-Label $title.ToUpper() $Fnt.cap $Pal.muted) 14 10 330 18; $cd.inner.Controls.Add($cap)
  $rows = @{}; $y = 34
  foreach ($k2 in $keys) {
    $pic = Put (New-Pic $null) 14 $y 22 22
    $nm = Put (New-Label $labels[$k2] $Fnt.n $Pal.text) 44 ($y + 1) 170 22
    $st = Put (New-Label '' $Fnt.s $Pal.faint) 210 ($y + 3) 136 20; $st.TextAlign = 'TopRight'
    $cd.inner.Controls.AddRange(@($pic, $nm, $st)); $rows[$k2] = @{ pic = $pic; nm = $nm; st = $st }; $y += 30
  }
  return $rows
}
$s1Cad = New-ListCard $s1 'Phần mềm CAD trên máy' 14 $script:CadList $script:CadLabel
$s1Ai = New-ListCard $s1 'Trợ lý AI trên máy' 386 $script:ClientList $script:ClientLabel
$bAuto = Put (New-Button '⚡  Kết nối tự động' 'primary') 14 248 280 48; $bAuto.Font = $Fnt.big
$tip.SetToolTip($bAuto, 'Nối mọi phần mềm CAD với mọi trợ lý AI có trên máy')
$autoInfo = Put (New-Label '' $Fnt.s $Pal.muted) 308 248 438 48
$autoLink = Put (New-Link '' $Fnt.s $Pal.accent) 308 250 438 44; $autoLink.Visible = $false
$autoLink.add_LinkClicked({ Start-Process $Url.claudecode })
$prog = Put (New-Object Windows.Forms.ProgressBar) 14 302 280 6; $prog.Style = 'Marquee'; $prog.MarqueeAnimationSpeed = 30; $prog.Visible = $false
$advLink = Put (New-Link 'Muốn tự chọn từng phần mềm, kiểm tra hay xem nhật ký? Mở phần nâng cao' $Fnt.s $Pal.accent) 14 314 500 18
$advLink.add_LinkClicked({ Show-Page 'conn' })
$s1.Controls.AddRange(@($bAuto, $autoInfo, $autoLink, $prog, $advLink))

# what "Kết nối tự động" would connect: every CAD found, every assistant found (Gemini only with an API key)
function Get-AutoPick {
  $cads = @($script:CadList | Where-Object { $cadTile[$_].ok })
  $clis = @($script:ClientList | Where-Object { $aiTile[$_].ok -and ($_ -ne 'gemini' -or (Test-GeminiKey)) })
  return @{ cads = $cads; clis = $clis }
}
function Update-Step1 {
  foreach ($c in $script:CadList) {
    $r = $s1Cad[$c]; $t = $cadTile[$c]
    if (-not $r.pic.Image) { $r.pic.Image = Get-ProgramImage $(if ($cadLaunch[$c].list.Count) { $cadLaunch[$c].list[0].file }) $c 22 }
    $r.nm.Text = $(if ($t.ok -and $t.sub.Text -and $t.sub.Text -notlike '⚠*') { $t.sub.Text } else { $script:CadLabel[$c] })
    if (-not $t.ok) { $r.st.Text = 'chưa cài'; $r.st.ForeColor = $Pal.faint; $r.nm.ForeColor = $Pal.faint }
    elseif ($t.conn) { $r.st.Text = '✓  đã kết nối'; $r.st.ForeColor = $Pal.green; $r.nm.ForeColor = $Pal.text }
    else { $r.st.Text = 'chưa kết nối'; $r.st.ForeColor = $Pal.warn; $r.nm.ForeColor = $Pal.text }
  }
  foreach ($c in $script:ClientList) {
    $r = $s1Ai[$c]; $t = $aiTile[$c]
    if (-not $r.pic.Image) { $r.pic.Image = Get-ProgramImage '' $c 22 }
    if (-not $t.ok) { $r.st.Text = 'chưa cài'; $r.st.ForeColor = $Pal.faint; $r.nm.ForeColor = $Pal.faint }
    elseif ($t.conn) { $r.st.Text = '✓  đã kết nối'; $r.st.ForeColor = $Pal.green; $r.nm.ForeColor = $Pal.text }
    elseif ($c -eq 'gemini' -and -not (Test-GeminiKey)) { $r.st.Text = 'dán API key  ›'; $r.st.ForeColor = $Pal.accent; $r.st.Cursor = 'Hand'; $r.nm.ForeColor = $Pal.text }
    else { $r.st.Text = 'chưa kết nối'; $r.st.ForeColor = $Pal.warn; $r.nm.ForeColor = $Pal.text }
  }
  $pick = Get-AutoPick
  $autoLink.Visible = $false; $autoInfo.Visible = $true
  if (-not $pick.cads) { $bAuto.Enabled = $false; $autoInfo.Text = '⚠  Máy chưa có ZWCAD, AutoCAD hoặc ADSCivil.'; $autoInfo.ForeColor = $Pal.warn }
  elseif (-not $pick.clis) {
    $bAuto.Enabled = $false; $autoInfo.Visible = $false; $autoLink.Visible = $true
    $autoLink.Text = '⚠  Máy chưa có trợ lý AI. Bấm vào đây để tải Claude Code (khuyên dùng), cài xong mở lại công cụ này.'
  } else {
    $bAuto.Enabled = -not $script:Busy
    $todo = @(foreach ($cl in $pick.clis) { foreach ($c in $pick.cads) { if (@($script:Conn[$cl]) -notcontains $c) { 1 } } }).Count
    if ($todo -eq 0) { $autoInfo.Text = "✓  Đã kết nối xong. Bấm ““Tiếp tục”” ở góc dưới bên phải."; $autoInfo.ForeColor = $Pal.green; $bAuto.Text = '↻  Kết nối lại' ; Set-ButtonLook $bAuto 'ghost' }
    else {
      $autoInfo.Text = "Sẽ nối: $(($pick.cads | ForEach-Object { $script:CadLabel[$_] }) -join ', ')`n⇄  $(($pick.clis | ForEach-Object { $script:ClientLabel[$_] }) -join ', ')"
      $autoInfo.ForeColor = $Pal.muted; $bAuto.Text = '⚡  Kết nối tự động'; Set-ButtonLook $bAuto 'primary'
    }
  }
}
$bAuto.add_Click({
  $pick = Get-AutoPick
  $prog.Visible = $true; $script:AutoOk = $false
  Invoke-Busy { $script:AutoOk = Invoke-Connect $pick.cads $pick.clis ([bool]$script:Ads26) '' }
  $prog.Visible = $false
  if ($script:AutoOk) { Set-HomeNote '✓ Kết nối xong. Trợ lý AI đang mở sẵn thì thoát hẳn rồi mở lại.' 'ok'; Show-Step 2 }
  else { Set-HomeNote 'Kết nối có lỗi. Xem nhật ký: ⚙ Tùy chọn nâng cao › Kết nối từng mục…, hoặc gọi hỗ trợ.' 'error' }
})

# Gemini needs a free API key: paste it right here in step 1 (no need for the advanced page)
function Show-GeminiKeyDialog {
  $d = New-Object Windows.Forms.Form; $d.Text = 'Gemini API key'; $d.AutoScaleMode = 'None'
  $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.StartPosition = 'CenterParent'
  $d.ClientSize = New-Object Drawing.Size (S 460), (S 168); $d.BackColor = $Pal.page; $d.ForeColor = $Pal.text; $d.Font = $Fnt.n
  $l1 = Put (New-Label 'Gemini cần một API key (miễn phí). Bấm link bên dưới, đăng nhập Google, tạo key rồi dán vào ô này:' $Fnt.n $Pal.text) 16 12 428 40
  $tb = Put (New-Object Windows.Forms.TextBox) 16 58 428 26; $tb.BackColor = $Pal.input; $tb.ForeColor = $Pal.text; $tb.BorderStyle = 'FixedSingle'; $tb.UseSystemPasswordChar = $true
  $lk = Put (New-Link 'Lấy key miễn phí tại aistudio.google.com' $Fnt.s $Pal.accent) 16 92 300 18
  $lk.add_LinkClicked({ Start-Process $Url.gemini })
  $ok = Put (New-Button 'Lưu key' 'primary') 254 120 92 34; $ok.DialogResult = 'OK'
  $no = Put (New-Button 'Huỷ') 352 120 92 34; $no.DialogResult = 'Cancel'
  $d.Controls.AddRange(@($l1, $tb, $lk, $ok, $no)); $d.AcceptButton = $ok; $d.CancelButton = $no
  if ($d.ShowDialog($form) -eq 'OK' -and $tb.Text.Trim()) {
    Save-GeminiKey $tb.Text.Trim(); Update-View
    Set-HomeNote '✓ Đã lưu Gemini API key. Bấm “Kết nối tự động” để nối Gemini.' 'ok'
  }
}
$s1Ai.gemini.st.add_Click({ if ($aiTile.gemini.ok -and -not $aiTile.gemini.conn -and -not (Test-GeminiKey)) { Show-GeminiKeyDialog } })

# ---------- step 2: start the CAD (pick the version when several are installed) ----------
$s2 = $stepPg[2]
Add-StepTitle $s2 'Mở phần mềm CAD' 'Bấm “Khởi động” ở phần mềm bạn muốn dùng. Máy có nhiều phiên bản thì chọn bản trong danh sách trước. CAD mở xong thì mở bản vẽ cần làm.'
$rescan = Put (New-Link '↻  Quét lại' $Fnt.s $Pal.accent) ($W - 100) 8 84 18; $rescan.TextAlign = 'TopRight'
$tip.SetToolTip($rescan, 'Tìm lại các phiên bản CAD đã cài (sau khi cài thêm bản mới)')
$s2.Controls.Add($rescan)
# one card per CAD: program icon, name, running status, version list (only when there are several), Khởi động
$cadLaunch = @{}; $x = 14
foreach ($c in $script:CadList) {
  $cd = New-Card $s2 $x 76 236 140
  $in = $cd.inner
  $pic = Put (New-Pic $null) 14 14 40 40
  $nm = Put (New-Label $script:CadLabel[$c] $Fnt.h2 $Pal.text) 64 12 160 22
  $st = Put (New-Label '' $Fnt.s $Pal.faint) 65 35 160 18
  $cb = Put (New-Combo) 14 64 206 28; $cb.Visible = $false
  $one = Put (New-Label '' $Fnt.s $Pal.muted) 14 68 206 18; $one.AutoEllipsis = $true
  $go = Put (New-Button '▶  Khởi động' 'primary') 14 98 206 32
  $in.Controls.AddRange(@($pic, $nm, $st, $cb, $one, $go))
  $l = @{ key = $c; card = $cd; pic = $pic; st = $st; cb = $cb; one = $one; go = $go; list = @() }
  $go.Tag = $l; $cb.Tag = $l
  $go.add_Click({
    $t = $this.Tag; $id = Get-PickedLaunchId $t.key
    try { Start-Cad $t.key $id; $t.st.Text = '◌  Đang khởi động…'; $t.st.ForeColor = $Pal.accent; $script:Starting[$t.key] = Get-Date; $script:AutoNext = $true } catch { Write-Log $_.Exception.Message 'error' }
  })
  $cb.add_SelectedIndexChanged({
    $t = $this.Tag; if ($this.SelectedIndex -lt 0) { return }
    $v = $t.list[$this.SelectedIndex]; $tip.SetToolTip($this, $v.file)
    $t.pic.Image = Get-ProgramImage $v.file $t.key 40   # e.g. ADSCivil 2026 and 2027 have their own icons
    if (-not $script:Filling) { Set-Setting "Launch_$($t.key)" $v.id }
  })
  $cadLaunch[$c] = $l; $x += 248
}
$s2Info = Put (New-Label '' $Fnt.n $Pal.muted) 16 232 728 22
$s2Tip = Put (New-Label 'Mẹo: CAD đã mở từ trước cũng được, công cụ tự nhận ra. Thẻ có viền xanh lá là phần mềm đang chạy.' $Fnt.s $Pal.faint) 16 260 728 20
$s2.Controls.AddRange(@($s2Info, $s2Tip))
$script:Starting = @{}
function Get-PickedLaunchId($cad) {
  $l = $cadLaunch[$cad]
  if ($l.list.Count -gt 1 -and $l.cb.SelectedIndex -ge 0) { return $l.list[$l.cb.SelectedIndex].id }
  if ($l.list.Count) { return $l.list[0].id }
  return ''
}
function Fill-Launchers([switch]$Refresh) {
  $script:Filling = $true
  try {
    if ($Refresh) { $script:LauncherCache = @{} }
    foreach ($c in $script:CadList) {
      $l = $cadLaunch[$c]; $l.list = @(Get-CadLaunchers $c)
      $l.cb.Items.Clear()
      if ($l.list.Count -gt 1) {
        foreach ($v in $l.list) { [void]$l.cb.Items.Add("Bản $($v.short)") }
        $want = [string](Get-Setting "Launch_$c" '')
        $i = 0; for ($j = 0; $j -lt $l.list.Count; $j++) { if ($l.list[$j].id -eq $want) { $i = $j } }
        $l.cb.SelectedIndex = $i   # sets the icon too
        $l.cb.Visible = $true; $l.one.Visible = $false
      } else {
        $l.cb.Visible = $false; $l.one.Visible = $true
        $l.one.Text = $(if ($l.list.Count) { $l.list[0].label } else { 'Chưa cài trên máy' })
        if ($l.list.Count) { $tip.SetToolTip($l.one, $l.list[0].file) }
        $l.pic.Image = Get-ProgramImage $(if ($l.list.Count) { $l.list[0].file }) $c 40
      }
      $l.go.Enabled = $l.list.Count -gt 0
      $s1Cad[$c].pic.Image = Get-ProgramImage $(if ($l.list.Count) { $l.list[0].file }) $c 22   # step 1 list: real icon too
    }
  } finally { $script:Filling = $false }
  Update-RunState
}
# running / starting status on the launch cards (timer)
function Update-RunState {
  $running = @()
  foreach ($c in $script:CadList) {
    $l = $cadLaunch[$c]
    if (-not $l.list.Count) { $l.st.Text = 'Chưa cài'; $l.st.ForeColor = $Pal.faint; $l.card.outer.BackColor = $Pal.line; continue }
    $run = Test-CadRunning $c
    if ($run) { $script:Starting.Remove($c); $running += $c }
    $busy = $script:Starting[$c] -and ((Get-Date) - $script:Starting[$c]).TotalSeconds -lt 90
    if ($run) {
      $l.st.Text = '●  Đang chạy'; $l.st.ForeColor = $Pal.green; $l.card.outer.BackColor = $Pal.green
      $l.go.Text = '▶  Mở thêm một phiên'; Set-ButtonLook $l.go 'ghost'
      $tip.SetToolTip($l.go, "$($script:CadLabel[$c]) đang chạy. Bấm để mở thêm một cửa sổ (phiên bản đang chọn).")
    } elseif ($busy) {
      $l.st.Text = '◌  Đang khởi động…'; $l.st.ForeColor = $Pal.accent; $l.card.outer.BackColor = $Pal.accent
    } else {
      $l.st.Text = $(if ($cadTile[$c].ok -and -not $cadTile[$c].conn) { '○  Chưa mở · chưa nối AI' } else { '○  Chưa mở' })
      $l.st.ForeColor = $Pal.faint; $l.card.outer.BackColor = $Pal.line
      $l.go.Text = '▶  Khởi động'; Set-ButtonLook $l.go 'primary'
      $tip.SetToolTip($l.go, $(if ($l.list.Count -gt 1) { 'Chọn phiên bản ở danh sách phía trên rồi bấm Khởi động' } else { "Khởi động $($script:CadLabel[$c])" }))
    }
  }
  $wasDone = $script:Done[2]
  $script:Done[2] = $running.Count -gt 0
  if ($running) { $s2Info.Text = "✓  $(($running | ForEach-Object { $script:CadLabel[$_] }) -join ', ') đang chạy. Mở bản vẽ cần làm rồi bấm ““Tiếp tục””."; $s2Info.ForeColor = $Pal.green }
  elseif ($script:Starting.Count) { $s2Info.Text = '◌  Đang khởi động CAD, chờ khoảng 10-30 giây…'; $s2Info.ForeColor = $Pal.accent }
  else { $s2Info.Text = ''; }
  if ($wasDone -ne $script:Done[2]) {
    # the CAD the user just started is up: move on to the AI step by itself
    if ($script:Done[2] -and $script:AutoNext -and $script:Step -eq 2) { $script:AutoNext = $false; Show-Step 3; Set-HomeNote "✓ $($script:CadLabel[$running[0]]) đã mở. Giờ bấm ““Mở Steve AI””." 'ok' }
    elseif ($script:Step -eq 2) { Show-Step 2 }
    foreach ($n in 1, 2, 3) { $stepUi[$n].dot.Invalidate() }
  }
  Update-AiReady
}
$rescan.add_LinkClicked({ Fill-Launchers -Refresh; Set-HomeNote 'Đã quét lại các phiên bản CAD.' 'ok' })

# ---------- step 3: talk to the AI ----------
$s3 = $stepPg[3]
Add-StepTitle $s3 'Trò chuyện với AI' 'Bấm “Mở Steve AI”: một cửa sổ chat hiện ra. Gõ yêu cầu bằng tiếng Việt, AI sẽ đọc và vẽ trực tiếp trên bản vẽ đang mở.'
$ai = New-Card $s3 14 74 732 168
$aiIn = $ai.inner
$lAi = Put (New-Label 'Trợ lý' $Fnt.s $Pal.muted) 18 14 60 18
$segs = @{}; $sx = 18
foreach ($c in $script:LaunchClients) {
  $segText = @{ claudecode = 'Claude Code'; codex = 'ChatGPT'; gemini = 'Gemini CLI' }[$c]   # short, fits on one line
  $b = Put (New-Button ('  ' + $segText) 'seg') $sx 34 150 34; $b.Name = $c
  $b.Image = Get-ProgramImage '' $c 18; $b.ImageAlign = 'MiddleLeft'; $b.TextImageRelation = 'ImageBeforeText'; $b.Padding = New-Object Windows.Forms.Padding (S 10), 0, (S 6), 0
  $b.add_Click({ $script:AiPick = $this.Name; Set-Setting 'DefaultAI' $this.Name; Update-Segs; Update-AiReady })
  $aiIn.Controls.Add($b); $segs[$c] = $b; $sx += 156
}
function Update-Segs { foreach ($c in $segs.Keys) { if ($segs[$c].Enabled) { Set-ButtonLook $segs[$c] 'seg' ($c -eq $script:AiPick) } } }
$lSk = Put (New-Label 'Việc làm sẵn (skill, không bắt buộc)' $Fnt.s $Pal.muted) 18 78 300 18
$cbSk = Put (New-Combo) 18 98 462 30
[void]$cbSk.Items.Add('Không - tôi tự gõ yêu cầu')
$script:Skills = @(Get-SkillList)
foreach ($s in $script:Skills) { $d = $s.description; if ($d.Length -gt 60) { $d = $d.Substring(0, 57).TrimEnd() + '…' }; [void]$cbSk.Items.Add("$($s.name)  -  $d") }
$cbSk.SelectedIndex = 0
$cs2 = Put (New-Label '' $Fnt.s $Pal.muted) 18 136 470 18   # readiness, see Update-AiReady
# same size and colour as the other main buttons, on the row of the last choice (read top to bottom, then press)
$bOpen = Put (New-Button "▶  Mở Steve AI" 'primary') 500 97 212 34
$tip.SetToolTip($bOpen, 'Mở cửa sổ chat với trợ lý AI, đã nối sẵn với CAD')
$aiIn.Controls.AddRange(@($lAi, $lSk, $cbSk, $cs2, $bOpen))

[void](Add-Caption $s3 'Chưa biết hỏi gì? Bấm một câu để chép, rồi dán vào cửa sổ chat (Ctrl+V)' 16 254 728)
$ex = @('Bản vẽ có những layer nào?', 'Tổng chiều dài layer TIM', 'Ghi kích thước đối tượng', 'Dựng cống 3D từ bản vẽ')
$ex2 = 14; $chipW = 177   # 4 equal chips across the page (not $w: PowerShell names ignore case, $w is $W)
foreach ($t in $ex) {
  $chip = Put (New-Button $t 'ghost') $ex2 276 $chipW 30; $chip.Font = $Fnt.s; $chip.ForeColor = $Pal.text; $chip.AutoEllipsis = $true
  $tip.SetToolTip($chip, 'Bấm để chép câu này, rồi dán vào cửa sổ Steve AI')
  $chip.add_Click({ [Windows.Forms.Clipboard]::SetText($this.Text); Set-HomeNote "Đã chép ““$($this.Text)””. Dán vào cửa sổ Steve AI bằng Ctrl+V." 'ok' })
  $s3.Controls.Add($chip); $ex2 += $chipW + 8
}
$s3Tip = Put (New-Label 'Lần sau không cần mở công cụ này: trong ZWCAD / AutoCAD gõ lệnh AI rồi Enter, hoặc bấm tab Steve AI trên thanh ribbon.' $Fnt.s $Pal.faint) 16 314 728 20
$s3.Controls.Add($s3Tip)

# can the chosen assistant work on a drawing right now?
function Update-AiReady {
  if (-not $cs2) { return }
  $set = { param($text, $color) $cs2.Text = $text; $cs2.ForeColor = $color }
  if (-not $script:AiChoices) { & $set '⚠  Chưa có Claude Code, Codex hoặc Gemini CLI. Xem bước 1.' $Pal.warn; return }
  $cl = $script:AiPick
  if (-not $cl) { & $set 'Chọn một trợ lý.' $Pal.muted; return }
  if ($cl -eq 'gemini' -and -not (Test-GeminiKey)) { & $set '⚠  Gemini chưa có API key. Dán key ở bước 1 (dòng Gemini CLI).' $Pal.warn; return }
  $mine = @($script:Conn[$cl])
  if (-not $mine) { & $set "⚠  $($script:ClientLabel[$cl]) chưa được kết nối. Quay lại bước 1." $Pal.warn; return }
  $up = @($mine | Where-Object { Test-CadRunning $_ })
  if ($up) { & $set "✓  Sẵn sàng  ·  $(($up | ForEach-Object { $script:CadLabel[$_] }) -join ', ') đang chạy" $Pal.green }
  else { & $set '⚠  Chưa mở phần mềm CAD nào. Quay lại bước 2.' $Pal.warn }
}

# step state from the real state of the PC; the page opens on the first unfinished step
function Update-Steps {
  $script:Done[1] = @($script:ClientList | Where-Object { @($script:Conn[$_]).Count }).Count -gt 0
  Update-Step1
  foreach ($n in 1, 2, 3) { $stepUi[$n].dot.Invalidate() }
  if ($script:Step) { Show-Step $script:Step }
}
function Get-FirstOpenStep { if (-not $script:Done[1]) { 1 } elseif (-not $script:Done[2]) { 2 } else { 3 } }

# =====================================================================
# Page 2: Kết nối
# =====================================================================
# A selectable tile. The check mark is painted (a hidden CheckBox keeps the state and raises CheckedChanged).
function New-Tile($parent, $key, $title, $x, $y, $w, $h) {
  $cd = New-Card $parent $x $y $w $h
  $i = $cd.inner; $i.Cursor = 'Hand'
  $chk = New-Object Windows.Forms.CheckBox   # state only, never shown
  $box = Put (New-Object Windows.Forms.Panel) 12 12 18 18; $box.BackColor = [Drawing.Color]::Transparent; $box.Cursor = 'Hand'
  $ttl = Put (New-Label $title $Fnt.b $Pal.text) 38 9 ($w - 48) 22; $ttl.Cursor = 'Hand'
  $sub = Put (New-Label '' $Fnt.s $Pal.muted) 38 31 ($w - 48) 18
  $st = Put (New-Link '' $Fnt.s $Pal.muted) 38 49 ($w - 48) 18
  $i.Controls.AddRange(@($box, $ttl, $sub, $st))
  $t = @{ key = $key; outer = $cd.outer; inner = $i; chk = $chk; box = $box; ttl = $ttl; sub = $sub; st = $st; ok = $false; conn = $false; url = '' }
  foreach ($c in $i, $box, $ttl, $sub, $st, $chk) { $c.Tag = $t }
  $box.add_Paint({
    param($s, $e)
    $t = $s.Tag; $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $r = New-Object Drawing.Rectangle 1, 1, ($s.Width - 3), ($s.Height - 3)
    $on = $t.chk.Checked -and $t.ok
    $col = if (-not $t.chk.Enabled) { $Pal.disabledLine } elseif ($on) { $Pal.accentBtn } else { $Pal.faint }
    if ($on) {
      $g.FillRectangle((New-Object Drawing.SolidBrush $col), $r)
      $pen = New-Object Drawing.Pen $Pal.onAccent, ([float](S 2))
      $u = $s.Width / 18.0
      $g.DrawLines($pen, [Drawing.PointF[]]@((New-Object Drawing.PointF (4.5 * $u), (9 * $u)), (New-Object Drawing.PointF (7.5 * $u), (12 * $u)), (New-Object Drawing.PointF (13.5 * $u), (5.5 * $u))))
    } else {
      $g.FillRectangle((New-Object Drawing.SolidBrush $(if ($t.chk.Enabled) { $Pal.input } else { $Pal.disabled })), $r)
      $g.DrawRectangle((New-Object Drawing.Pen $col, ([float](S 1.5))), $r)
    }
  })
  foreach ($c in $i, $box, $ttl, $sub) { $c.add_Click({ Switch-Tile $this.Tag }) }
  $st.add_LinkClicked({ if ($this.Tag.url) { Start-Process $this.Tag.url } else { Switch-Tile $this.Tag } })
  # hover
  foreach ($c in $i, $box, $ttl, $sub, $st) {
    $c.add_MouseEnter({ $t = $this.Tag; if ($t.ok -and -not $t.chk.Checked) { $t.inner.BackColor = $Pal.hover } })
    $c.add_MouseLeave({ Set-TileLook $this.Tag })
  }
  $chk.add_CheckedChanged({ Set-TileLook $this.Tag; Update-Dependent })
  return $t
}
function Switch-Tile($t) { if ($t.chk.Enabled) { $t.chk.Checked = -not $t.chk.Checked } }
function Set-TileLook($t) {
  if (-not $t.ok) { $bg = $Pal.disabled; $bd = $Pal.disabledLine; $fg = $Pal.faint }
  elseif ($t.chk.Checked) { $bg = $Pal.accentSoft; $bd = $Pal.accent; $fg = $Pal.text }
  else { $bg = $Pal.surface; $bd = $Pal.line; $fg = $Pal.text }
  $t.outer.BackColor = $bd; $t.inner.BackColor = $bg; $t.ttl.ForeColor = $fg
  # 2px border when selected
  $p = if ($t.chk.Checked -and $t.ok) { 2 } else { 1 }
  $t.inner.SetBounds($p, $p, $t.outer.Width - 2 * $p, $t.outer.Height - 2 * $p)
  $t.box.Invalidate()
}
function Set-TileStatus($t, $ok, $conn, $sub, $status, $color, $url = '', $tipText = '') {
  $t.ok = $ok; $t.conn = $conn; $t.url = $url
  $t.chk.Enabled = $ok -or ($t.key -eq 'gemini')
  $t.sub.Text = $sub; $t.sub.ForeColor = $(if ($sub -like '⚠*') { $Pal.warn } else { $Pal.muted })
  $t.st.Text = $status; $t.st.LinkColor = $color; $t.st.ActiveLinkColor = $color
  $t.st.LinkBehavior = $(if ($url) { 'AlwaysUnderline' } else { 'NeverUnderline' })
  $t.st.Cursor = $(if ($url) { 'Hand' } else { 'Default' })
  if ($tipText) { foreach ($c in $t.inner, $t.sub, $t.st, $t.ttl) { $tip.SetToolTip($c, $tipText) } }
  Set-TileLook $t
}

[void](Add-Caption $pgConn '1. Phần mềm CAD' 16 12)
$backHome = Put (New-Link '←  Về trang Bắt đầu' $Fnt.s $Pal.accent) ($W - 170) 12 154 18; $backHome.TextAlign = 'TopRight'
$backHome.add_LinkClicked({ Show-Page 'home' }); $pgConn.Controls.Add($backHome)
$cadTile = @{}; $x = 14
foreach ($c in $script:CadList) { $cadTile[$c] = New-Tile $pgConn $c $script:CadLabel[$c] $x 32 236 74; $x += 248 }

[void](Add-Caption $pgConn '2. Trợ lý AI' 16 120)
$aiTile = @{}; $x = 14
foreach ($c in $script:ClientList) { $aiTile[$c] = New-Tile $pgConn $c $script:ClientLabel[$c] $x 140 176 74; $x += 186 }

[void](Add-Caption $pgConn '3. Kết nối' 16 228 200)
$keyBox = Put (New-Object Windows.Forms.Panel) 330 222 416 30; $keyBox.BackColor = $Pal.page
$lk = Put (New-Label 'Gemini API key' $Fnt.s $Pal.muted) 0 7 92 18
$txtKey = Put (New-Object Windows.Forms.TextBox) 94 3 196 24; $txtKey.UseSystemPasswordChar = $true; $txtKey.Font = $Fnt.n
$txtKey.BackColor = $Pal.input; $txtKey.ForeColor = $Pal.text; $txtKey.BorderStyle = 'FixedSingle'
$getKey = Put (New-Link 'Lấy key miễn phí' $Fnt.s $Pal.accent) 298 7 118 18
$getKey.add_LinkClicked({ Start-Process $Url.gemini })
$keyBox.Controls.AddRange(@($lk, $txtKey, $getKey)); $pgConn.Controls.Add($keyBox)

$bConnect    = Put (New-Button 'Kết nối' 'primary') 14 256 150 38
$bTest       = Put (New-Button 'Kiểm tra') 174 256 110 38
$bDisconnect = Put (New-Button 'Ngắt kết nối') 294 256 124 38
$hint = Put (New-Label '' $Fnt.s $Pal.warn) 432 266 314 20
$tip.SetToolTip($bConnect, 'Nối các CAD đã chọn với các trợ lý AI đã chọn')
$tip.SetToolTip($bTest, 'Thử chạy server và đọc bản vẽ đang mở')
$tip.SetToolTip($bDisconnect, 'Gỡ kết nối giữa các CAD và trợ lý AI đã chọn (chỉ bật khi có cặp đang kết nối)')
$pgConn.Controls.AddRange(@($bConnect, $bTest, $bDisconnect, $hint))

[void](Add-Caption $pgConn 'Nhật ký' 16 308)
$logBox = Put (New-Object Windows.Forms.Panel) 14 328 732 152; $logBox.BackColor = $Pal.line
$log = New-Object Windows.Forms.RichTextBox
$log.SetBounds(1, 1, $logBox.Width - 2, $logBox.Height - 2); $log.ReadOnly = $true; $log.BorderStyle = 'None'
$log.BackColor = $Pal.surface; $log.ForeColor = $Pal.text; $log.Font = $Fnt.s; $log.LanguageOption = 'UIFonts'   # Segoe UI: full Vietnamese glyphs
$logBox.Controls.Add($log); $pgConn.Controls.Add($logBox)
$clr = Put (New-Link 'Xoá' $Fnt.s $Pal.accent) ($W - 60) 308 44 18; $clr.TextAlign = 'TopRight'
$clr.add_LinkClicked({ $log.Clear() }); $pgConn.Controls.Add($clr)

# =====================================================================
# Page 3: Công cụ & Skill
# =====================================================================
$nTools = ($script:ToolCatalog.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
$tabTools.Text = "Công cụ & Skill ($nTools)"
$pt = Put (New-Label 'Không cần nhớ tên tool: cứ gõ yêu cầu bằng lời, AI tự chọn tool phù hợp. Nhấp đúp một skill để chạy ngay.' $Fnt.s $Pal.muted) 16 12 730 18
$searchBox = Put (New-Object Windows.Forms.Panel) 14 38 320 30; $searchBox.BackColor = $Pal.line
$search = New-Object Windows.Forms.TextBox; $search.Font = $Fnt.n; $search.BorderStyle = 'None'
$search.BackColor = $Pal.input; $search.ForeColor = $Pal.text
$searchIn = New-Object Windows.Forms.Panel; $searchIn.SetBounds(1, 1, $searchBox.Width - 2, $searchBox.Height - 2); $searchIn.BackColor = $Pal.input
$search.SetBounds((S 8), [int](($searchIn.Height - $search.PreferredHeight) / 2), $searchIn.Width - (S 16), $search.PreferredHeight)
$searchIn.Controls.Add($search); $searchBox.Controls.Add($searchIn)
$cnt = Put (New-Label '' $Fnt.s $Pal.muted) 346 44 400 18
$lv = Put (New-Object Windows.Forms.ListView) 14 76 732 404
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HeaderStyle = 'Nonclickable'; $lv.BorderStyle = 'FixedSingle'
$lv.Font = $Fnt.s; $lv.ShowItemToolTips = $true; $lv.MultiSelect = $false
$lv.BackColor = $Pal.surface; $lv.ForeColor = $Pal.text
# taller rows: a 1 x rowheight image list
$il = New-Object Windows.Forms.ImageList; $il.ImageSize = New-Object Drawing.Size (S 22), (S 24); $il.ColorDepth = 'Depth32Bit'; $lv.SmallImageList = $il
[void]$lv.Columns.Add('Tool', (S 150)); [void]$lv.Columns.Add('Chức năng', (S 270)); [void]$lv.Columns.Add('Ví dụ bạn có thể gõ', (S 290))
$lv.OwnerDraw = $true
$script:SecFont = New-Object Drawing.Font 'Segoe UI Semibold', 8.25
$lv.add_DrawItem({
  param($s, $e)
  if ("$($e.Item.Tag)" -ne 'hdr') { $e.DrawDefault = $true; return }
  # section row: one band across all columns
  $b = $e.Bounds
  $e.Graphics.FillRectangle((New-Object Drawing.SolidBrush $Pal.accentSoft), $b)
  $r = New-Object Drawing.Rectangle ($b.X + (S 6)), $b.Y, ($b.Width - (S 6)), $b.Height
  [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Item.Text, $script:SecFont, $r, $Pal.accent, [Windows.Forms.TextFormatFlags]'VerticalCenter, Left')
})
$lv.add_DrawSubItem({ param($s, $e) if ("$($e.Item.Tag)" -ne 'hdr') { $e.DrawDefault = $true } })
$lv.add_ItemSelectionChanged({ param($s, $e) if ($e.IsSelected -and "$($e.Item.Tag)" -eq 'hdr') { $e.Item.Selected = $false } })
$lv.add_DrawColumnHeader({
  param($s, $e)
  $e.Graphics.FillRectangle((New-Object Drawing.SolidBrush $Pal.surface), $e.Bounds)
  $e.Graphics.DrawLine((New-Object Drawing.Pen $Pal.line), $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
  $r = New-Object Drawing.Rectangle ($e.Bounds.X + (S 6)), $e.Bounds.Y, ($e.Bounds.Width - (S 6)), $e.Bounds.Height
  [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text.ToUpper(), $Fnt.cap, $r, $Pal.muted, [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
})
$pgTools.Controls.AddRange(@($pt, $searchBox, $cnt, $lv))

function Add-Section([string]$title) {
  $h = New-Object Windows.Forms.ListViewItem($title); $h.Tag = 'hdr'; $h.Font = $script:SecFont
  $h.ForeColor = $Pal.accent; $h.BackColor = $Pal.accentSoft; [void]$h.SubItems.Add(''); [void]$h.SubItems.Add('')
  [void]$lv.Items.Add($h); return $h
}
function Fill-Tools([string]$q) {
  $q = $q.Trim().ToLower(); $qa = (ConvertTo-Ascii $q)
  $hit = { param($parts) if (-not $q) { return $true }; $s = ($parts -join ' ').ToLower(); return ($s.Contains($q) -or (ConvertTo-Ascii $s).Contains($qa)) }
  foreach ($s in $script:Skills) {   # illustrated icon of each skill, centred in the row
    if ($il.Images.ContainsKey($s.name)) { continue }
    $cell = New-Object Drawing.Bitmap (S 22), (S 24); $gc = [Drawing.Graphics]::FromImage($cell); $ic = New-SkillIcon $s.name (S 18)
    $gc.DrawImageUnscaled($ic, (S 1), (S 3)); $gc.Dispose(); $ic.Dispose(); $il.Images.Add($s.name, $cell)
  }
  $lv.BeginUpdate(); $lv.Items.Clear(); $n = 0
  $sk = @($script:Skills | Where-Object { & $hit @($_.name, $_.title, $_.description) })
  if ($sk) {
    [void](Add-Section 'SKILL  ·  quy trình nhiều bước, nhấp đúp để chạy')
    foreach ($s in $sk) {
      $it = New-Object Windows.Forms.ListViewItem($s.title); $it.ImageKey = $s.name; [void]$it.SubItems.Add($s.description); [void]$it.SubItems.Add("/$($s.name)  ·  lệnh CAD: AI-$($s.name.ToUpper())")
      $it.Tag = "skill:$($s.name)"; $it.ForeColor = $Pal.accent; $it.ToolTipText = $s.description; [void]$lv.Items.Add($it); $n++
    }
  }
  foreach ($cat in $script:ToolCatalog.Keys) {
    $rows = @($script:ToolCatalog[$cat] | Where-Object { & $hit @($_[0], $_[1], $_[2], $cat) })
    if (-not $rows) { continue }
    [void](Add-Section "ZWCAD / AUTOCAD  ·  $($cat.ToUpper())")
    foreach ($r in $rows) {
      $it = New-Object Windows.Forms.ListViewItem($r[0]); [void]$it.SubItems.Add($r[1]); [void]$it.SubItems.Add($r[2])
      $it.ToolTipText = "$($r[1])`nVí dụ: $($r[2])"; [void]$lv.Items.Add($it); $n++
    }
  }
  if (& $hit @('adscivil tuyen trac doc tieu chuan tcvn', 'ADSCivil')) {
    [void](Add-Section 'ADSCIVIL')
    $it = New-Object Windows.Forms.ListViewItem('(nghiệp vụ)')
    [void]$it.SubItems.Add('Tuyến, trắc dọc, siêu cao, mạng cống, san nền, tiêu chuẩn TCVN')
    [void]$it.SubItems.Add('Kiểm tra bán kính cong theo TCVN 4054'); [void]$lv.Items.Add($it); $n++
    $it = New-Object Windows.Forms.ListViewItem('(số lượng)')
    [void]$it.SubItems.Add('Khoảng 49 tool với bản 2026, khoảng 290 tool với bản 2027')
    [void]$it.SubItems.Add('Hướng dẫn tôi thiết kế trắc dọc'); [void]$lv.Items.Add($it); $n++
  }
  $lv.EndUpdate()
  $cnt.Text = $(if ($q) { "$n kết quả" } else { "$nTools tool cho ZWCAD / AutoCAD  ·  $($script:Skills.Count) skill" })
}
$search.add_TextChanged({ Fill-Tools $search.Text })
$lv.add_DoubleClick({
  $it = $lv.SelectedItems | Select-Object -First 1
  if ($it -and "$($it.Tag)" -like 'skill:*') {
    $sk = "$($it.Tag)".Substring(6)
    $i = [array]::IndexOf(@($script:Skills | ForEach-Object { $_.name }), $sk)
    if ($i -ge 0) { $cbSk.SelectedIndex = $i + 1 }
    Show-Page 'home'; Open-SteveAI
  }
})

# =====================================================================
# logic
# =====================================================================
$script:LogSink = {
  param($m, $lvl)
  $col = @{ ok = $Pal.green; warn = $Pal.warn; error = $Pal.red; title = $Pal.accent; detail = $Pal.faint }[$lvl]
  if (-not $col) { $col = $Pal.text }
  $log.SelectionStart = $log.TextLength; $log.SelectionLength = 0; $log.SelectionColor = $col
  $log.AppendText($m + "`n"); $log.ScrollToCaret()
  # the home page has no log: show the latest result line there
  # while connecting, every step shows there too, so people see that something is happening
  if ($m.Trim() -and ($lvl -in 'ok', 'warn', 'error' -or ($script:Busy -and $lvl -ne 'detail'))) { Set-HomeNote $m.Trim() $lvl }
  [System.Windows.Forms.Application]::DoEvents()
}
$script:ConfirmSink = { param($q) [Windows.Forms.MessageBox]::Show($form, $q, $script:AppName, 'YesNo', 'Question') -eq 'Yes' }

function Get-Picked($tiles, $order) { @($order | Where-Object { $tiles[$_].chk.Checked -and $tiles[$_].chk.Enabled }) }
# buttons are enabled only when the selection makes sense
function Update-Dependent {
  if (-not $script:aiTile -or -not $script:aiTile.gemini -or -not $script:cadTile.adscivil) { return }
  $keyBox.Visible = $aiTile.gemini.chk.Checked
  $mi26.Enabled = [bool]$script:Ads26 -and $cadTile.adscivil.chk.Checked
  if ($script:Busy) { return }
  $pc = Get-Picked $cadTile $script:CadList; $pa = Get-Picked $aiTile $script:ClientList
  $nc = $pc.Count; $na = $pa.Count
  $bConnect.Enabled = $nc -gt 0 -and $na -gt 0; $bTest.Enabled = $nc -gt 0
  # Ngắt kết nối: only when a picked assistant is really connected to a picked CAD
  $bDisconnect.Enabled = @($pa | Where-Object { $cl = $_; @($script:Conn[$cl] | Where-Object { $_ -in $pc }).Count }).Count -gt 0
  $hint.Text = if ($nc -eq 0 -and $na -eq 0) { '← Chọn CAD (bước 1) và trợ lý AI (bước 2)' }
               elseif ($nc -eq 0) { '← Chọn thêm một phần mềm CAD (bước 1)' } elseif ($na -eq 0) { '← Chọn thêm một trợ lý AI (bước 2)' }
               else { "✓  Đã chọn $nc CAD · $na trợ lý" }
  $hint.ForeColor = $(if ($nc -gt 0 -and $na -gt 0) { $Pal.green } else { $Pal.warn })
}

function Update-View {
  $script:Filling = $true
  $cs = Get-CadStatus; $ks = Get-ClientStatus; $conn = Get-Connections
  if ($env:STEVECAD_FRESH) { foreach ($k2 in @($conn.Keys)) { $conn[$k2] = @() } }   # screenshots / tests: look like a new PC
  $script:Conn = $conn
  foreach ($c in $script:CadList) {
    $users = @($script:ClientList | Where-Object { $conn[$_] -contains $c } | ForEach-Object { $script:ClientLabel[$_] })
    $isConn = $users.Count -gt 0
    $status = if (-not $cs[$c].ok) { 'Chưa cài trên máy' } elseif ($isConn) { "●  Đã nối $($users.Count) trợ lý" } else { '○  Chưa kết nối' }
    $tipText = if ($isConn) { 'Đang nối với: ' + ($users -join ', ') } else { $cs[$c].info }
    $sub = if ($cs[$c].ok) { $cs[$c].info } else { $(if ($c -eq 'adscivil' -and $cs[$c].dir2026) { '⚠ ' + $cs[$c].info } else { '' }) }
    Set-TileStatus $cadTile[$c] $cs[$c].ok $isConn $sub $status $(if ($isConn) { $Pal.green } else { $Pal.faint }) '' $tipText
    if (-not $cs[$c].ok) { $cadTile[$c].chk.Checked = $false }
  }
  $a = $cs.adscivil; $script:Ads26 = [bool]($a.dir2026 -and $a.dir2027)
  $on26 = Test-Ads2026Autoload
  $mi26.Text = 'ADSCivil 2026: tự nạp trợ lý ADSAI khi khởi động' + $(if ($on26) { '  (đang bật)' } elseif (-not $a.dir2026) { '  (không có bản 2026)' } else { '' })
  if (-not $script:Shown) { $mi26.Checked = $on26 -or $script:Ads26; $miScript.Checked = [bool](Get-Setting 'AllowScript' $false) }
  $miScript.Enabled = $cs.zwcad.ok -or $cs.autocad.ok
  foreach ($c in $script:ClientList) {
    $mine = @($conn[$c]); $ok = [bool]$ks[$c].ok
    $isConn = $mine.Count -gt 0
    if (-not $ok -and $c -ne 'gemini') { Set-TileStatus $aiTile[$c] $false $false '' 'Chưa cài  ·  tải về' $Pal.accent $Url[$c] $ks[$c].hint }
    elseif (-not $ok) { Set-TileStatus $aiTile[$c] $true $false 'Tự cài khi kết nối' '○  Chưa cài' $Pal.faint '' $ks[$c].hint }
    else {
      $sub = if ($c -eq 'gemini' -and -not (Test-GeminiKey)) { '⚠ chưa có API key' } elseif ($c -in $script:LaunchClients) { 'cửa sổ lệnh' } else { 'ứng dụng' }
      $st = if ($isConn) { "●  Đã nối $($mine.Count) CAD" } else { '○  Chưa kết nối' }
      $tipText = if ($isConn) { 'Đang nối: ' + (($mine | ForEach-Object { $script:CadLabel[$_] }) -join ', ') } else { 'Đã cài, chưa kết nối' }
      Set-TileStatus $aiTile[$c] $true $isConn $sub $st $(if ($isConn) { $Pal.green } else { $Pal.faint }) '' $tipText
    }
  }
  if (Test-GeminiKey) { $getKey.Text = 'Đã có key (dán để thay)' }
  # Steve AI: only terminal assistants that are installed
  $script:AiChoices = @($script:LaunchClients | Where-Object { $ks[$_].ok })
  foreach ($c in $script:LaunchClients) {
    $segs[$c].Enabled = $c -in $script:AiChoices
    $tip.SetToolTip($segs[$c], $(if ($c -in $script:AiChoices) { "Dùng $($script:ClientLabel[$c])" } else { "Chưa cài $($script:ClientLabel[$c]). Vào thẻ Kết nối." }))
  }
  if ($script:AiPick -notin $script:AiChoices) {
    $want = [string](Get-Setting 'DefaultAI' '')
    $script:AiPick = if ($want -in $script:AiChoices) { $want } elseif ($script:AiChoices) { $script:AiChoices[0] } else { '' }
  }
  Update-Segs
  $bOpen.Enabled = $script:AiChoices.Count -gt 0
  Update-AiReady
  Update-Dependent
  $script:Filling = $false
  Update-Steps
}

function Open-SteveAI {
  if (-not $script:AiPick) { Set-HomeNote 'Chưa có trợ lý AI dạng cửa sổ lệnh (Claude Code, Codex, Gemini CLI).' 'warn'; return }
  $cl = $script:AiPick
  $sk = if ($cbSk.SelectedIndex -gt 0) { $script:Skills[$cbSk.SelectedIndex - 1].name } else { '' }
  Set-Setting 'DefaultAI' $cl
  Start-SteveAI $cl $sk
  Write-Log "Đang mở Steve AI ($($script:ClientLabel[$cl])$(if ($sk) { ", skill $sk" }))..." 'ok'
}
$bOpen.add_Click({ Open-SteveAI })

function Invoke-Busy([scriptblock]$job) {
  $script:Busy = $true
  $all = @($bConnect, $bDisconnect, $bTest, $bOpen, $bAuto); $all | ForEach-Object { $_.Enabled = $false }; $bUninstall.Enabled = $false
  $form.Cursor = 'WaitCursor'
  try { & $job } catch { Write-Log "LỖI: $($_.Exception.Message)" 'error'; Add-ErrorLog 'window' $_.Exception.Message $_.ScriptStackTrace }
  finally {
    $form.Cursor = 'Default'; $bUninstall.Enabled = $true; $script:Busy = $false
    try { Update-View } catch {}
  }
}

$bConnect.add_Click({
  $script:AfterConnect = $null
  Invoke-Busy {
    $key0 = $txtKey.Text; $txtKey.Text = ''
    Set-Setting 'AllowScript' ([bool]$miScript.Checked)
    $cads = Get-Picked $cadTile $script:CadList; $clis = Get-Picked $aiTile $script:ClientList
    if (Invoke-Connect $cads $clis ($mi26.Checked -and $mi26.Enabled) $key0) {
      $script:AfterConnect = @{ cads = @(Get-CadsToStart $cads | Where-Object { $cadLaunch[$_].list.Count }); ai = @($clis | Where-Object { $_ -in $script:LaunchClients }).Count -gt 0 }
    }
  }
  # next step: start the selected CAD programs that are not running (the version picked on Bắt đầu), and Steve AI
  $nx = $script:AfterConnect
  if (-not $nx) { return }
  $doAi = $nx.ai -and $bOpen.Enabled
  $what = @(); if ($nx.cads) { $what += (($nx.cads | ForEach-Object { (Get-CadLauncher $_ (Get-PickedLaunchId $_)).label }) -join ', ') }; if ($doAi) { $what += 'cửa sổ Steve AI' }
  if (-not $what) { return }
  if (Confirm-User "Kết nối xong.`n`nMở $($what -join ' và ') để bắt đầu làm việc ngay?") {
    foreach ($c in $nx.cads) { try { Start-Cad $c (Get-PickedLaunchId $c); $script:Starting[$c] = Get-Date } catch { Write-Log $_.Exception.Message 'error' } }
    if ($doAi) { Open-SteveAI }
    Show-Page 'home'; Update-RunState
  }
})
$bDisconnect.add_Click({
  $cads = Get-Picked $cadTile $script:CadList; $clis = Get-Picked $aiTile $script:ClientList
  Invoke-Busy { Invoke-Disconnect $cads $clis ($mi26.Checked -and $mi26.Enabled) }
})
$bTest.add_Click({
  $cads = Get-Picked $cadTile $script:CadList
  Invoke-Busy { Invoke-Test $cads }
})
$bUninstall.add_Click({
  $menu.Close()
  $q = "Gỡ toàn bộ $($script:AppName)?`n`n- Ngắt ZWCAD, AutoCAD, ADSCivil khỏi mọi trợ lý AI`n- Gỡ lệnh AI / STEVEAI, tắt tự nạp ADSCivil 2026`n- Xoá server, shortcut và mục trong Settings > Apps`n`nThư mục làm việc (có API key) được giữ lại."
  if (-not (Confirm-User $q)) { return }
  Show-Page 'conn'
  Invoke-Busy { Invoke-Uninstall }
})

# keep the running state on the launch cards current
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 3000
$script:LiveTick = 0
$timer.add_Tick({
  if ($script:Busy) { return }
  try { Update-RunState } catch {}
  # every 15 s: a ZWCAD that runs without the Steve AI menu gets it
  $script:LiveTick++
  if (-not $env:STEVECAD_SELFTEST -and $script:LiveTick % 5 -eq 2) {
    # ZWCAD closed: write its start-up entry again (it overwrote the list on exit)
    try { if (-not @(Get-CadProcess 'zwcad').Count -and -not (Test-CadAddon 'zwcad')) { Repair-CadAddon } } catch {}
    try { if ((Update-RunningZwcad) -eq 'ok') { Write-Log 'ZWCAD đang mở: đã nạp lệnh AI và tab ribbon Steve AI.' 'ok' } } catch {}
  }
})

$form.add_HandleCreated({
  if ($script:Dark) { try { $v = 1; [void][SteveCad.Win]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4) } catch {} }
})
$form.add_Shown({
  Set-DarkScroll $lv; Set-DarkScroll $log
  try { Update-View } catch { Write-Log "Lỗi đọc trạng thái: $($_.Exception.Message)" 'error' }
  if ($script:FirstRun) { try { Install-Self; Write-Log 'Đã tạo shortcut Steve AI Connect và Steve AI trên Desktop.' 'detail' } catch {} }
  if ($script:FirstRun -and -not $env:STEVECAD_SELFTEST) { Invoke-Busy { Update-Installed } }
  try { Repair-CadAddon } catch {}
  try { Fill-Launchers } catch { Write-Log "Lỗi tìm phiên bản CAD: $($_.Exception.Message)" 'error' }
  # asked once, in plain words: a security setting is never changed silently
  if (-not ($env:STEVECAD_SELFTEST -or $env:STEVECAD_SNAPSHOT) -and (Test-CadAddon 'autocad') -and $null -eq (Get-Setting 'TrustAcad' $null)) {
    $q = "AutoCAD / Civil 3D sẽ hỏi bảo mật khi nạp Steve AI.`n`nThêm 3 thư mục của Steve AI vào Trusted Locations (Options > Files) để không phải hỏi nữa?`n`n" + (@(Get-AcadTrustDirs) -join "`n") + "`n`nAutoCAD sẽ nạp mọi file chương trình trong các thư mục này mà không hỏi. Có thể tắt trong Tùy chọn nâng cao."
    Set-Trust ([Windows.Forms.MessageBox]::Show($form, $q, $script:AppName, 'YesNo', 'Question') -eq 'Yes')
  }
  # one-time registration (email code). Not for self-tests and screenshots.
  if (-not ($env:STEVECAD_SELFTEST -or $env:STEVECAD_SNAPSHOT) -and $script:RegisterUrl -and -not (Test-Registered)) {
    if (-not (Show-Register)) { $form.Close(); return }
  }
  $script:Shown = $true
  Fill-Tools ''
  try { [void][SteveCad.Win]::SendMessage($search.Handle, 0x1501, [IntPtr]1, 'Tìm tool, ví dụ: kích thước, 3D, PDF...') } catch {}
  Write-Log "Chọn phần mềm CAD và trợ lý AI rồi bấm Kết nối." 'title'
  Write-Log "Kết nối xong, sang thẻ Bắt đầu: khởi động CAD rồi bấm 'Mở Steve AI' (hoặc gõ AI trong ZWCAD / AutoCAD)."
  # first run (nothing connected yet): open on the setup page
  # the guided page, on the first step that is not done yet
  Show-Page 'home'; Show-Step (Get-FirstOpenStep)
  $form.ActiveControl = $(switch ($script:Step) { 1 { $bAuto } 2 { $cadLaunch[$script:CadList[0]].go } default { $bOpen } })
  $timer.Start()
  if (-not ($env:STEVECAD_SELFTEST -or $env:STEVECAD_SNAPSHOT) -and $script:RegisterUrl -and $null -eq (Get-Setting 'SendErrors' $null)) {
    $q = "Khi công cụ gặp lỗi, có tự gửi báo lỗi cho Steve để sửa không?`n`nChỉ gửi: nội dung lỗi, vị trí trong mã, phiên bản Windows, CAD và công cụ.`nKhông gửi: tên, email, SĐT, tên máy, đường dẫn, tên hay nội dung bản vẽ, nội dung chat.`n`nĐổi lại bất cứ lúc nào trong Tùy chọn nâng cao."
    $yes = [Windows.Forms.MessageBox]::Show($form, $q, $script:AppName, 'YesNo', 'Question') -eq 'Yes'
    Set-Setting 'SendErrors' $yes; $miErr.Checked = $yes
  }
  if (-not ($env:STEVECAD_SELFTEST -or $env:STEVECAD_SNAPSHOT)) { try { [void](Send-ErrorReports) } catch {} }
  if (-not ($env:STEVECAD_SELFTEST -or $env:STEVECAD_SNAPSHOT)) { try { Start-UpdateCheck } catch {} }
  if ($env:STEVECAD_SELFTEST) {
    # Self-test: click every button of the guided page for real (with STEVECAD_DRYRUN no CAD / AI is started),
    # after the timer's refresh has run, and write PASS / FAIL lines to the file named by STEVECAD_SELFTEST.
    $res = New-Object Collections.ArrayList
    $try = { param($name, [scriptblock]$act) try { & $act; [void]$res.Add("PASS  $name") } catch { [void]$res.Add("FAIL  $name : $($_.Exception.Message)") } }
    & $try 'timer refresh x2' { Update-RunState; Update-RunState }
    foreach ($c in $script:CadList) {
      $l = $cadLaunch[$c]
      if (-not $l.list.Count) { [void]$res.Add("SKIP  Khởi động $c (chưa cài)"); continue }
      & $try "Tag nút Khởi động $c còn nguyên" { if (-not ($l.go.Tag -is [hashtable]) -or $l.go.Tag.key -ne $c) { throw "Tag = '$($l.go.Tag)'" } }
      & $try "bấm Khởi động $c" { Show-Step 2; $l.go.PerformClick() }
      if ($l.list.Count -gt 1) { & $try "đổi phiên bản $c" { $l.cb.SelectedIndex = $l.list.Count - 1; $l.cb.SelectedIndex = 0 } }
    }
    foreach ($n0 in 1, 2, 3) { & $try "chuyển bước $n0" { Show-Step $n0 } }
    & $try 'Tiếp tục / Quay lại' { Show-Step 2; $bNext.PerformClick(); $bBack.PerformClick() }
    foreach ($c in $segs.Keys) { if ($segs[$c].Enabled) { & $try "chọn trợ lý $c" { $segs[$c].PerformClick() } } }
    & $try 'bấm Mở Steve AI' { Show-Step 3; $bOpen.PerformClick() }
    if ($env:STEVECAD_REGTEST) { . $env:STEVECAD_REGTEST }   # registration test script (needs a local test server)
    & $try 'mở trang nâng cao và quay về' { Show-Page 'conn'; Show-Page 'home' }
    & $try 'tab Công cụ & tìm kiếm' { Show-Page 'tools'; $search.Text = 'kich thuoc'; $search.Text = ''; Show-Page 'home' }
    [IO.File]::WriteAllLines($env:STEVECAD_SELFTEST, [string[]]$res, (New-Object Text.UTF8Encoding $false))
    $form.Close(); return
  }
  if ($env:STEVECAD_SNAPSHOT) {   # README screenshots: render the form itself (never the screen)
    if ($env:STEVECAD_SNAPPAGE) { Show-Page $env:STEVECAD_SNAPPAGE }
    if ($env:STEVECAD_SNAPSTEP) { Show-Step ([int]$env:STEVECAD_SNAPSTEP) }
    if ($env:STEVECAD_SNAPDIALOG) {
      # open the dialog exactly as a click does (ShowDialog), capture it from a timer, then close everything
      $script:SnapTimer = New-Object Windows.Forms.Timer; $script:SnapTimer.Interval = 1200
      $script:SnapTimer.add_Tick({
        $script:SnapTimer.Stop()
        $dl = @([Windows.Forms.Application]::OpenForms | Where-Object { $_ -ne $form })[0]
        if ($dl) {
          $b2 = New-Object Drawing.Bitmap $dl.Width, $dl.Height
          $dl.DrawToBitmap($b2, (New-Object Drawing.Rectangle 0, 0, $dl.Width, $dl.Height)); $b2.Save($env:STEVECAD_SNAPSHOT, [Drawing.Imaging.ImageFormat]::Png); $dl.Close()
        }
      })
      $script:SnapTimer.Start()
      switch ($env:STEVECAD_SNAPDIALOG) { 'about' { Show-About } 'register' { [void](Show-Register) } 'feature' { Show-Feature } 'share' { Show-ShareSkill } 'update' { Show-Update @{ tag = 'v9.9.9'; notes = 'Bản thử' } } default { Show-Coffee } }
      $form.Close(); return
    }
    if ($env:STEVECAD_SNAPPICK) { $cadTile.zwcad.chk.Checked = $true; $aiTile.claudecode.chk.Checked = $true }
    $form.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300
    $bmp = New-Object Drawing.Bitmap $form.Width, $form.Height
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle 0, 0, $form.Width, $form.Height))
    $bmp.Save($env:STEVECAD_SNAPSHOT, [Drawing.Imaging.ImageFormat]::Png); $form.Close()
  }
})
[void]$form.ShowDialog()
$timer.Stop()
