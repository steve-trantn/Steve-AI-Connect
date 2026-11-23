// Steve AI Connect - Setup.exe
// One file to send to other people. It carries the whole tool (payload.zip, embedded resource),
// unpacks it into %LOCALAPPDATA%\SteveCADConnect\tool (per user, no admin rights) and opens the tool,
// which starts on step 1 "Kết nối". Built by build\build-exe.ps1 with the C# compiler that ships with
// Windows (.NET Framework 4.x), so no extra software is needed to build or to run it.
//
// Command line (IT): Setup.exe -Connect [-Cad ...] [-Client ...]   -> unpack, then run the tool's command line and wait.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
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
        Form splash = null;
        try
        {
            if (args.Length == 0) { splash = MakeSplash(); splash.Show(); Application.DoEvents(); }
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
            var gui = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"" + script + "\" -FirstRun");
            gui.UseShellExecute = false; gui.CreateNoWindow = true; gui.WorkingDirectory = tool;
            var g = Process.Start(gui);
            // keep the "đang cài" window up until the tool's window shows (PowerShell takes a few seconds)
            DateTime end = DateTime.Now.AddSeconds(40);
            while (DateTime.Now < end && !g.HasExited)
            {
                g.Refresh();
                if (g.MainWindowHandle != IntPtr.Zero) break;
                Application.DoEvents(); Thread.Sleep(150);
            }
            if (g.HasExited && g.ExitCode != 0) throw new Exception("Công cụ dừng với mã lỗi " + g.ExitCode + ".");
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
                e.ExtractToFile(dest, true);
            }
        }
    }

    static string JoinArgs(string[] args)
    {
        var parts = new string[args.Length];
        for (int i = 0; i < args.Length; i++)
            parts[i] = (args[i].IndexOfAny(new[] { ' ', '\t', '"' }) >= 0) ? "\"" + args[i].Replace("\"", "\\\"") + "\"" : args[i];
        return string.Join(" ", parts);
    }

    static Form MakeSplash()
    {
        var f = new Form();
        f.FormBorderStyle = FormBorderStyle.None; f.StartPosition = FormStartPosition.CenterScreen;
        f.ShowInTaskbar = true; f.Text = "Steve AI Connect"; f.TopMost = true;
        f.BackColor = Color.FromArgb(15, 23, 42); f.AutoScaleMode = AutoScaleMode.Dpi;
        f.ClientSize = new Size(440, 120);
        try { f.Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }
        var t1 = new Label(); t1.Text = "Steve AI Connect"; t1.ForeColor = Color.White; t1.Font = new Font("Segoe UI Semibold", 14f);
        t1.SetBounds(24, 18, 400, 32); t1.BackColor = Color.Transparent;
        var t2 = new Label(); t2.Text = "Đang cài đặt… cửa sổ chính sẽ tự mở sau vài giây."; t2.ForeColor = Color.FromArgb(255, 196, 0);
        t2.Font = new Font("Segoe UI", 10f); t2.SetBounds(26, 56, 400, 24); t2.BackColor = Color.Transparent;
        var bar = new ProgressBar(); bar.Style = ProgressBarStyle.Marquee; bar.MarqueeAnimationSpeed = 30; bar.SetBounds(26, 90, 388, 8);
        f.Controls.Add(t1); f.Controls.Add(t2); f.Controls.Add(bar);
        return f;
    }
}
