// AutoCAD / Civil 3D only: the "Steve AI" ribbon tab, built in code. A partial CUIX loaded by script is not added to the
// current workspace there, so its tab stays invisible. Loaded at start-up by the SteveAI.bundle (see Write-AcadBundle).
// Buttons come from %LOCALAPPDATA%\SteveCADConnect\ribbon.txt, written by app\cadmenu.ps1:
//   panel <TAB> large|small <TAB> text <TAB> tooltip <TAB> command <TAB> icon file (without 16.png / 32.png)
#if ACAD
using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using Autodesk.AutoCAD.Runtime;
using Autodesk.Windows;
using CadApp = Autodesk.AutoCAD.ApplicationServices.Application;

[assembly: ExtensionApplication(typeof(SteveAI.RibbonApp))]

namespace SteveAI
{
    public class RibbonApp : IExtensionApplication
    {
        const string TabId = "STEVEAI_TAB";
        static string Home { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteveCADConnect"); } }
        static DateTime next = DateTime.MinValue;

        public void Initialize()
        {
            try
            {
                CadApp.Idle += OnIdle;   // the ribbon appears after start-up, and Civil 3D / a workspace switch rebuilds it: keep looking
            }
            catch { }
        }
        public void Terminate() { }

        static void OnIdle(object sender, EventArgs e)
        {
            try
            {
                if (DateTime.UtcNow < next) return;
                next = DateTime.UtcNow.AddSeconds(2);
                if (ComponentManager.Ribbon != null && ComponentManager.Ribbon.FindTab(TabId) == null) Build();
            }
            catch { next = DateTime.UtcNow.AddSeconds(10); }   // still starting: try again later
        }

        static BitmapImage Img(string file)
        {
            try
            {
                if (!File.Exists(file)) return null;
                var b = new BitmapImage(); b.BeginInit(); b.CacheOption = BitmapCacheOption.OnLoad; b.UriSource = new Uri(file); b.EndInit(); b.Freeze();
                return b;
            }
            catch { return null; }
        }

        static void Build()
        {
            RibbonControl ribbon = ComponentManager.Ribbon;
            if (ribbon.FindTab(TabId) != null) return;
            string def = Path.Combine(Home, "ribbon.txt");
            if (!File.Exists(def)) return;
            var tab = new RibbonTab(); tab.Title = "Steve AI"; tab.Id = TabId;
            var panels = new Dictionary<string, RibbonPanelSource>();
            var column = new Dictionary<string, RibbonRowPanel>(); var count = new Dictionary<string, int>();
            foreach (string line in File.ReadAllLines(def, System.Text.Encoding.UTF8))
            {
                string[] f = line.Split('\t');
                if (f.Length != 6) continue;
                RibbonPanelSource src;
                if (!panels.TryGetValue(f[0], out src))
                {
                    src = new RibbonPanelSource(); src.Title = f[0]; panels[f[0]] = src; count[f[0]] = 0;
                    var pn = new RibbonPanel(); pn.Source = src; tab.Panels.Add(pn);
                }
                bool large = f[1] == "large";
                var b = new RibbonButton();
                b.Text = f[2]; b.ToolTip = f[3]; b.ShowText = true; b.ShowImage = true;
                b.Image = Img(Path.Combine(Home, "icons", f[5] + "16.png")); b.LargeImage = Img(Path.Combine(Home, "icons", f[5] + "32.png"));
                b.Size = large ? RibbonItemSize.Large : RibbonItemSize.Standard;
                b.Orientation = large ? System.Windows.Controls.Orientation.Vertical : System.Windows.Controls.Orientation.Horizontal;
                b.CommandParameter = f[4]; b.CommandHandler = new Run();
                if (large) { src.Items.Add(b); continue; }
                if (count[f[0]] % 3 == 0) { var rp = new RibbonRowPanel(); column[f[0]] = rp; src.Items.Add(rp); }
                else column[f[0]].Items.Add(new RibbonRowBreak());
                column[f[0]].Items.Add(b);
                count[f[0]]++;
            }
            ribbon.Tabs.Add(tab);
        }

        class Run : ICommand
        {
            public bool CanExecute(object p) { return true; }
            public event EventHandler CanExecuteChanged { add { } remove { } }
            public void Execute(object p)
            {
                try
                {
                    var b = p as RibbonButton; var d = CadApp.DocumentManager.MdiActiveDocument;
                    if (b == null || d == null) return;
                    d.SendStringToExecute("\x03\x03" + (string)b.CommandParameter + " ", true, false, true);
                }
                catch { }
            }
        }
    }
}
#endif
