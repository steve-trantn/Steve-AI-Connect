// Steve AI Chat: a WebView2 window with a real terminal (ConPTY) that runs Claude Code / Codex / Gemini.
// Stand-alone window, or embedded in a CAD palette with -Parent <hwnd> (see SteveAIPanel.cs). It runs in its own
// process, so a problem here cannot take the CAD down. C# 5 (the compiler that ships with Windows).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32.SafeHandles;

[assembly: System.Reflection.AssemblyTitle("Steve AI Chat")]
[assembly: System.Reflection.AssemblyCompany("Steve Tran")]
[assembly: System.Reflection.AssemblyVersion("@VERSION@.0")]

static class Program
{
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [STAThread]
    static void Main(string[] args)
    {
        SetProcessDPIAware();
        Application.EnableVisualStyles();
        try { Application.Run(new ChatForm(args)); }
        catch (Exception ex)
        {
            MessageBox.Show("Không mở được khung chat:\n\n" + ex.Message + "\n\nHỗ trợ: Steve Tran | 0987 779 228", "Steve AI", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}

class ChatForm : Form
{
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    readonly WebView2 web = new WebView2();
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly string appDir = AppDomain.CurrentDomain.BaseDirectory;
    readonly string ps1;
    readonly IntPtr parent = IntPtr.Zero;
    readonly string startClient = "", startSkill = "", snap = "";
    string docName = "";
    Pty pty; int cols = 100, rows = 30, run = 0; bool closing;

    public ChatForm(string[] a)
    {
        for (int i = 0; i + 1 < a.Length; i += 2)
        {
            string k = a[i].ToLowerInvariant(), v = a[i + 1];
            if (k == "-parent") parent = new IntPtr(long.Parse(v));
            else if (k == "-client") startClient = v;
            else if (k == "-skill") startSkill = v;
            else if (k == "-snapshot") snap = v;      // tests: save a picture of the page and close
        }
        ps1 = Path.GetFullPath(Path.Combine(appDir, @"..\..\app\SteveAI.ps1"));
        Text = "Steve AI"; BackColor = Color.FromArgb(13, 20, 33); AutoScaleMode = AutoScaleMode.None;
        StartPosition = FormStartPosition.Manual;
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        int w = Math.Max(480, wa.Width * 34 / 100);
        Bounds = new Rectangle(wa.Right - w, wa.Top, w, wa.Height);   // right side of the screen, beside the drawing
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        if (parent != IntPtr.Zero) { FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; }
        web.Dock = DockStyle.Fill; web.DefaultBackgroundColor = BackColor; Controls.Add(web);
        Load += delegate { Init(); };
        FormClosing += delegate { closing = true; Stop(); };
    }
    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams p = base.CreateParams;
            if (parent != IntPtr.Zero) { p.Style = (p.Style & ~unchecked((int)0x80000000)) | 0x40000000 | 0x02000000; p.Parent = parent; }   // WS_CHILD
            return p;
        }
    }

    async void Init()
    {
        try
        {
            if (parent != IntPtr.Zero)
            {
                SetParent(Handle, parent);
                var t = new System.Windows.Forms.Timer(); t.Interval = 150;   // follow the palette's size; end with it
                t.Tick += delegate
                {
                    RECT r;
                    if (!IsWindow(parent)) { t.Stop(); Close(); return; }
                    if (GetClientRect(parent, out r) && (Left != 0 || Top != 0 || Width != r.R || Height != r.B) && r.R > 0 && r.B > 0) Bounds = new Rectangle(0, 0, r.R, r.B);
                };
                t.Start();
            }
            string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"SteveCADConnect\chat-data");
            var env = await CoreWebView2Environment.CreateAsync(null, data);
            await web.EnsureCoreWebView2Async(env);
            var s = web.CoreWebView2.Settings;
            s.AreDevToolsEnabled = false; s.IsStatusBarEnabled = false; s.AreDefaultContextMenusEnabled = true; s.AreHostObjectsAllowed = false;
            web.CoreWebView2.SetVirtualHostNameToFolderMapping("steveai.local", Path.Combine(appDir, "web"), CoreWebView2HostResourceAccessKind.Deny);
            // the page never leaves our own folder
            web.CoreWebView2.NavigationStarting += (o, e) => { if (!e.Uri.StartsWith("https://steveai.local/")) e.Cancel = true; };
            web.CoreWebView2.NewWindowRequested += (o, e) => { e.Handled = true; OpenLink(e.Uri); };
            web.CoreWebView2.WebMessageReceived += OnMessage;
            if (parent != IntPtr.Zero)
            {
                // the CAD palette sends "client|skill" lines when a command is run while the panel is open
                Console.SetIn(new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false)));
                var rd = new Thread(delegate()
                {
                    try
                    {
                        string line;
                        while ((line = Console.In.ReadLine()) != null)
                        {
                            if (line.StartsWith("doc|")) { string nm = line.Substring(4); BeginInvoke((Action)delegate { docName = nm; Post(new { t = "doc", name = nm }); }); continue; }
                            string[] q = line.Split('|');
                            if (q.Length == 2) BeginInvoke((Action)delegate { Post(new { t = "ask", client = Safe(q[0]), skill = Safe(q[1]) }); });
                        }
                    }
                    catch { }
                });
                rd.IsBackground = true; rd.Start();
            }
            web.CoreWebView2.Navigate("https://steveai.local/index.html");
        }
        catch (WebView2RuntimeNotFoundException)
        {
            MessageBox.Show(this, "Máy chưa có Microsoft Edge WebView2 Runtime.\nTải miễn phí tại: https://go.microsoft.com/fwlink/p/?LinkId=2124703", "Steve AI"); Close();
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Steve AI"); Close(); }
    }
    static void OpenLink(string u)
    {
        Uri x;
        if (Uri.TryCreate(u, UriKind.Absolute, out x) && (x.Scheme == "https" || x.Scheme == "http")) try { Process.Start(x.AbsoluteUri); } catch { }
    }
    void Post(object o) { if (!closing && web.CoreWebView2 != null) web.CoreWebView2.PostWebMessageAsJson(json.Serialize(o)); }

    void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (!e.Source.StartsWith("https://steveai.local/")) return;
        var m = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson);
        switch ((string)m["t"])
        {
            case "ready":
                cols = Convert.ToInt32(m["cols"]); rows = Convert.ToInt32(m["rows"]);
                RunPs("-Info", (r, err) =>
                {
                    if (err != null) { Post(new { t = "error", text = err }); return; }
                    r["t"] = "info"; r["panel"] = parent != IntPtr.Zero; r["doc"] = docName; r["client"] = startClient; r["skill"] = startSkill; Post(r);
                });
                break;
            case "start": Begin((string)m["client"], (string)m["skill"], m.ContainsKey("resume") && true.Equals(m["resume"])); break;
            case "undo": if (parent != IntPtr.Zero) try { Console.Out.WriteLine("undo"); Console.Out.Flush(); } catch { } break;
            case "files":
                var paths = new List<string>();
                foreach (object o in e.AdditionalObjects) { var f = o as CoreWebView2File; if (f != null) paths.Add(f.Path); }
                Post(new { t = "files", paths = paths });
                break;
            case "stop": Stop(); break;
            case "in": { var p = pty; if (p != null) p.Write((string)m["d"]); } break;
            case "size":
                cols = Convert.ToInt32(m["cols"]); rows = Convert.ToInt32(m["rows"]);
                { var p = pty; if (p != null) p.Resize(cols, rows); }
                break;
            case "link": OpenLink((string)m["u"]); break;
            case "snap": SaveSnap(); break;
        }
    }
    async void SaveSnap()
    {
        if (snap == "") return;
        await System.Threading.Tasks.Task.Delay(9000);
        using (var f = File.Create(snap)) await web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, f);
        Close();
    }

    static string Safe(string s) { var b = new StringBuilder(); foreach (char c in s ?? "") if (char.IsLetterOrDigit(c) || c == '-' || c == '_') b.Append(c); return b.ToString(); }

    // runs SteveAI.ps1 (same launcher as the terminal version: registration gate, assistant lookup) and reads its JSON
    void RunPs(string args, Action<Dictionary<string, object>, string> done)
    {
        var th = new Thread(delegate()
        {
            Dictionary<string, object> res = null; string err = null;
            try
            {
                var si = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                    "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + ps1 + "\" " + args);
                si.UseShellExecute = false; si.CreateNoWindow = true; si.RedirectStandardOutput = true; si.StandardOutputEncoding = Encoding.UTF8;
                using (var p = Process.Start(si))
                {
                    string o = p.StandardOutput.ReadToEnd(); p.WaitForExit();
                    int i = o.IndexOf('{');
                    if (i >= 0) res = json.Deserialize<Dictionary<string, object>>(o.Substring(i));
                    if (res != null && res.ContainsKey("error")) { err = (string)res["error"]; res = null; }
                    else if (res == null) err = "Chưa mở được trợ lý AI. Xem thông báo vừa hiện, hoặc mở Steve AI Connect để kết nối.";
                }
            }
            catch (Exception ex) { err = ex.Message; }
            try { if (!closing) BeginInvoke((Action)delegate { done(res, err); }); } catch { }
        });
        th.IsBackground = true; th.Start();
    }

    void Begin(string client, string skill, bool resume)
    {
        Stop();
        int id = ++run;
        string a = "-Prepare";
        if (Safe(client) != "") a += " -Client " + Safe(client);
        if (Safe(skill) != "") a += " -Skill " + Safe(skill);
        if (resume) a += " -Resume";
        RunPs(a, (r, err) =>
        {
            if (id != run || closing) return;   // another start was asked meanwhile
            if (err != null) { Post(new { t = "error", text = err }); return; }
            try
            {
                string bat = (string)r["bat"];
                var p = new Pty(Path.Combine(Environment.SystemDirectory, "cmd.exe"), "/d /c \"\"" + bat + "\"\"", (string)r["dir"], cols, rows);
                pty = p;
                p.Start(bytes => { try { BeginInvoke((Action)delegate { if (pty == p) Post(new { t = "out", d = Convert.ToBase64String(bytes) }); }); } catch { } },
                        () => { try { BeginInvoke((Action)delegate { if (pty == p) { Stop(); Post(new { t = "exit" }); } }); } catch { } });
                Post(new { t = "started", client = r["client"], label = r["label"] });
            }
            catch (Exception ex) { Post(new { t = "error", text = ex.Message }); }
        });
    }
    void Stop() { run++; var p = pty; pty = null; if (p != null) p.Dispose(); }
}

// Windows pseudo console (Windows 10 1809+)
class Pty : IDisposable
{
    [StructLayout(LayoutKind.Sequential)] struct COORD { public short X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string r1, desk, title; public int x, y, cx, cy, ccx, ccy, fill, flags; public short show, r2; public IntPtr r3, hin, hout, herr; }
    [StructLayout(LayoutKind.Sequential)] struct STARTUPINFOEX { public STARTUPINFO si; public IntPtr attrs; }
    [StructLayout(LayoutKind.Sequential)] struct PROCINFO { public IntPtr hp, ht; public int pid, tid; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out SafeFileHandle r, out SafeFileHandle w, IntPtr sa, int size);
    [DllImport("kernel32.dll")] static extern int CreatePseudoConsole(COORD size, SafeFileHandle hin, SafeFileHandle hout, uint flags, out IntPtr pc);
    [DllImport("kernel32.dll")] static extern int ResizePseudoConsole(IntPtr pc, COORD size);
    [DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr pc);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr l, int n, int f, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr l, uint f, IntPtr attr, IntPtr val, IntPtr size, IntPtr prev, IntPtr ret);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr l);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFOEX si, out PROCINFO pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool DuplicateHandle(IntPtr sp, IntPtr h, IntPtr tp, out IntPtr o, uint acc, bool inh, uint opt);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();

    IntPtr pc = IntPtr.Zero, proc; readonly FileStream wr, rd; readonly object gate = new object(); bool dead;

    public Pty(string exe, string args, string dir, int cols, int rows)
    {
        SafeFileHandle inR, inW, outR, outW;
        if (!CreatePipe(out inR, out inW, IntPtr.Zero, 0) || !CreatePipe(out outR, out outW, IntPtr.Zero, 0)) throw new Exception("Không tạo được pipe.");
        int hr;
        try { hr = CreatePseudoConsole(Size(cols, rows), inR, outW, 0, out pc); }
        catch (EntryPointNotFoundException) { throw new Exception("Khung chat cần Windows 10 bản 1809 trở lên."); }
        inR.Dispose(); outW.Dispose();
        if (hr != 0) throw new Exception("Không tạo được terminal (0x" + hr.ToString("X8") + ").");
        wr = new FileStream(inW, FileAccess.Write); rd = new FileStream(outR, FileAccess.Read);
        IntPtr n = IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref n);
        IntPtr list = Marshal.AllocHGlobal(n);
        try
        {
            if (!InitializeProcThreadAttributeList(list, 1, 0, ref n)) throw new Exception("AttributeList");
            if (!UpdateProcThreadAttribute(list, 0, (IntPtr)0x00020016, pc, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) throw new Exception("UpdateAttribute");
            var si = new STARTUPINFOEX(); si.si.cb = Marshal.SizeOf(typeof(STARTUPINFOEX)); si.attrs = list;
            si.si.flags = 0x100;   // STARTF_USESTDHANDLES with null handles: never inherit redirected handles of the parent
            PROCINFO pi;
            if (!CreateProcessW(exe, new StringBuilder("\"" + exe + "\" " + args), IntPtr.Zero, IntPtr.Zero, false, 0x00080000, IntPtr.Zero, dir, ref si, out pi))
                throw new Exception("Không chạy được trợ lý (lỗi " + Marshal.GetLastWin32Error() + ").");
            CloseHandle(pi.ht); proc = pi.hp;
            DeleteProcThreadAttributeList(list);
        }
        catch { ClosePseudoConsole(pc); throw; }
        finally { Marshal.FreeHGlobal(list); }
    }
    static COORD Size(int c, int r) { var s = new COORD(); s.X = (short)Math.Max(20, Math.Min(500, c)); s.Y = (short)Math.Max(5, Math.Min(300, r)); return s; }

    public void Start(Action<byte[]> output, Action exited)
    {
        var t = new Thread(delegate()
        {
            var b = new byte[16384];
            try { int k; while ((k = rd.Read(b, 0, b.Length)) > 0) { var c = new byte[k]; Buffer.BlockCopy(b, 0, c, 0, k); output(c); } } catch { }
        });
        t.IsBackground = true; t.Start();
        IntPtr h; DuplicateHandle(GetCurrentProcess(), proc, GetCurrentProcess(), out h, 0, false, 2);
        var w = new Thread(delegate() { WaitForSingleObject(h, 0xFFFFFFFF); CloseHandle(h); Thread.Sleep(300); exited(); });
        w.IsBackground = true; w.Start();
    }
    public void Write(string s)
    {
        try { var b = Encoding.UTF8.GetBytes(s); lock (gate) { if (dead) return; wr.Write(b, 0, b.Length); wr.Flush(); } } catch { }
    }
    public void Resize(int c, int r) { lock (gate) { if (!dead) ResizePseudoConsole(pc, Size(c, r)); } }
    public void Dispose()
    {
        lock (gate) { if (dead) return; dead = true; }
        // closing the console ends everything attached to it; it blocks until output is drained, so not on the UI thread
        var t = new Thread(delegate() { ClosePseudoConsole(pc); try { wr.Dispose(); } catch { } try { rd.Dispose(); } catch { } CloseHandle(proc); });
        t.Start();
    }
}
