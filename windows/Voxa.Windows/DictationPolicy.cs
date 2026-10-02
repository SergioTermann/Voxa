using System.Collections.Generic;

namespace Voxa;

internal static class DictationPolicy
{
    internal static bool ShouldFinish(long now, long lastText, long lastVoice, bool hasText) =>
        hasText && now - lastText >= 1600 && now - lastVoice >= 1600;

    // Unicode input must never submit a command or insert control characters.
    internal static string Clean(string text)
    {
        var characters = text.ToCharArray();
        for (int i = 0; i < characters.Length; i++)
            if (char.IsControl(characters[i])) characters[i] = ' ';
        return new string(characters).Trim();
    }
}

internal sealed class TranscriptBuffer
{
    private readonly List<string> segments = new();
    private string hypothesis = "";
    private readonly string separator;

    internal TranscriptBuffer(string language) => separator =
        language.StartsWith("zh") || language.StartsWith("ja") ? "" : " ";

    internal void Hypothesize(string text) => hypothesis = DictationPolicy.Clean(text);
    internal void Commit(string text)
    {
        text = DictationPolicy.Clean(text);
        if (text.Length > 0) segments.Add(text);
        hypothesis = "";
    }
    internal string Final => string.Join(separator, segments);
    internal string Preview => Final.Length == 0 ? hypothesis :
        hypothesis.Length == 0 ? Final : Final + separator + hypothesis;
}
