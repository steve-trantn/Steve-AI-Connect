// Thin CAD plugin: a dockable palette that hosts SteveAIChat.exe (separate process).
//   (steveai-show client skill)   LISP function used by the AI commands; T when the panel is shown, nil = use the window instead
//   STEVEAIPANEL                  shows / hides the panel
// SteveAI.lsp loads this DLL by itself. Compiled per CAD: ZWCAD (default) or AutoCAD with /define:ACAD.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
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
                ps.Visible = true; ps.Dock = DockSides.Right; ps.Size = new Size(420, 700);
            }
            else if (!ps.Visible) ps.Visible = true;
            ps.KeepFocus = true;
            if (chat == null || chat.HasExited)
            {
                var si = new ProcessStartInfo(Exe, "-Parent " + host.Handle.ToInt64() + (client != "" ? " -Client " + client : "") + (skill != "" ? " -Skill " + skill : ""));
                si.UseShellExecute = false; si.RedirectStandardInput = true;
                chat = Process.Start(si);
            }
            else if (client != "" || skill != "") { chat.StandardInput.WriteLine(client + "|" + skill); chat.StandardInput.Flush(); }
        }
    }
}
