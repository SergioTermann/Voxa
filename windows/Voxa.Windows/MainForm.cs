using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Speech.Recognition;
using System.Windows.Forms;

namespace Voxa;

internal sealed class MainForm : Form
{
    private readonly Settings settings = Settings.Load();
    private readonly ComboBox languages = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly CheckBox autoFinish = new() { Text = "停顿后自动完成并输入", AutoSize = true };
    private readonly Label status = new() { AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(0, 8, 0, 8) };
    private readonly Label hotkeys = new() { AutoSize = true, Dock = DockStyle.Fill };
    private readonly TextBox result = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill };
    private readonly Button copy = new() { Text = "复制文字", AutoSize = true };
    private readonly Button clear = new() { Text = "清除", AutoSize = true };
    private readonly Button cancel = new() { Text = "取消听写", AutoSize = true };
    private readonly NotifyIcon tray;
    private readonly PreviewForm preview = new();
    private readonly DictationController controller;
    private bool quitting, toggleRegistered, cancelRegistered;
    private const int ToggleId = 1, CancelId = 2;
    private IReadOnlyList<RecognizerInfo> recognizers = Array.Empty<RecognizerInfo>();
    private RecognizerInfo? SelectedRecognizer => languages.SelectedItem is RecognizerChoice choice ? choice.Info : null;

    private sealed record RecognizerChoice(RecognizerInfo Info)
    {
        public override string ToString() => $"{Info.Culture.DisplayName} ({Info.Culture.Name}) — {Info.Description}";
    }

    internal MainForm()
    {
        Text = "Voxa for Windows";
        Font = new Font("Microsoft YaHei UI", 10);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(690, 610);
        MinimumSize = new Size(620, 570);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application;

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 10 };
        for (int i = 0; i < 10; i++) layout.RowStyles.Add(new RowStyle(i == 8 ? SizeType.Percent : SizeType.AutoSize, i == 8 ? 100 : 0));
        layout.Controls.Add(new Label { Text = "Voxa  语音输入", Font = new Font(Font.FontFamily, 22, FontStyle.Bold), AutoSize = true, Margin = new Padding(0, 0, 0, 12) }, 0, 0);
        layout.Controls.Add(new Label { Text = "点击其他应用的输入框，再按快捷键开始说话。\n关闭此窗口后，Voxa 会继续在系统托盘运行。", AutoSize = true, Margin = new Padding(0, 0, 0, 14) }, 0, 1);
        hotkeys.Text = "开始 / 完成：Ctrl + Alt + Space     取消：Ctrl + Alt + Esc";
        layout.Controls.Add(hotkeys, 0, 2);
        layout.Controls.Add(new Label { Text = "本机识别语言（仅显示已安装的兼容引擎）", AutoSize = true, Margin = new Padding(0, 14, 0, 6) }, 0, 3);
        layout.Controls.Add(languages, 0, 4);
        autoFinish.Checked = settings.AutoFinish;
        autoFinish.Margin = new Padding(0, 12, 0, 8);
        layout.Controls.Add(autoFinish, 0, 5);
        var links = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = true };
        AddLink(links, "麦克风权限", "ms-settings:privacy-microphone");
        AddLink(links, "语音设置", "ms-settings:speech");
        AddLink(links, "语言设置", "ms-settings:regionlanguage");
        layout.Controls.Add(links, 0, 6);
        layout.Controls.Add(status, 0, 7);
        layout.Controls.Add(result, 0, 8);
        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(0, 10, 0, 0) };
        var exit = new Button { Text = "退出 Voxa", AutoSize = true };
        actions.Controls.AddRange(new Control[] { copy, clear, cancel, exit });
        layout.Controls.Add(actions, 0, 9);
        Controls.Add(layout);

        controller = new DictationController(this);
        controller.Changed += UpdateState;
        var menu = new ContextMenuStrip();
        menu.Items.Add("打开 Voxa", null, (_, _) => ShowSettings());
        menu.Items.Add("取消听写", null, (_, _) => controller.Cancel());
        menu.Items.Add("复制上次结果", null, (_, _) => CopyResult());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Quit());
        tray = new NotifyIcon { Icon = Icon, Text = "Voxa · Ctrl + Alt + Space", Visible = true, ContextMenuStrip = menu };
        tray.DoubleClick += (_, _) => ShowSettings();
        copy.Click += (_, _) => CopyResult();
        clear.Click += (_, _) => controller.Clear();
        cancel.Click += (_, _) => controller.Cancel();
        exit.Click += (_, _) => Quit();
        autoFinish.CheckedChanged += (_, _) => SaveSettings();
        languages.SelectedIndexChanged += (_, _) => SaveSettings();
        Shown += (_, _) => LoadRecognizers();
        UpdateState();
    }

    private void AddLink(Control parent, string title, string uri)
    {
        var link = new LinkLabel { Text = title, AutoSize = true, Margin = new Padding(0, 0, 18, 6) };
        link.LinkClicked += (_, _) =>
        {
            try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); }
            catch (Exception e) { status.Text = "无法打开系统设置：" + e.Message; }
        };
        parent.Controls.Add(link);
    }

    private void LoadRecognizers()
    {
        try
        {
            recognizers = SpeechRecognitionEngine.InstalledRecognizers().ToList();
            languages.Items.AddRange(recognizers.Select(r => (object)new RecognizerChoice(r)).ToArray());
            int selected = recognizers.ToList().FindIndex(r => r.Id == settings.RecognizerId);
            if (recognizers.Count > 0) languages.SelectedIndex = selected < 0 ? 0 : selected;
            else status.Text = "未找到兼容的 SAPI 听写引擎。安装 Windows 语音组件后重启 Voxa；现代语音访问语言包不一定兼容。详见 Windows README。";
        }
        catch (Exception e) { status.Text = "无法读取本机语音引擎：" + e.Message; }
    }

    private void SaveSettings()
    {
        settings.AutoFinish = autoFinish.Checked;
        settings.RecognizerId = SelectedRecognizer?.Id ?? "";
        if (!settings.Save()) status.Text = "设置暂时无法保存，本次运行仍可使用。";
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        const uint modifiers = 0x0001 | 0x0002 | 0x4000; // Alt + Control + MOD_NOREPEAT
        toggleRegistered = Native.RegisterHotKey(Handle, ToggleId, modifiers, 0x20);
        cancelRegistered = Native.RegisterHotKey(Handle, CancelId, modifiers, 0x1B);
        hotkeys.Text = $"Ctrl + Alt + Space：{(toggleRegistered ? "开始 / 完成" : "注册失败（已被占用）")}\nCtrl + Alt + Esc：{(cancelRegistered ? "取消" : "注册失败；请用托盘菜单取消")}";
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        if (toggleRegistered) Native.UnregisterHotKey(Handle, ToggleId);
        if (cancelRegistered) Native.UnregisterHotKey(Handle, CancelId);
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WmHotkey)
        {
            if ((int)m.WParam == ToggleId) controller.Toggle(SelectedRecognizer, autoFinish.Checked);
            else if ((int)m.WParam == CancelId) controller.Cancel();
            return;
        }
        base.WndProc(ref m);
    }

    private void UpdateState()
    {
        bool idle = controller.Phase == Phase.Idle;
        status.Text = controller.Message;
        result.Text = idle ? controller.LastResult : controller.Preview;
        languages.Enabled = autoFinish.Enabled = clear.Enabled = idle;
        copy.Enabled = idle && controller.LastResult.Length > 0;
        cancel.Enabled = !idle;
        tray.Text = idle ? "Voxa · Ctrl + Alt + Space" : "Voxa · 正在听写";
        if (idle)
        {
            preview.Hide();
            if (!Visible && IsHandleCreated)
                tray.ShowBalloonTip(3500, "Voxa", controller.Message, ToolTipIcon.Info);
        }
        else preview.UpdatePreview(controller.Phase, controller.Preview);
    }

    private void CopyResult()
    {
        if (controller.LastResult.Length == 0) return;
        try { Clipboard.SetText(controller.LastResult); status.Text = "已复制。"; }
        catch (Exception e) { status.Text = "剪贴板暂时不可用：" + e.Message; }
    }

    private void ShowSettings()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private void Quit() { quitting = true; Close(); }
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!quitting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        controller.Dispose();
        preview.Dispose();
        tray.Visible = false;
        tray.ContextMenuStrip?.Dispose();
        tray.Dispose();
        base.OnFormClosed(e);
    }
}
