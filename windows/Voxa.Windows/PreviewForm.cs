using System.Drawing;
using System.Windows.Forms;

namespace Voxa;

internal sealed class PreviewForm : Form
{
    private readonly Label transcript = new() { Dock = DockStyle.Fill, ForeColor = Color.White,
        Padding = new Padding(16, 10, 16, 8), AutoEllipsis = true };
    private readonly Label heading = new() { Dock = DockStyle.Top, Height = 38, ForeColor = Color.Turquoise,
        Padding = new Padding(16, 12, 0, 0) };

    internal PreviewForm()
    {
        Text = "Voxa · Listening";
        Font = new Font("Microsoft YaHei UI", 10);
        FormBorderStyle = FormBorderStyle.None;
        BackColor = Color.FromArgb(30, 35, 44);
        ClientSize = new Size(480, 155);
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Controls.Add(transcript);
        Controls.Add(heading);
        Controls.Add(new Label { Dock = DockStyle.Bottom, Height = 30,
            ForeColor = Color.Silver, Padding = new Padding(16, 0, 0, 0),
            Text = "Ctrl + Alt + Space 完成  ·  Ctrl + Alt + Esc 取消" });
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x00000080; return p; }
    }
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0021) { m.Result = (System.IntPtr)3; return; } // MA_NOACTIVATE
        base.WndProc(ref m);
    }

    internal void UpdatePreview(Phase phase, string text)
    {
        heading.Text = phase == Phase.Finishing ? "Voxa · 正在完成识别" : "Voxa · 本机语音识别";
        transcript.Text = text.Length == 0 ? "请开始说话……" : text;
        if (Visible) return;
        var area = Screen.FromHandle(Native.GetForegroundWindow()).WorkingArea;
        Location = new Point(area.Left + (area.Width - Width) / 2, area.Bottom - Height - 36);
        Show();
    }
}
