namespace Voxa;

// All timings use monotonic milliseconds. Ordinary Ctrl shortcuts must never trigger dictation.
internal sealed class RightControlSequence
{
    internal const long MaximumHold = 500;
    internal const long MaximumGap = 650;
    private long? pressedAt, releasedAt;
    private nint window;

    internal bool Change(bool isDown, long now, nint foreground, bool otherModifierDown)
    {
        if (otherModifierDown || foreground == 0) { Reset(); return false; }
        if (window != 0 && window != foreground) Reset();
        window = foreground;
        if (isDown)
        {
            if (pressedAt == null)
            {
                if (releasedAt != null && now - releasedAt > MaximumGap) releasedAt = null;
                pressedAt = now;
            }
            return false; // Ignore auto-repeat downs.
        }
        if (pressedAt == null || now - pressedAt < 0 || now - pressedAt > MaximumHold)
        { Reset(); return false; }
        bool trigger = releasedAt != null && pressedAt - releasedAt >= 0 && pressedAt - releasedAt <= MaximumGap;
        pressedAt = null;
        releasedAt = trigger ? null : now;
        if (trigger) window = 0;
        return trigger;
    }

    internal void Interrupt() => Reset();

    internal void Reset() { pressedAt = releasedAt = null; window = 0; }
}
