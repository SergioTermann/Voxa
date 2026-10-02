using System;
using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace Voxa;

internal sealed class RightControlTrigger : IDisposable
{
    private readonly RightControlSequence sequence = new();
    private readonly Native.HookProc keyboardCallback, mouseCallback;
    private readonly Dispatcher dispatcher;
    private readonly DispatcherTimer monitor;
    private IntPtr keyboard, mouse, foreground;
    internal bool Available => keyboard != IntPtr.Zero && mouse != IntPtr.Zero;
    internal event Action? Triggered;

    internal RightControlTrigger(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        keyboardCallback = KeyboardHook;
        mouseCallback = MouseHook;
        monitor = new DispatcherTimer(TimeSpan.FromMilliseconds(100), DispatcherPriority.Input,
            (_, _) =>
            {
                var current = Native.GetForegroundWindow();
                if (current != foreground) { sequence.Reset(); foreground = current; }
            }, dispatcher);
        monitor.Stop();
    }

    internal void Start()
    {
        if (Available) return;
        var module = Native.GetModuleHandle(null);
        keyboard = Native.SetWindowsHookEx(13, keyboardCallback, module, 0); // WH_KEYBOARD_LL
        mouse = Native.SetWindowsHookEx(14, mouseCallback, module, 0); // WH_MOUSE_LL
        if (!Available) { Stop(); return; }
        foreground = Native.GetForegroundWindow();
        monitor.Start();
    }

    private IntPtr KeyboardHook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            var key = Marshal.PtrToStructure<Native.KeyboardHookData>(data);
            int type = message.ToInt32();
            bool down = type == 0x100 || type == 0x104;
            bool up = type == 0x101 || type == 0x105;
            if ((key.Flags & 0x12) != 0) // Injected input never counts as a physical Ctrl tap.
                sequence.Reset();
            else if (down || up)
            {
                bool rightControl = key.VirtualKey == 0xA3 ||
                    (key.VirtualKey == 0x11 && (key.Flags & 1) != 0);
                if (!rightControl) sequence.Reset();
                else if (sequence.Change(down, Environment.TickCount64, Native.GetForegroundWindow(),
                    Native.OtherModifiersDown))
                {
                    // Hooks return immediately. Recognition and UI work are queued outside the callback.
                    var targetWindow = Native.GetForegroundWindow();
                    dispatcher.BeginInvoke(DispatcherPriority.Normal, (Action)(() =>
                    {
                        if (Native.GetForegroundWindow() == targetWindow) Triggered?.Invoke();
                    }));
                }
            }
        }
        return Native.CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    private IntPtr MouseHook(int code, IntPtr message, IntPtr data)
    {
        int type = message.ToInt32();
        if (code >= 0 && type != 0x200) sequence.Reset(); // Movement is harmless; clicks/wheel interrupt taps.
        return Native.CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    private void Stop()
    {
        monitor.Stop();
        if (keyboard != IntPtr.Zero) Native.UnhookWindowsHookEx(keyboard);
        if (mouse != IntPtr.Zero) Native.UnhookWindowsHookEx(mouse);
        keyboard = mouse = IntPtr.Zero;
        sequence.Reset();
    }
    public void Dispose() => Stop();
}
