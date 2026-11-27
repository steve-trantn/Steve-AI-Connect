// Steve AI Connect - Setup.exe
// One file to send to other people. It carries the whole tool (payload.zip, embedded resource),
// unpacks it into %LOCALAPPDATA%\SteveCADConnect\tool (per user, no admin rights) and installs everything without
// the tool's window (v1.10: app\SteveCADConnect.ps1 -Setup). Registration and the AI assistant are set up inside the CAD.
// Built by build\build-exe.ps1 with the C# compiler that ships with Windows (.NET Framework 4.x), so no extra software is needed to build or to run it.
//
// Command line (IT): Setup.exe -Connect [-Cad ...] [-Client ...]   -> unpack, then run the tool's command line and wait.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Steve AI Connect")]
[assembly: AssemblyDescription("Cài đặt Steve AI Connect: nối ZWCAD, AutoCAD, ADSCivil với Claude, ChatGPT, Gemini")]
[assembly: AssemblyCompany("Steve Tran")]
[assembly: AssemblyProduct("Steve AI Connect")]
[assembly: AssemblyCopyright("© 2026 Steve Tran · 0987 779 228")]
[assembly: AssemblyVersion("@VERSION@.0")]
[assembly: AssemblyFileVersion("@VERSION@.0")]

static class Program
{
    const string Contact = "Steve Tran | 0987 779 228";

    [STAThread]
    static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        string tool = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteveCADConnect", "tool");
        Form splash = null; Label status = null;
        try
        {
            if (args.Length == 0) { splash = MakeSplash(out status); splash.Show(); Application.DoEvents(); }
            Unpack(tool);
            string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            string script = Path.Combine(tool, @"app\SteveCADConnect.ps1");
            if (args.Length > 0)
            {
                // command line: pass the switches through, show the output, return its exit code
                var psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" " + JoinArgs(args));
                psi.UseShellExecute = false;
                var p = Process.Start(psi); p.WaitForExit(); return p.ExitCode;
            }
            // v1.10: install without the tool's window. Progress shows here; registration and the assistant are chosen
            // later inside the CAD panel. The last line of the script is "@@DONE {json}".
            var si = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"" + script + "\" -Setup");
            si.UseShellExecute = false; si.CreateNoWindow = true; si.WorkingDirectory = tool;
            si.RedirectStandardOutput = true; si.RedirectStandardInput = true; si.StandardOutputEncoding = new UTF8Encoding(false);
            var g = Process.Start(si);
            g.StandardInput.Close();
            string done = null; var lines = new List<string>();
            var reader = new Thread(delegate()
            {
                string l;
                while ((l = g.StandardOutput.ReadLine()) != null)
                {
                    lock (lines) { if (l.StartsWith("@@DONE ")) done = l.Substring(7); else if (l.Trim().Length > 0) lines.Add(l.Trim()); }
                }
            });
            reader.IsBackground = true; reader.Start();
            DateTime end = DateTime.Now.AddMinutes(20);
            while (!g.HasExited && DateTime.Now < end)
            {
                lock (lines) if (lines.Count > 0) status.Text = lines[lines.Count - 1];
                Application.DoEvents(); Thread.Sleep(120);
            }
            if (!g.HasExited) { try { g.Kill(); } catch { } throw new Exception("Cài đặt quá lâu (hơn 20 phút). Kiểm tra mạng Internet rồi chạy lại."); }
            reader.Join(3000);
            splash.Hide();
            List<string> errs;
            lock (lines) errs = lines.FindAll(x => x.IndexOf("Lỗi", StringComparison.Ordinal) >= 0 || x.StartsWith("LỖI"));
            ShowDone(done, g.ExitCode, errs, script, ps);
            return 0;
        }
        catch (Exception ex)
        {
            if (splash != null) splash.Hide();
            MessageBox.Show("Không cài được Steve AI Connect:\n\n" + ex.Message + "\n\nCần hỗ trợ: " + Contact,
                "Steve AI Connect", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally { if (splash != null) splash.Close(); }
    }

    static void Unpack(string tool)
    {
        Directory.CreateDirectory(tool);
        // fresh copy of the program folders; the user's data (settings, API key, workspace) lives elsewhere
        foreach (string d in new[] { "app", "CAD", "server", "templates" })
        {
            string p = Path.Combine(tool, d);
            try { if (Directory.Exists(p)) Directory.Delete(p, true); } catch { /* in use: files are overwritten below */ }
        }
        string bin = Path.Combine(tool, "chat");
        if (Directory.Exists(bin)) foreach (string f in Directory.GetFiles(bin, "*.old-*", SearchOption.AllDirectories)) try { File.Delete(f); } catch { }
        string root = Path.GetFullPath(tool).TrimEnd('\\') + "\\";
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry e in zip.Entries)
            {
                string dest = Path.GetFullPath(Path.Combine(root, e.FullName.Replace('/', '\\')));
                if (!dest.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;   // never write outside the tool folder
                if (e.Name.Length == 0) { Directory.CreateDirectory(dest); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                try { e.ExtractToFile(dest, true); }
                catch (IOException)
                {
                    // the chat window is open: a loaded exe / dll cannot be overwritten, but it can be renamed
                    File.Move(dest, dest + ".old-" + Guid.NewGuid().ToString("N"));
                    e.ExtractToFile(dest, true);
                }
            }
        }
    }

    // the end: what was found, a button per CAD to start it, and where to go next (inside the CAD)
    static void ShowDone(string json, int code, List<string> errs, string script, string ps)
    {
        var cads = new List<Dictionary<string, object>>(); string ver = ""; int nAi = 0;
        try
        {
            var r = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json ?? "{}");
            if (r.ContainsKey("version")) ver = (string)r["version"];
            var a = r.ContainsKey("cads") ? r["cads"] as System.Collections.ArrayList : null;
            if (a != null) foreach (object o in a) { var d = o as Dictionary<string, object>; if (d != null) cads.Add(d); }
            var k = r.ContainsKey("clients") ? r["clients"] as System.Collections.ArrayList : null;
            if (k != null) nAi = k.Count;
        }
        catch { }
        var f = new Form();
        f.Text = "Steve AI Connect " + ver; f.StartPosition = FormStartPosition.CenterScreen; f.FormBorderStyle = FormBorderStyle.FixedDialog;
        f.MaximizeBox = false; f.MinimizeBox = false; f.AutoScaleMode = AutoScaleMode.Dpi; f.BackColor = Color.White; f.TopMost = true;
        try { f.Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }
        int y = 18;
        bool ok = code == 0 && json != null && errs.Count == 0;
        var h = new Label(); h.Font = new Font("Segoe UI Semibold", 13f); h.AutoSize = false; h.SetBounds(22, y, 460, 30);
        h.Text = ok ? "✓  Đã cài xong" : "Đã cài, có lỗi cần xem";
        h.ForeColor = ok ? Color.FromArgb(22, 128, 61) : Color.FromArgb(180, 83, 9); f.Controls.Add(h); y += 38;
        string msg;
        if (cads.Count == 0) msg = "Máy chưa có ZWCAD, AutoCAD hoặc ADSCivil. Cài một phần mềm CAD rồi chạy lại file cài này.";
        else msg = "Mở CAD, sang tab Steve AI trên ribbon rồi bấm Steve AI (hoặc gõ lệnh AI).\n" +
                   (nAi > 0 ? "Lần đầu: đăng ký (miễn phí) ngay trong khung chat." : "Lần đầu: đăng ký (miễn phí) và chọn trợ lý AI cần cài, ngay trong khung chat.") +
                   "\nCAD đang mở thì lưu bản vẽ, đóng hẳn rồi mở lại.";
        if (errs.Count > 0) msg += "\n\n⚠ " + string.Join("\n⚠ ", errs.GetRange(0, Math.Min(3, errs.Count)).ToArray()) + "\nCần hỗ trợ: " + Contact;
        var m = new Label(); m.Font = new Font("Segoe UI", 10f); m.AutoSize = false; m.Text = msg;
        int mh = TextRenderer.MeasureText(msg, m.Font, new Size(460, 0), TextFormatFlags.WordBreak).Height + 8;
        m.SetBounds(22, y, 460, mh); f.Controls.Add(m); y += mh + 10;
        foreach (var c in cads)
        {
            string cad = (string)c["cad"], label = (string)c["label"];
            var b = new Button(); b.Text = "Mở " + label; b.Font = new Font("Segoe UI", 10f); b.SetBounds(22, y, 460, 36);
            b.FlatStyle = FlatStyle.Flat; b.BackColor = Color.FromArgb(0, 104, 236); b.ForeColor = Color.White; b.FlatAppearance.BorderSize = 0;
            b.Click += delegate
            {
                try
                {
                    var si = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -Launch " + cad + " -CadVersion \"" + label.Replace("\"", "") + "\"");
                    si.UseShellExecute = false; si.CreateNoWindow = true; si.RedirectStandardInput = true;
                    Process.Start(si).StandardInput.Close();
                }
                catch (Exception ex) { MessageBox.Show(ex.Message, "Steve AI Connect"); }
                f.Close();
            };
            f.Controls.Add(b); y += 42;
        }
        var close = new Button(); close.Text = "Đóng"; close.Font = new Font("Segoe UI", 10f); close.SetBounds(382, y + 4, 100, 32);
        close.Click += delegate { f.Close(); }; f.Controls.Add(close); f.CancelButton = close;
        f.ClientSize = new Size(504, y + 50);
        Application.Run(f);
    }

    static string JoinArgs(string[] args)
    {
        var parts = new string[args.Length];
        for (int i = 0; i < args.Length; i++)
            parts[i] = (args[i].IndexOfAny(new[] { ' ', '\t', '"' }) >= 0) ? "\"" + args[i].Replace("\"", "\\\"") + "\"" : args[i];
        return string.Join(" ", parts);
    }

    static Form MakeSplash(out Label status)
    {
        var f = new Form();
        f.FormBorderStyle = FormBorderStyle.None; f.StartPosition = FormStartPosition.CenterScreen;
        f.ShowInTaskbar = true; f.Text = "Steve AI Connect"; f.TopMost = true;
        f.BackColor = Color.FromArgb(15, 23, 42); f.AutoScaleMode = AutoScaleMode.Dpi;
        f.ClientSize = new Size(440, 120);
        try { f.Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }
        var t1 = new Label(); t1.Text = "Steve AI Connect"; t1.ForeColor = Color.White; t1.Font = new Font("Segoe UI Semibold", 14f);
        t1.SetBounds(24, 18, 400, 32); t1.BackColor = Color.Transparent;
        var t2 = new Label(); t2.Text = "Đang cài đặt…"; t2.ForeColor = Color.FromArgb(255, 196, 0);
        t2.Font = new Font("Segoe UI", 10f); t2.SetBounds(26, 56, 400, 24); t2.BackColor = Color.Transparent;
        var bar = new ProgressBar(); bar.Style = ProgressBarStyle.Marquee; bar.MarqueeAnimationSpeed = 30; bar.SetBounds(26, 90, 388, 8);
        f.Controls.Add(t1); f.Controls.Add(t2); f.Controls.Add(bar);
        status = t2;
        return f;
    }
}
