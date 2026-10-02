using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Voxa;

public partial class PreviewWindow : Window
{
    private readonly DispatcherTimer animation = new() { Interval = TimeSpan.FromMilliseconds(60) };
    private DictationController? controller;
    private int frame;
    public PreviewWindow()
    {
        InitializeComponent();
        for (int i = 0; i < 15; i++) Wave.Children.Add(new Rectangle { Width = 3, Height = 3,
            RadiusX = 1.5, RadiusY = 1.5, Margin = new Thickness(2, 0, 2, 0),
            Fill = new SolidColorBrush(Color.FromRgb(170, 152, 255)), VerticalAlignment = VerticalAlignment.Center });
        animation.Tick += (_, _) =>
        {
            frame++;
            double level = controller?.Phase == Phase.Listening ? (controller.AudioLevel / 100.0) : 0;
            for (int i = 0; i < Wave.Children.Count; i++)
                ((Rectangle)Wave.Children[i]).Height = 3 + level * (5 + 12 * Math.Abs(Math.Sin(frame * 0.3 + i * 0.7)));
        };
        IsVisibleChanged += (_, _) => { if (IsVisible) animation.Start(); else animation.Stop(); };
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            Native.MakeNonActivating(handle);
            HwndSource.FromHwnd(handle).AddHook((IntPtr h, int m, IntPtr w, IntPtr l, ref bool handled) =>
            {
                if (m == 0x21) { handled = true; return (IntPtr)3; }
                return IntPtr.Zero;
            });
        };
        Closed += (_, _) => animation.Stop();
    }
    internal void ShowUiSample()
    {
        Heading.Text = "正在聆听";
        Transcript.Text = "让想法自然流动，让每一句话都能轻松到达光标。";
        Show();
        animation.Stop();
        for (int i = 0; i < Wave.Children.Count; i++) ((Rectangle)Wave.Children[i]).Height = 3 + 16 * Math.Abs(Math.Sin(i * 0.7));
    }
    internal void UpdatePreview(DictationController current)
    {
        controller = current;
        Heading.Text = current.Phase == Phase.Finishing ? "正在整理文字" : "正在聆听";
        Transcript.Text = current.Preview.Length == 0 ? "说出你的想法……" : current.Preview;
        if (IsVisible) return;
        var area = Forms.Screen.FromHandle(Native.GetForegroundWindow()).WorkingArea;
        var transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
        // Display once without activation, then use this monitor's DPI for physical positioning.
        Show();
        transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice ?? transform;
        var topLeft = transform.Transform(new Point(area.Left + (area.Width - ActualWidth / transform.M11) / 2,
            area.Bottom - ActualHeight / transform.M22 - 30));
        Left = topLeft.X; Top = topLeft.Y;
    }
}
