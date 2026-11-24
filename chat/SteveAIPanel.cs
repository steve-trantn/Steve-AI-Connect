// Thin CAD plugin: a dockable palette that hosts SteveAIChat.exe (separate process).
//   (steveai-show client skill)   LISP function used by the AI commands; T when the panel is shown, nil = use the window instead
//   STEVEAIPANEL                  shows / hides the panel
// SteveAI.lsp loads this DLL by itself. Compiled per CAD: ZWCAD (default) or AutoCAD with /define:ACAD.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Forms;
#if ACAD
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.Windows;
using CadApp = Autodesk.AutoCAD.ApplicationServices.Application;
#else
using ZwSoft.ZwCAD.DatabaseServices;
using ZwSoft.ZwCAD.Runtime;
using ZwSoft.ZwCAD.Windows;
using CadApp = ZwSoft.ZwCAD.ApplicationServices.Application;
#endif

[assembly: CommandClass(typeof(SteveAI.PanelCommands))]
[assembly: AssemblyTitle("Steve AI Panel")]
[assembly: AssemblyCompany("Steve Tran")]
[assembly: AssemblyVersion("@VERSION@.0")]

namespace SteveAI
{
    public class PanelCommands
    {
        static PaletteSet ps; static Panel host; static Process chat;

        [LispFunction("steveai-show")]
        public static object LispShow(ResultBuffer args)
        {
            try
            {
                if (!CanRun()) return null;
                string client = "", skill = ""; int n = 0;
                if (args != null) foreach (TypedValue v in args.AsArray())
                {
                    string s = v.Value as string;
                    if (s == null) continue;
                    if (n++ == 0) client = Safe(s); else skill = Safe(s);
                }
                Open(client, skill);
                return true;
            }
            catch (System.Exception ex) { Say(ex.Message); return null; }
        }

        [CommandMethod("STEVEAIPANEL", CommandFlags.Session)]
        public static void Toggle()
        {
            try { if (ps != null && ps.Visible) ps.Visible = false; else Open("", ""); }
            catch (System.Exception ex) { Say(ex.Message); }
        }

        [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
        static Size lastFit; static int startWidth;   // startWidth: wanted once, after the first docking (AutoCAD docks at the minimum width)
        // AutoCAD 2027 does not stretch a docked palette to its dock bar by itself
        static void Fit()
        {
            try
            {
                if (ps == null || !ps.Visible || ps.Dock == DockSides.None) return;
                IntPtr pal = GetParent(GetParent(host.Handle)), bar = GetParent(pal);
                var cls = new System.Text.StringBuilder(64); GetClassName(bar, cls, 64);
                if (!cls.ToString().StartsWith("AfxControlBar")) return;
                RECT p, b; GetWindowRect(pal, out p); GetWindowRect(bar, out b);
                var want = new Size(b.R - b.L, b.B - p.T - 3);
                bool wider = startWidth > want.Width + 20;
                if (wider) want.Width = startWidth;
                startWidth = 0;
                if ((b.B - p.B < 24 && !wider) || want.Height < 200 || want == lastFit) return;   // fits, or already tried this size
                lastFit = want; ps.Size = want;
            }
            catch { }
        }

        static string Safe(string s) { return Regex.Replace(s ?? "", @"[^\w\-]", ""); }
        static void Say(string m) { try { CadApp.DocumentManager.MdiActiveDocument.Editor.WriteMessage("\nSteve AI: " + m); } catch { } }

        // same rules as Test-ChatWindow in app\core.ps1
        static bool CanRun()
        {
            string set = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"SteveCADConnect\settings.json");
            if (File.Exists(set) && Regex.IsMatch(File.ReadAllText(set), "\"UseTerminal\"\\s*:\\s*true")) return false;
            if (!File.Exists(Exe)) return false;
            const string k = @"Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
            foreach (string p in new[] { @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\" + k, @"HKEY_CURRENT_USER\Software\" + k })
            {
                string v = Microsoft.Win32.Registry.GetValue(p, "pv", null) as string;
                if (!string.IsNullOrEmpty(v) && v != "0.0.0.0") return true;
            }
            return false;
        }
        static string Exe { get { return Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "SteveAIChat.exe"); } }

        // tells the chat which drawing is in front (bytes: the writer of .NET 4 has no UTF-8 setting)
        static void SendDoc()
        {
            try
            {
                if (chat == null || chat.HasExited) return;
                var d = CadApp.DocumentManager.MdiActiveDocument;
                string n = d == null ? "" : Regex.Replace(Path.GetFileName(d.Name), @"[\r\n]", "");
                byte[] b = new System.Text.UTF8Encoding(false).GetBytes("doc|" + n + "\n");
                chat.StandardInput.BaseStream.Write(b, 0, b.Length); chat.StandardInput.BaseStream.Flush();
            }
            catch { }
        }
        // one step back in the drawing in front; never while a command is running
        static void Undo()
        {
            try
            {
                var d = CadApp.DocumentManager.MdiActiveDocument;
                if (d == null) return;
                if (!string.IsNullOrEmpty(d.CommandInProgress)) { Say("đang dở một lệnh, bấm Esc rồi hoàn tác lại."); return; }
                d.SendStringToExecute("_.U ", true, false, true);
            }
            catch (System.Exception ex) { Say(ex.Message); }
        }

        static void Open(string client, string skill)
        {
            if (ps == null)
            {
                host = new Panel(); host.BackColor = Color.FromArgb(13, 20, 33); host.Dock = DockStyle.Fill;
                ps = new PaletteSet("Steve AI", new Guid("6A0E5B5C-0E0B-4B5B-9C53-57E7A1C0D2A1"));
                ps.Style = PaletteSetStyles.ShowCloseButton | PaletteSetStyles.ShowAutoHideButton | PaletteSetStyles.ShowPropertiesMenu;
                ps.Add("Chat", host);
                ps.MinimumSize = new Size(280, 240);
                ps.DockEnabled = DockSides.Left | DockSides.Right;
                CadApp.DocumentManager.DocumentActivated += delegate { SendDoc(); };
                float k; using (Graphics gr = host.CreateGraphics()) k = gr.DpiX / 96f;   // 380 px at 100 %
                int w = (int)(380 * k); startWidth = w;
                ps.Size = new Size(w, (int)(600 * k));   // before docking: a size set afterwards stays, and leaves half of the dock empty
                ps.Visible = true; ps.Dock = DockSides.Right;
                var fit = new System.Windows.Forms.Timer(); fit.Interval = 700; fit.Tick += delegate { Fit(); }; fit.Start();
            }
            else if (!ps.Visible) ps.Visible = true;
            ps.KeepFocus = true;
            if (chat == null || chat.HasExited)
            {
                var si = new ProcessStartInfo(Exe, "-Parent " + host.Handle.ToInt64() + (client != "" ? " -Client " + client : "") + (skill != "" ? " -Skill " + skill : ""));
                si.UseShellExecute = false; si.RedirectStandardInput = true; si.RedirectStandardOutput = true;
                chat = Process.Start(si);
                chat.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
                {
                    if (e.Data == "undo") try { host.BeginInvoke((Action)Undo); } catch { }   // back on the CAD's own thread
                };
                chat.BeginOutputReadLine();
                SendDoc();
            }
            else if (client != "" || skill != "") { chat.StandardInput.WriteLine(client + "|" + skill); chat.StandardInput.Flush(); }
        }
    }
}
