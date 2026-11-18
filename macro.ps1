Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @'
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Drawing2D;
public static class SoftTheme {
    public static GraphicsPath Shape(RectangleF bounds, float radius) {
        float d = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
        GraphicsPath path = new GraphicsPath();
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
    public static void PaintButton(Graphics g, Control c, bool hover, bool down, bool focus) {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(c.Parent == null ? SystemColors.Control : c.Parent.BackColor);
        Color fill = c.BackColor;
        Color text = c.ForeColor;
        if (!c.Enabled) { fill = Color.FromArgb(239, 233, 247); text = Color.FromArgb(151, 138, 171); }
        else if (down) fill = ControlPaint.Dark(fill, 0.06f);
        else if (hover) fill = ControlPaint.Light(fill, 0.10f);
        using (GraphicsPath path = Shape(new RectangleF(1, 1, c.Width - 2, c.Height - 2), 12))
        using (SolidBrush brush = new SolidBrush(fill)) { g.FillPath(brush, path); }
        TextRenderer.DrawText(g, c.Text, c.Font, new Rectangle(5, 3, c.Width - 10, c.Height - 6), text,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
        if (focus && c.Enabled) {
            using (GraphicsPath path = Shape(new RectangleF(4, 4, c.Width - 8, c.Height - 8), 9))
            using (Pen pen = new Pen(Color.FromArgb(124, 85, 184), 1)) { g.DrawPath(pen, path); }
        }
    }
}
public class SoftCard : Panel {
    public SoftCard() { DoubleBuffered = true; }
    protected override void OnPaintBackground(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent == null ? SystemColors.Control : Parent.BackColor);
        using (GraphicsPath path = SoftTheme.Shape(new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), 20))
        using (SolidBrush brush = new SolidBrush(BackColor))
        using (Pen border = new Pen(Color.FromArgb(232, 222, 245))) {
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(border, path);
        }
    }
}
public class SoftButton : Button {
    private bool hover, down;
    public SoftButton() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true); }
    protected override void OnPaint(PaintEventArgs e) { SoftTheme.PaintButton(e.Graphics, this, hover, down, Focused); }
    protected override void OnMouseEnter(EventArgs e) { hover = true; base.OnMouseEnter(e); Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; base.OnMouseLeave(e); Invalidate(); }
    protected override void OnMouseDown(MouseEventArgs e) { down = true; base.OnMouseDown(e); Invalidate(); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; base.OnMouseUp(e); Invalidate(); }
}
public class SoftToggle : CheckBox {
    private bool hover;
    public SoftToggle() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true); }
    protected override void OnPaint(PaintEventArgs e) { SoftTheme.PaintButton(e.Graphics, this, hover, false, Focused); }
    protected override void OnMouseEnter(EventArgs e) { hover = true; base.OnMouseEnter(e); Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; base.OnMouseLeave(e); Invalidate(); }
    protected override void OnCheckedChanged(EventArgs e) { base.OnCheckedChanged(e); Invalidate(); }
}
public static class MacroKeyboard {
    [StructLayout(LayoutKind.Sequential)]
    public struct KeyboardInput {
        public ushort vk, scan;
        public uint flags, time;
        public UIntPtr extra;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct MouseInput {
        public int x, y;
        public uint data, flags, time;
        public UIntPtr extra;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public KeyboardInput keyboard;
        [FieldOffset(0)] public MouseInput mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct Input {
        public uint type;
        public InputUnion data;
    }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);
    public static int InputSize { get { return Marshal.SizeOf(typeof(Input)); } }
    public static Input MakeInput(ushort scan, bool up) {
        Input input = new Input();
        input.type = 1;
        input.data.keyboard.scan = scan;
        input.data.keyboard.flags = (uint)(0x0008 | (up ? 0x0002 : 0));
        return input;
    }
    private static void Send(ushort scan, bool up) {
        if (SendInput(1, new Input[] { MakeInput(scan, up) }, InputSize) != 1)
            throw new InvalidOperationException("Windows rejected keyboard input.");
    }
    public static void Press(ushort scan) {
        Send(scan, false);
        try { System.Threading.Thread.Sleep(80); }
        finally { Send(scan, true); }
    }
    public static void Chord(ushort modifier, ushort key) {
        Send(modifier, false);
        try {
            System.Threading.Thread.Sleep(40);
            Press(key);
        } finally { Send(modifier, true); }
    }
    public static Input MakeUnicodeInput(char value, bool up) {
        Input input = new Input();
        input.type = 1;
        input.data.keyboard.scan = value;
        input.data.keyboard.flags = (uint)(0x0004 | (up ? 0x0002 : 0));
        return input;
    }
    private static void SendUnicode(char value, bool up) {
        if (SendInput(1, new Input[] { MakeUnicodeInput(value, up) }, InputSize) != 1)
            throw new InvalidOperationException("Windows rejected text input.");
    }
    public static void TypeElement(string text) {
        // Keep numeric input compatible with the original game's scan-code path.
        if (text.Length == 1 && text[0] >= '0' && text[0] <= '9') {
            Press((ushort)(text[0] == '0' ? 0x0B : 0x02 + text[0] - '1'));
            return;
        }
        foreach (char value in text) {
            SendUnicode(value, false);
            try { System.Threading.Thread.Sleep(20); }
            finally { SendUnicode(value, true); }
        }
    }
}
public static class MacroApp {
    public const string Id = "Hans.ChatMacro.Desktop";
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    public static void Configure() {
        Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(Id));
    }
}
public class MacroForm : Form {
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr type, IntPtr value);
    private Icon largeIcon, smallIcon;
    private void UpdateWindowIcons() {
        if (!IsHandleCreated || Icon == null) return;
        Icon nextLarge = new Icon(Icon, 32, 32);
        Icon nextSmall = new Icon(Icon, 16, 16);
        SendMessage(Handle, 0x0080, new IntPtr(1), nextLarge.Handle);
        SendMessage(Handle, 0x0080, IntPtr.Zero, nextSmall.Handle);
        if (largeIcon != null) largeIcon.Dispose();
        if (smallIcon != null) smallIcon.Dispose();
        largeIcon = nextLarge;
        smallIcon = nextSmall;
    }
    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); UpdateWindowIcons(); }
    protected override void OnShown(EventArgs e) { UpdateWindowIcons(); base.OnShown(e); }
    protected override void Dispose(bool disposing) {
        base.Dispose(disposing);
        if (disposing) {
            if (largeIcon != null) { largeIcon.Dispose(); largeIcon = null; }
            if (smallIcon != null) { smallIcon.Dispose(); smallIcon = null; }
        }
    }
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
    public event EventHandler StartRequested;
    public event EventHandler StopRequested;
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) {
            if (m.WParam.ToInt32() == 1 && StartRequested != null) StartRequested(this, EventArgs.Empty);
            if (m.WParam.ToInt32() == 2 && StopRequested != null) StopRequested(this, EventArgs.Empty);
        }
        base.WndProc(ref m);
    }
}
'@
[MacroApp]::Configure()
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object MacroForm
$form.Text = '클라이언트 반복 매크로'
$form.ClientSize = New-Object System.Drawing.Size(760, 754)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.ShowInTaskbar = $true
$form.ShowIcon = $true
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F6F1FC')
$form.Font = New-Object System.Drawing.Font('맑은 고딕', 10)
$ink = [System.Drawing.ColorTranslator]::FromHtml('#332540')
$muted = [System.Drawing.ColorTranslator]::FromHtml('#81718F')
$accent = [System.Drawing.ColorTranslator]::FromHtml('#9568C9')
$form.ForeColor = $ink
function Add-Text($parent, $text, $x, $y, $width, $height, $size = 10, $bold = $false) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($width, $height)
    $style = [System.Drawing.FontStyle]::Regular
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
    $label.Font = New-Object System.Drawing.Font('맑은 고딕', $size, $style)
    $label.ForeColor = $ink
    $parent.Controls.Add($label)
    return $label
}
function Add-Card($x, $y, $width, $height) {
    $panel = New-Object SoftCard
    $panel.Location = New-Object System.Drawing.Point($x, $y)
    $panel.Size = New-Object System.Drawing.Size($width, $height)
    $panel.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($panel)
    return $panel
}
function Add-Button($parent, $text, $x, $y, $width, $height) {
    $button = New-Object SoftButton
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($x, $y)
    $button.Size = New-Object System.Drawing.Size($width, $height)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#EFE5FA')
    $button.ForeColor = $accent
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $parent.Controls.Add($button)
    return $button
}
$iconPath = Join-Path $PSScriptRoot 'assets\chat-macro.ico'
$imagePath = Join-Path $PSScriptRoot 'assets\chat-macro.png'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Object System.Drawing.Point(24, 25)
$logo.Size = New-Object System.Drawing.Size(52, 52)
$logo.SizeMode = 'Zoom'
if (Test-Path -LiteralPath $imagePath) { $logo.Image = [System.Drawing.Image]::FromFile($imagePath) }
$form.Controls.Add($logo)
$title = Add-Text $form '클라이언트 반복 매크로' 90 18 640 38 21 $true
$subtitle = Add-Text $form '선택한 클라만, 원하는 간격으로. Enter → 입력 내용 → Enter' 93 64 640 25 10
$subtitle.ForeColor = $muted

$hotkeyOptions = [ordered]@{}
$keyScans = [ordered]@{
    '1' = 0x02; '2' = 0x03; '3' = 0x04; '4' = 0x05; '5' = 0x06; '6' = 0x07
    'Q' = 0x10; 'W' = 0x11; 'E' = 0x12
    'F5' = 0x3F; 'F6' = 0x40; 'F7' = 0x41; 'F8' = 0x42; 'F9' = 0x43
    'F10' = 0x44; 'F11' = 0x57; 'F12' = 0x58
}
foreach ($modifier in @('Ctrl', 'Shift', 'Alt')) {
    $modifierScan = switch ($modifier) { 'Ctrl' { 0x1D } 'Shift' { 0x2A } 'Alt' { 0x38 } }
    foreach ($key in $keyScans.Keys) {
        $hotkeyOptions["$modifier + $key"] = @{ Modifier = $modifierScan; Scan = $keyScans[$key] }
    }
}
foreach ($key in @('F10', 'F11', 'F12')) {
    $hotkeyOptions[$key] = @{ Modifier = 0; Scan = $keyScans[$key] }
}
$hotkeyOptions['` (백틱)'] = @{ Modifier = 0; Scan = 0x29 }
$hotkeyOptions['\ (백슬래시)'] = @{ Modifier = 0; Scan = 0x2B }
$hotkeyOptions['Scroll Lock'] = @{ Modifier = 0; Scan = 0x46 }
$clientSettings = Add-Card 24 108 360 306
$null = Add-Text $clientSettings '01  입력할 클라 선택' 18 16 324 28 12 $true
$clientHeader = Add-Text $clientSettings '고상 트레이더스의 개별 전환 단축키와 맞춰 주세요.' 18 49 324 24 9
$clientHeader.ForeColor = $muted
$clientChecks = @()
$clientHotkeys = @()
$defaultHotkeys = @('Ctrl + F10', 'Ctrl + F11', 'Shift + F11')
for ($slot = 0; $slot -lt 3; $slot++) {
    $check = New-Object System.Windows.Forms.CheckBox
    $check.Text = "$($slot + 1)클 입력"
    $check.Checked = $true
    $check.Location = New-Object System.Drawing.Point(18, (87 + $slot * 58))
    $check.Size = New-Object System.Drawing.Size(108, 30)
    $check.Font = New-Object System.Drawing.Font('맑은 고딕', 11, [System.Drawing.FontStyle]::Bold)
    $check.ForeColor = $accent
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    $combo.Location = New-Object System.Drawing.Point(132, (87 + $slot * 58))
    $combo.Size = New-Object System.Drawing.Size(210, 30)
    $combo.MaxDropDownItems = 12
    [void]$combo.Items.AddRange([object[]]@($hotkeyOptions.Keys))
    $combo.SelectedItem = $defaultHotkeys[$slot]
    $check.Tag = $combo
    $check.Add_CheckedChanged({
        param($sender, $eventArgs)
        $sender.Tag.Enabled = $sender.Checked
        if ($sender.Checked) { $sender.ForeColor = $accent }
        else { $sender.ForeColor = $muted }
    })
    $clientSettings.Controls.Add($check)
    $clientSettings.Controls.Add($combo)
    $clientChecks += $check
    $clientHotkeys += $combo
}
$clientHint = Add-Text $clientSettings '체크한 클라만 1 → 2 → 3 순서로 입력합니다.' 18 267 324 24 9
$clientHint.ForeColor = $muted

$repeatCard = Add-Card 404 108 332 204
$null = Add-Text $repeatCard '02  반복 간격' 18 16 296 28 12 $true
$interval = New-Object System.Windows.Forms.NumericUpDown
$interval.Location = New-Object System.Drawing.Point(18, 59)
$interval.Size = New-Object System.Drawing.Size(184, 38)
$interval.Font = New-Object System.Drawing.Font('맑은 고딕', 17, [System.Drawing.FontStyle]::Bold)
$interval.Minimum = 1
$interval.Maximum = 86400
$interval.Value = 60
$interval.ThousandsSeparator = $true
$repeatCard.Controls.Add($interval)
$null = Add-Text $repeatCard '초 후 반복' 215 73 100 28 10
$presets = New-Object System.Windows.Forms.Panel
$presets.Location = New-Object System.Drawing.Point(18, 111)
$presets.Size = New-Object System.Drawing.Size(296, 47)
$repeatCard.Controls.Add($presets)
$presetMinutes = @(5, 10, 20, 30)
for ($index = 0; $index -lt $presetMinutes.Count; $index++) {
    $minutes = $presetMinutes[$index]
    $seconds = $minutes * 60
    $button = Add-Button $presets "$minutes 분`n$seconds 초" ($index * 75) 0 71 46
    $button.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
    $button.Tag = $seconds
    $button.Add_Click({
        param($sender, $eventArgs)
        if ($interval.Enabled) { $interval.Value = [decimal]$sender.Tag }
    })
}
$intervalHint = Add-Text $repeatCard '초 직접 입력 · 위아래 버튼으로 미세 조절' 18 170 296 23 9
$intervalHint.ForeColor = $muted

$autoSettings = Add-Card 404 328 332 246
$autoTitle = Add-Text $autoSettings '03  자동 중지' 18 16 145 28 12 $true
$autoStop = New-Object SoftToggle
$autoStop.Appearance = 'Button'
$autoStop.Text = '자동 중지: 꺼짐'
$autoStop.TextAlign = 'MiddleCenter'
$autoStop.FlatStyle = 'Flat'
$autoStop.FlatAppearance.BorderSize = 0
$autoStop.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#EFE5FA')
$autoStop.ForeColor = $accent
$autoStop.Location = New-Object System.Drawing.Point(18, 57)
$autoStop.Size = New-Object System.Drawing.Size(145, 34)
$autoSettings.Controls.Add($autoStop)
$shutdownOption = New-Object System.Windows.Forms.CheckBox
$shutdownOption.Text = 'PC도 종료 (+5분)'
$shutdownOption.Location = New-Object System.Drawing.Point(176, 17)
$shutdownOption.Size = New-Object System.Drawing.Size(148, 27)
$shutdownOption.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
$shutdownOption.ForeColor = $accent
$shutdownOption.Enabled = $false
$autoSettings.Controls.Add($shutdownOption)
$shutdownOption.BringToFront()
$stopMinutes = New-Object System.Windows.Forms.NumericUpDown
$stopMinutes.Location = New-Object System.Drawing.Point(176, 59)
$stopMinutes.Size = New-Object System.Drawing.Size(85, 30)
$stopMinutes.Minimum = 1
$stopMinutes.Maximum = 10080
$stopMinutes.Value = 60
$autoSettings.Controls.Add($stopMinutes)
$null = Add-Text $autoSettings '분 후' 270 62 44 25 10
for ($hours = 1; $hours -le 4; $hours++) {
    $minutes = $hours * 60
    $minuteButton = Add-Button $autoSettings "$minutes 분`n($hours 시간)" (18 + ($hours - 1) * 75) 105 71 46
    $minuteButton.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
    $minuteButton.Tag = $minutes
    $minuteButton.Add_Click({
        param($sender, $eventArgs)
        $stopMinutes.Value = [decimal]$sender.Tag
        $autoStop.Checked = $true
    })
}
$autoHint = Add-Text $autoSettings "분 단위로 직접 설정 · 1~10,080분`n일시정지 중에는 사용 시간도 멈춥니다.`nPC 종료 체크 시 중지 5분 뒤 종료합니다.`n저장하지 않은 작업이 닫힐 수 있습니다." 18 160 296 80 9
$autoHint.ForeColor = $muted
$autoStop.Add_CheckedChanged({
    $shutdownOption.Enabled = $autoStop.Checked
    if ($autoStop.Checked) {
        $autoStop.Text = '자동 중지: 켜짐'
        $autoStop.BackColor = $accent
        $autoStop.ForeColor = [System.Drawing.Color]::White
    } else {
        $shutdownOption.Checked = $false
        $autoStop.Text = '자동 중지: 꺼짐'
        $autoStop.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#EFE5FA')
        $autoStop.ForeColor = $accent
    }
})
$guide = Add-Card 24 430 360 144
$null = Add-Text $guide '입력할 내용' 18 15 324 27 11 $true
$inputContent = New-Object System.Windows.Forms.TextBox
$inputContent.Location = New-Object System.Drawing.Point(18, 49)
$inputContent.Size = New-Object System.Drawing.Size(324, 30)
$inputContent.Text = '1'
$inputContent.MaxLength = 200
$guide.Controls.Add($inputContent)
$inputHint = Add-Text $guide "기본값 ‘1’은 예시입니다. 원하는 내용을 입력하세요.`nEnter → 위 입력 내용 → Enter 순서로 전송합니다." 18 88 324 44 9
$inputHint.ForeColor = $muted
$start = Add-Button $form '▶  시작' 24 594 232 50
$start.BackColor = $accent
$start.ForeColor = [System.Drawing.Color]::White
$start.Font = New-Object System.Drawing.Font('맑은 고딕', 12, [System.Drawing.FontStyle]::Bold)
$pause = Add-Button $form 'Ⅱ  일시정지' 264 594 232 50
$pause.Enabled = $false
$stop = Add-Button $form '■  중지' 504 594 232 50
$stop.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F9E9EC')
$stop.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#AC445A')
$stop.Enabled = $false
$status = Add-Text $form '● 대기 중 · 클라와 시간을 설정한 뒤 시작하세요' 27 660 470 26 10 $true
$cancelShutdown = Add-Button $form 'PC 종료 예약 취소' 504 655 232 32
$cancelShutdown.Enabled = $false
$autoStatus = Add-Text $form '자동 중지 시간은 시작할 때부터 계산합니다.' 27 691 706 24 9
$autoStatus.ForeColor = $muted
$help = Add-Text $form '시작 Ctrl + [  /  중지 Ctrl + ]  ·  창 전환 전후 대기 1초' 27 725 590 22 9
$help.ForeColor = $muted
$currentVersion = $env:CHATMACRO_VERSION
if (-not $currentVersion) {
    $versionFile = Join-Path $PSScriptRoot 'packaging\version.json'
    if (Test-Path -LiteralPath $versionFile) {
        $currentVersion = (Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json).version
    }
}
$versionLink = New-Object System.Windows.Forms.LinkLabel
$versionLink.Text = if ($currentVersion) { 'v' + $currentVersion } else { '개발 버전' }
$versionLink.Location = New-Object System.Drawing.Point(632, 725)
$versionLink.Size = New-Object System.Drawing.Size(104, 22)
$versionLink.TextAlign = 'MiddleRight'
$versionLink.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
$versionLink.LinkColor = $accent
$versionLink.ActiveLinkColor = [System.Drawing.ColorTranslator]::FromHtml('#7443A8')
$versionLink.VisitedLinkColor = $accent
$versionLink.LinkBehavior = 'HoverUnderline'
$versionLink.Cursor = [System.Windows.Forms.Cursors]::Hand
$releasePage = 'https://github.com/HansCheek/chat-macro/releases'
$versionLink.Add_LinkClicked({
    try { Start-Process -FilePath $releasePage -ErrorAction Stop }
    catch { $status.Text = '● 릴리스 페이지를 열지 못했습니다' }
})
$form.Controls.Add($versionLink)
$versionToolTip = New-Object System.Windows.Forms.ToolTip
$versionToolTip.SetToolTip($versionLink, '클릭하면 깃허브 릴리즈페이지로 연결됩니다.')

$script:running = $false
$script:paused = $false
$script:remainingMs = 0
$script:phase = 0
$script:client = 0
$script:clientIndex = 0
$script:activeClients = @()
$script:activeHotkeys = @{}
$script:textElements = @('1')
$script:textIndex = 0
$script:count = 0
$script:period = 60000
$script:due = 0
$script:stopAt = 0
$script:pausedAt = 0
$script:shutdownAfterStop = $false
$script:shutdownPending = $false
$script:shutdownDue = 0
$watch = [System.Diagnostics.Stopwatch]::StartNew()
function Stop-Macro {
    $script:running = $false
    $script:paused = $false
    $script:stopAt = 0
    $script:pausedAt = 0
    $autoSettings.Enabled = $true
    $clientSettings.Enabled = $true
    $guide.Enabled = $true
    $autoStatus.Text = '자동 중지 시간은 다음 시작부터 새로 계산합니다.'
    $pause.Text = 'Ⅱ  일시정지'
    $pause.Enabled = $false
    $script:phase = 0
    $script:client = 0
    $interval.Enabled = $true
    $presets.Enabled = $true
    $start.Enabled = $true
    $stop.Enabled = $false
    $status.Text = "● 중지됨 · $($script:count)회 완료"
    $form.Text = '간단 반복 매크로 — 중지됨'
}
function Start-Macro {
    if ($script:running) { return }
    if ($script:shutdownPending) {
        $status.Text = '● PC 종료 예약을 취소한 뒤 시작하세요'
        return
    }
    $selected = @()
    $selectedHotkeys = @{}
    $usedHotkeys = @()
    for ($slot = 0; $slot -lt 3; $slot++) {
        if (-not $clientChecks[$slot].Checked) { continue }
        $name = [string]$clientHotkeys[$slot].SelectedItem
        if (-not $hotkeyOptions.Contains($name)) {
            $status.Text = "● $($slot + 1)클 전환 단축키를 선택하세요"
            return
        }
        if ($usedHotkeys -contains $name) {
            $status.Text = '● 선택한 클라의 전환 단축키가 중복됩니다'
            return
        }
        $selected += ($slot + 1)
        $selectedHotkeys[$slot + 1] = $hotkeyOptions[$name]
        $usedHotkeys += $name
    }
    if ($selected.Count -eq 0) {
        $status.Text = '● 입력할 클라를 하나 이상 체크하세요'
        return
    }
    if ([string]::IsNullOrWhiteSpace($inputContent.Text)) {
        $status.Text = '● 입력할 내용을 한 줄로 적어 주세요'
        return
    }
    foreach ($character in $inputContent.Text.ToCharArray()) {
        if ([char]::IsControl($character)) {
            $status.Text = '● 줄바꿈 없이 한 줄로 입력해 주세요'
            return
        }
    }
    $script:textElements = @()
    $elements = [Globalization.StringInfo]::GetTextElementEnumerator($inputContent.Text)
    while ($elements.MoveNext()) { $script:textElements += $elements.GetTextElement() }
    $script:textIndex = 0
    $script:activeClients = $selected
    $script:activeHotkeys = $selectedHotkeys
    $script:clientIndex = 0
    $script:period = [double]$interval.Value * 1000
    $script:due = $watch.ElapsedMilliseconds + $script:period
    $script:phase = 0
    $script:client = 0
    $script:count = 0
    $script:running = $true
    $script:paused = $false
    $script:pausedAt = 0
    $script:stopAt = 0
    $script:shutdownAfterStop = $autoStop.Checked -and $shutdownOption.Checked
    if ($autoStop.Checked) {
        $script:stopAt = $watch.ElapsedMilliseconds + ([double]$stopMinutes.Value * 60000)
    }
    $autoSettings.Enabled = $false
    $clientSettings.Enabled = $false
    $guide.Enabled = $false
    Update-AutoStopStatus
    $pause.Text = 'Ⅱ  일시정지'
    $pause.Enabled = $true
    $interval.Enabled = $false
    $presets.Enabled = $false
    $start.Enabled = $false
    $stop.Enabled = $true
    $status.Text = "● 실행 중 · $($script:activeClients -join ', ')클 선택"
    $form.WindowState = 'Minimized'
}
function Toggle-Pause {
    if (-not $script:running) { return }
    if ($script:paused) {
        if ($script:stopAt -gt 0) {
            $script:stopAt += $watch.ElapsedMilliseconds - $script:pausedAt
        }
        $script:pausedAt = 0
        $form.WindowState = 'Minimized'
        if ($script:client -gt 0) {
            try { Select-Client } catch {
                Stop-Macro
                [void][System.Windows.Forms.MessageBox]::Show('클라이언트 전환 입력에 실패해 중지했습니다.', '간단 반복 매크로')
                return
            }
            $script:remainingMs = [Math]::Max(1000, $script:remainingMs)
        }
        $script:due = $watch.ElapsedMilliseconds + $script:remainingMs
        $script:paused = $false
        Update-AutoStopStatus
        $pause.Text = 'Ⅱ  일시정지'
        $status.Text = '● 실행 중 · 이어서 입력합니다'
        $form.WindowState = 'Minimized'
    } else {
        if (Test-AutoStop) { return }
        $script:remainingMs = [Math]::Max(0, $script:due - $watch.ElapsedMilliseconds)
        $script:paused = $true
        $script:pausedAt = $watch.ElapsedMilliseconds
        Update-AutoStopStatus
        $pause.Text = '▶  계속'
        $seconds = [Math]::Ceiling($script:remainingMs / 1000)
        $status.Text = "Ⅱ 일시정지 · $seconds 초 남음 · $($script:client)클 · $($script:count)회 완료"
        $form.Text = '간단 반복 매크로 — 일시정지'
    }
}
$start.Add_Click({ Start-Macro })
$pause.Add_Click({ Toggle-Pause })
$stop.Add_Click({ Stop-Macro })
$form.add_StartRequested({ Start-Macro })
$form.add_StopRequested({ Stop-Macro })
$cancelShutdown.Add_Click({ Cancel-ComputerShutdown })

function Invoke-ShutdownCommand([string]$Arguments) {
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
    try { return $process.ExitCode } finally { $process.Dispose() }
}
function Update-ShutdownStatus {
    if (-not $script:shutdownPending) { return }
    $seconds = [Math]::Max(0, [Math]::Ceiling(($script:shutdownDue - $watch.ElapsedMilliseconds) / 1000))
    $left = [TimeSpan]::FromSeconds($seconds)
    $autoStatus.Text = 'PC 종료까지 {0:00}:{1:00} · 창을 닫아도 예약 유지 · 취소 버튼으로 취소' -f [Math]::Floor($left.TotalMinutes), $left.Seconds
}
function Schedule-ComputerShutdown {
    try {
        $code = Invoke-ShutdownCommand '/s /t 300'
        if ($code -ne 0) { throw "Windows 종료 예약 실패 (코드 $code)" }
        $script:shutdownPending = $true
        $script:shutdownDue = $watch.ElapsedMilliseconds + 300000
        $cancelShutdown.Enabled = $true
        $start.Enabled = $false
        $status.Text = '● 매크로 중지 · PC 종료 5분 대기'
        $form.Text = '채팅 매크로 — PC 종료 예약됨'
        Update-ShutdownStatus
    } catch {
        $autoStatus.Text = "PC 종료를 예약하지 못했습니다: $($_.Exception.Message)"
    }
}
function Cancel-ComputerShutdown {
    if (-not $script:shutdownPending) { return }
    try {
        $code = Invoke-ShutdownCommand '/a'
        if ($code -ne 0 -and $code -ne 1116) { throw "Windows 종료 취소 실패 (코드 $code)" }
        $script:shutdownPending = $false
        $script:shutdownDue = 0
        $cancelShutdown.Enabled = $false
        $start.Enabled = $true
        $status.Text = '● PC 종료 예약을 취소했습니다'
        $autoStatus.Text = '컴퓨터를 종료하지 않습니다. 매크로는 중지 상태입니다.'
        $form.Text = '클라이언트 반복 매크로'
    } catch {
        $autoStatus.Text = "PC 종료 취소에 실패했습니다: $($_.Exception.Message)"
    }
}

function Update-AutoStopStatus {
    if ($script:stopAt -le 0) {
        $autoStatus.Text = '자동 중지 꺼짐 · 직접 중지할 때까지 반복합니다.'
        return
    }
    $timeNow = $watch.ElapsedMilliseconds
    if ($script:paused) { $timeNow = $script:pausedAt }
    $left = [TimeSpan]::FromSeconds([Math]::Max(0, [Math]::Ceiling(($script:stopAt - $timeNow) / 1000)))
    $autoStatus.Text = '자동 중지까지 {0:00}:{1:00}:{2:00}' -f [Math]::Floor($left.TotalHours), $left.Minutes, $left.Seconds
    if ($script:paused) { $autoStatus.Text += ' (일시정지)' }
    if ($script:shutdownAfterStop) { $autoStatus.Text += ' · 중지 후 5분 뒤 PC 종료' }
}
function Test-AutoStop {
    if ($script:running -and -not $script:paused -and $script:stopAt -gt 0 -and $watch.ElapsedMilliseconds -ge $script:stopAt) {
        Stop-Macro
        $status.Text = "● 자동 중지됨 · $($script:count)회 완료"
        $autoStatus.Text = '설정한 사용 시간이 끝나 자동으로 중지했습니다.'
        $form.Text = '간단 반복 매크로 — 자동 중지됨'
        if ($script:shutdownAfterStop) { Schedule-ComputerShutdown }
        return $true
    }
    return $false
}

function Select-Client {
    $key = $script:activeHotkeys[$script:client]
    if ($null -eq $key) { throw 'Invalid client number' }
    if ($key.Modifier -eq 0) { [MacroKeyboard]::Press($key.Scan) }
    else { [MacroKeyboard]::Chord($key.Modifier, $key.Scan) }
}
function Switch-Client {
    Select-Client
    $script:phase = 1
    $script:due = $watch.ElapsedMilliseconds + 1000
    $status.Text = "● $($script:client)클 입력 중 · $($script:count)회 완료"
    $form.Text = "매크로 실행 중 · $($script:client)클"
}

function Invoke-MacroStep {
    if (Test-AutoStop) { return }
    switch ($script:phase) {
        0 {
            $script:clientIndex = 0
            $script:client = $script:activeClients[$script:clientIndex]
            Switch-Client
        }
        1 {
            [MacroKeyboard]::Press(0x1C)
            $script:textIndex = 0
            $script:phase = 2
            $script:due = $watch.ElapsedMilliseconds + 150
        }
        2 {
            [MacroKeyboard]::TypeElement($script:textElements[$script:textIndex])
            $script:textIndex++
            if ($script:textIndex -ge $script:textElements.Count) {
                $script:phase = 3
                $script:due = $watch.ElapsedMilliseconds + 150
            } else {
                $script:due = $watch.ElapsedMilliseconds + 30
            }
        }
        3 {
            [MacroKeyboard]::Press(0x1C)
            if ($script:clientIndex -lt ($script:activeClients.Count - 1)) {
                $script:phase = 4
                $script:due = $watch.ElapsedMilliseconds + 1000
            } else {
                $script:count++
                $script:client = 0
                $script:phase = 0
                $script:due = $watch.ElapsedMilliseconds + $script:period
            }
        }
        4 {
            $script:clientIndex++
            $script:client = $script:activeClients[$script:clientIndex]
            Switch-Client
        }
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 40
$timer.Add_Tick({
    if ($script:shutdownPending) { Update-ShutdownStatus; return }
    if (-not $script:running -or $script:paused) { return }
    if (Test-AutoStop) { return }
    Update-AutoStopStatus
    $now = $watch.ElapsedMilliseconds
    if ($script:phase -eq 0) {
        $remaining = [Math]::Max(0, [Math]::Ceiling(($script:due - $now) / 1000))
        $status.Text = "● 실행 중 · 다음 입력까지 $remaining 초 · $($script:count)회 완료"
        $form.Text = "매크로 실행 중 · $remaining 초 남음"
    }
    if ($now -lt $script:due) { return }
    # Do not type into the macro's own settings window.
    if ($form.ContainsFocus) {
        Stop-Macro
        $status.Text = '● 중지됨 · 입력할 창에서 다시 시작하세요'
        return
    }
    try {
        Invoke-MacroStep
    } catch {
        Stop-Macro
        [System.Windows.Forms.MessageBox]::Show("Windows에서 입력 전송을 거부해 중지했습니다.`n대상 프로그램이 관리자 권한이면 실행.bat도 관리자 권한으로 실행해 보세요.", '간단 반복 매크로')
    }
})
$form.Add_Shown({
    $script:startKey = [MacroForm]::RegisterHotKey($form.Handle, 1, 0x4002, 0xDB)
    $script:stopKey = [MacroForm]::RegisterHotKey($form.Handle, 2, 0x4002, 0xDD)
    if (-not $script:startKey -or -not $script:stopKey) {
        $help.Text = "다른 프로그램이 단축키를 사용 중입니다.`n시작·중지 버튼을 이용하세요."
    }
    $timer.Start()
})
$form.Add_FormClosed({
    $versionToolTip.Dispose()
    $script:running = $false
    $timer.Stop()
    $timer.Dispose()
    [void][MacroForm]::UnregisterHotKey($form.Handle, 1)
    [void][MacroForm]::UnregisterHotKey($form.Handle, 2)
})
[System.Windows.Forms.Application]::Run($form)
$form.Dispose()
