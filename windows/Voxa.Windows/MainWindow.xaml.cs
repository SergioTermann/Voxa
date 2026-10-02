using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Speech.Recognition;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace Voxa;

public partial class MainWindow : Window
{
    private readonly Settings settings = Settings.Load();
    private readonly DictationController controller;
    private readonly RightControlTrigger trigger;
    private readonly PreviewWindow preview;
    private readonly Forms.NotifyIcon tray;
    private HwndSource? source;
    private bool initialized, quitting, toggleRegistered, cancelRegistered;
    private const int ToggleId = 1, CancelId = 2;
    private RecognizerInfo? SelectedRecognizer => (Languages.SelectedItem as RecognizerChoice)?.Info;
    private sealed record RecognizerChoice(RecognizerInfo Info)
    {
        public override string ToString() => Info.Culture.NativeName;
    }

    public MainWindow()
    {
        InitializeComponent();
        controller = new DictationController(Dispatcher);
        trigger = new RightControlTrigger(Dispatcher);
        preview = new PreviewWindow();
        var icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("打开 Voxa", null, (_, _) => ShowSettings());
        menu.Items.Add("取消听写", null, (_, _) => controller.Cancel());
        menu.Items.Add("复制上次结果", null, (_, _) => CopyResult());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Quit());
        tray = new Forms.NotifyIcon { Icon = icon, Text = "Voxa · 双击右 Ctrl", Visible = true, ContextMenuStrip = menu };
        tray.DoubleClick += (_, _) => ShowSettings();
        controller.Changed += UpdateState;
        trigger.Triggered += Toggle;
        AutoFinish.IsChecked = settings.AutoFinish;
        initialized = true;
        Loaded += (_, _) => LoadRecognizers();
        SourceInitialized += (_, _) => ConfigureShortcuts();
        UpdateState();
    }

    private void ConfigureShortcuts()
    {
        var handle = new WindowInteropHelper(this).Handle;
        source = HwndSource.FromHwnd(handle);
        source.AddHook(WindowMessage);
        const uint modifiers = 0x0001 | 0x0002 | 0x4000;
        toggleRegistered = Native.RegisterHotKey(handle, ToggleId, modifiers, 0x20);
        cancelRegistered = Native.RegisterHotKey(handle, CancelId, modifiers, 0x1B);
        trigger.Start();
        TriggerStatus.Text = trigger.Available ? "●  双击右 Ctrl 已启用" : "右 Ctrl 监听不可用，请使用备用快捷键";
        BackupStatus.Text = $"备用：Ctrl + Alt + Space{(toggleRegistered ? "" : "（被占用）")}  ·  取消：Ctrl + Alt + Esc{(cancelRegistered ? "" : "（被占用，请用托盘取消）")}";
        int dark = 1, rounded = 2;
        Native.DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int));
        Native.DwmSetWindowAttribute(handle, 33, ref rounded, sizeof(int));
    }

    private IntPtr WindowMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == Native.WmHotkey)
        {
            if (wParam.ToInt32() == ToggleId) Toggle();
            else if (wParam.ToInt32() == CancelId) controller.Cancel();
            handled = true;
        }
        return IntPtr.Zero;
    }

    private void Toggle() => controller.Toggle(SelectedRecognizer, AutoFinish.IsChecked == true);
    private void LoadRecognizers()
    {
        try
        {
            var choices = SpeechRecognitionEngine.InstalledRecognizers().Select(r => new RecognizerChoice(r)).ToList();
            Languages.ItemsSource = choices;
            Languages.SelectedItem = choices.FirstOrDefault(c => c.Info.Id == settings.RecognizerId) ?? choices.FirstOrDefault();
            if (choices.Count == 0) Status.Text = "未找到兼容的本机听写引擎，请安装语音组件后重启。详见 Windows README。";
        }
        catch (Exception e) { Status.Text = "无法读取本机语音引擎：" + e.Message; }
    }

    private void SaveSettings()
    {
        if (!initialized) return;
        settings.AutoFinish = AutoFinish.IsChecked == true;
        settings.RecognizerId = SelectedRecognizer?.Id ?? "";
        if (!settings.Save()) Status.Text = "设置暂时无法保存，本次运行仍可使用。";
    }
    private void LanguageChanged(object sender, SelectionChangedEventArgs e) => SaveSettings();
    private void AutoFinishChanged(object sender, RoutedEventArgs e) => SaveSettings();

    private void UpdateState()
    {
        bool idle = controller.Phase == Phase.Idle;
        StateBadge.Text = idle ? "●  准备就绪" : controller.Phase == Phase.Listening ? "●  正在聆听" : "●  正在完成";
        Status.Text = controller.Message;
        Result.Text = idle ? controller.LastResult : controller.Preview;
        EmptyResult.Visibility = Result.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        Languages.IsEnabled = AutoFinish.IsEnabled = ClearButton.IsEnabled = idle;
        CopyButton.IsEnabled = idle && controller.LastResult.Length > 0;
        CancelButton.Visibility = idle ? Visibility.Collapsed : Visibility.Visible;
        tray.Text = idle ? "Voxa · 双击右 Ctrl" : "Voxa · 正在听写";
        if (idle)
        {
            bool wasVisible = preview.IsVisible;
            preview.Hide();
            if (wasVisible && !IsVisible) tray.ShowBalloonTip(3500, "Voxa", controller.Message, Forms.ToolTipIcon.Info);
        }
        else preview.UpdatePreview(controller);
    }


    internal void SaveUiPreviews(string directory)
    {
        System.IO.Directory.CreateDirectory(directory);
        initialized = false;
        Languages.ItemsSource = new[] { "中文（简体，中国）" };
        Languages.SelectedIndex = 0;
        AutoFinish.IsChecked = true;
        Result.Text = "";
        EmptyResult.Visibility = Visibility.Visible;
        Width = 1040; Height = 760;
        UpdateLayout();
        SaveImage(this, System.IO.Path.Combine(directory, "settings.png"));
        Result.Text = "让想法自然流动，让每一句话都能轻松到达光标。\nVoxa 帮你专注表达，无需打断思路。";
        EmptyResult.Visibility = Visibility.Collapsed;
        CopyButton.IsEnabled = true;
        Width = 920; Height = 680;
        UpdateLayout();
        SaveImage(this, System.IO.Path.Combine(directory, "settings-compact.png"));
        preview.ShowUiSample();
        preview.UpdateLayout();
        SaveImage(preview, System.IO.Path.Combine(directory, "listening.png"));
        System.IO.File.WriteAllText(System.IO.Path.Combine(directory, "diagnostics.txt"),
            $"RightCtrlHook={trigger.Available}; BackupHotkey={toggleRegistered}; CancelHotkey={cancelRegistered}");
        if (!trigger.Available) throw new InvalidOperationException("Right Ctrl hook could not be installed.");
        Quit();
    }
    private static void SaveImage(Window window, string path)
    {
        var content = (FrameworkElement)window.Content;
        content.UpdateLayout();
        var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)content.ActualWidth,
            (int)content.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
        bitmap.Render(content);
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
        using var stream = System.IO.File.Create(path);
        encoder.Save(stream);
    }

    private void CopyResult()
    {
        if (controller.LastResult.Length == 0) return;
        try { Clipboard.SetText(controller.LastResult); Status.Text = "已复制，随时粘贴到需要的地方。"; }
        catch (Exception e) { Status.Text = "剪贴板暂时不可用：" + e.Message; }
    }
    private void CopyClick(object sender, RoutedEventArgs e) => CopyResult();
    private void ClearClick(object sender, RoutedEventArgs e) => controller.Clear();
    private void CancelClick(object sender, RoutedEventArgs e) => controller.Cancel();
    private void QuitClick(object sender, RoutedEventArgs e) => Quit();
    private void MicrophoneClick(object sender, RoutedEventArgs e) => OpenSettings("ms-settings:privacy-microphone");
    private void LanguageSettingsClick(object sender, RoutedEventArgs e) => OpenSettings("ms-settings:regionlanguage");
    private void OpenSettings(string uri)
    {
        try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); }
        catch (Exception e) { Status.Text = "无法打开系统设置：" + e.Message; }
    }
    private void ShowSettings() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void Quit() { quitting = true; Close(); }
    protected override void OnClosing(CancelEventArgs e)
    {
        if (!quitting) { e.Cancel = true; Hide(); }
        base.OnClosing(e);
    }
    protected override void OnClosed(EventArgs e)
    {
        trigger.Dispose();
        var handle = new WindowInteropHelper(this).Handle;
        if (toggleRegistered) Native.UnregisterHotKey(handle, ToggleId);
        if (cancelRegistered) Native.UnregisterHotKey(handle, CancelId);
        source?.RemoveHook(WindowMessage);
        controller.Dispose();
        preview.Close();
        tray.Visible = false;
        tray.ContextMenuStrip?.Dispose();
        tray.Icon?.Dispose();
        tray.Dispose();
        base.OnClosed(e);
    }
}
