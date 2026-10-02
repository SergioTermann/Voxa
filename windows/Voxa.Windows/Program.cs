using System;
using System.Threading;
using System.Windows;

namespace Voxa;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        using var instance = new Mutex(true, @"Local\Voxa.Windows", out bool first);
        if (!first)
        {
            MessageBox.Show("Voxa 已在运行，请查看系统托盘。", "Voxa");
            return;
        }
        var application = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        var window = new MainWindow();
        if (args.Length == 2 && args[0] == "--ui-check")
        {
            window.Loaded += (_, _) => window.Dispatcher.BeginInvoke(
                System.Windows.Threading.DispatcherPriority.ApplicationIdle,
                (Action)(() => window.SaveUiPreviews(args[1])));
        }
        application.Run(window);
    }
}
