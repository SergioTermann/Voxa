using System;
using System.Threading.Tasks;
using System.Windows.Automation;

namespace Voxa;

internal sealed record InsertionTarget(IntPtr Window, AutomationElement Element)
{
    internal static InsertionTarget? Capture()
    {
        try
        {
            IntPtr window = Native.GetForegroundWindow();
            Native.GetWindowThreadProcessId(window, out uint pid);
            if (window == IntPtr.Zero || pid == Environment.ProcessId) return null;
            var element = AutomationElement.FocusedElement;
            if (element == null || element.Current.ProcessId != pid || !Editable(element)) return null;
            return new(window, element);
        }
        catch (Exception) { return null; } // Unresponsive or inaccessible UIA providers fail closed.
    }

    private static bool Editable(AutomationElement element)
    {
        var info = element.Current;
        if (info.IsPassword || !info.IsEnabled || !info.HasKeyboardFocus) return false;
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out object value))
            return !((ValuePattern)value).Current.IsReadOnly;
        // TextPattern alone also occurs on read-only documents. Require the Edit control type.
        return info.ControlType == ControlType.Edit &&
            element.TryGetCurrentPattern(TextPattern.Pattern, out _);
    }

    internal bool IsCurrent()
    {
        try
        {
            var current = Capture();
            return current != null && Window == current.Window && Automation.Compare(Element, current.Element);
        }
        catch (Exception) { return false; }
    }

    internal async Task<string> InsertAsync(string text, Func<bool> stillActive)
    {
        // The stop hotkey may still be held; do not send Unicode while Ctrl/Alt is down.
        for (int i = 0; i < 40 && Native.ModifiersDown; i++)
        {
            if (!stillActive() || !IsCurrent()) return "目标输入框已变化，文字已保留，请手动复制。";
            await Task.Delay(25);
        }
        if (!stillActive()) return "已取消输入，文字已保留。";
        if (Native.ModifiersDown || !IsCurrent()) return "按键尚未松开或焦点已变化，请手动复制。";
        if (!Native.TypeUnicode(text)) return "Windows 未完整接受输入，请检查目标内容后手动复制；管理员窗口可能无法输入。";
        return "已发送文字到输入框；如目标应用不支持 Unicode 输入，请手动复制。";
    }
}
