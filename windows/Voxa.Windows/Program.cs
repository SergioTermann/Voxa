using System;
using System.Threading;
using System.Windows.Forms;

namespace Voxa;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var instance = new Mutex(true, @"Local\Voxa.Windows", out bool first);
        if (!first)
        {
            MessageBox.Show("Voxa 已在运行，请查看系统托盘。", "Voxa");
            return;
        }
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
    }
}
