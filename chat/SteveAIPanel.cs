// Thin CAD plugin: a dockable palette that hosts SteveAIChat.exe (separate process). Command STEVEAIPANEL.
// Compiled per CAD: ZWCAD (default) or AutoCAD with /define:ACAD.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
#if ACAD
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.Windows;
using CadApp = Autodesk.AutoCAD.ApplicationServices.Application;
#else
using ZwSoft.ZwCAD.Runtime;
using ZwSoft.ZwCAD.Windows;
using CadApp = ZwSoft.ZwCAD.ApplicationServices.Application;
#endif

[assembly: CommandClass(typeof(SteveAI.PanelCommands))]
[assembly: AssemblyTitle("Steve AI Panel")]
[assembly: AssemblyCompany("Steve Tran")]

namespace SteveAI
{
    public class PanelCommands
    {
        static PaletteSet ps; static Panel host; static Process chat;

        [CommandMethod("STEVEAIPANEL", CommandFlags.Session)]
        public static void Show()
        {
            try
            {
                if (ps == null)
                {
                    host = new Panel(); host.BackColor = Color.FromArgb(13, 20, 33); host.Dock = DockStyle.Fill;
                    ps = new PaletteSet("Steve AI", new Guid("6A0E5B5C-0E0B-4B5B-9C53-57E7A1C0D2A1"));
                    ps.Add("Chat", host);
                    ps.MinimumSize = new Size(320, 300);
                    ps.DockEnabled = DockSides.Left | DockSides.Right;
                    ps.Visible = true; ps.Dock = DockSides.Right; ps.Size = new Size(460, 700);
                }
                else ps.Visible = !ps.Visible;
                ps.KeepFocus = true;
                if (ps.Visible && (chat == null || chat.HasExited))
                {
                    string exe = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "SteveAIChat.exe");
                    var si = new ProcessStartInfo(exe, "-Parent " + host.Handle.ToInt64());
                    si.UseShellExecute = false;
                    chat = Process.Start(si);
                }
            }
            catch (System.Exception ex)
            {
                CadApp.DocumentManager.MdiActiveDocument.Editor.WriteMessage("\nSteve AI: " + ex.Message);
            }
        }
    }
}
