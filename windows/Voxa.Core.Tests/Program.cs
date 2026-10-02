using System.Runtime.InteropServices;
using Voxa;

int checks = 0;
void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
    checks++;
}

var english = new TranscriptBuffer("en-US");
english.Hypothesize("hello wor");
Check(english.Final == "" && english.Preview == "hello wor", "Hypotheses must not become final text.");
english.Hypothesize("hello world");
english.Commit("hello world");
Check(english.Final == "hello world" && english.Preview == english.Final, "Final results replace partial text without duplication.");
english.Hypothesize("next phra");
Check(english.Preview == "hello world next phra", "Preview retains prior utterances.");
english.Hypothesize("");
Check(english.Final == "hello world" && english.Preview == english.Final, "Rejected speech must not erase confirmed text.");
english.Commit("hello world");
Check(english.Final == "hello world hello world", "Intentional repeated utterances must be preserved.");
var chinese = new TranscriptBuffer("zh-CN");
chinese.Commit("你好");
chinese.Commit("世界");
Check(chinese.Final == "你好世界", "Do not add artificial word spaces between Chinese utterances.");
Check(!DictationPolicy.ShouldFinish(4000, 1000, 3900, true), "Ongoing voice activity prevents auto-finish.");
Check(!DictationPolicy.ShouldFinish(4000, 3900, 1000, true), "Recent recognition prevents auto-finish.");
Check(!DictationPolicy.ShouldFinish(4000, 1000, 1000, false), "Silence without confirmed text does not insert.");
Check(DictationPolicy.ShouldFinish(4000, 2400, 2400, true), "Stable text plus silence ends dictation.");
Check(DictationPolicy.Clean("  echo test\r\nnext\tword  ") == "echo test  next word", "Transcription must never inject Return or Tab.");
Check(DictationPolicy.Clean("a\b\0b") == "a  b", "Other control characters cannot be typed into the target.");
Check(Marshal.SizeOf<Native.Input>() == (IntPtr.Size == 8 ? 40 : 28), "SendInput ABI layout must match Windows INPUT size.");
var taps = new RightControlSequence();
Check(!taps.Change(true, 0, 1, false) && !taps.Change(false, 80, 1, false), "One right Ctrl tap does not trigger.");
Check(!taps.Change(true, 250, 1, false) && taps.Change(false, 320, 1, false), "Two quick right Ctrl taps trigger on release.");
Check(!taps.Change(true, 400, 1, false) && !taps.Change(false, 1000, 1, false), "Long Ctrl holds must not trigger.");
taps.Change(true, 1200, 1, false); taps.Change(false, 1280, 1, false);
taps.Reset(); // Any non-Ctrl key, mouse click, or injected key interrupts.
Check(!taps.Change(true, 1400, 1, false) && !taps.Change(false, 1480, 1, false), "Ctrl shortcuts interrupt the tap sequence.");
taps.Change(true, 1550, 2, false);
Check(!taps.Change(false, 1620, 2, false), "Switching foreground windows interrupts the sequence.");
Check(!taps.Change(true, 1700, 2, true) && !taps.Change(false, 1800, 2, true), "Other modifiers prevent triggering.");
taps.Reset(); taps.Change(true, 2000, 1, false); taps.Change(true, 2030, 1, false); taps.Change(false, 2060, 1, false);
taps.Change(true, 2200, 1, false);
Check(taps.Change(false, 2270, 1, false), "Auto-repeat downs count only once.");
taps.Change(true, 2500, 1, false); taps.Change(false, 2580, 1, false);
taps.Change(true, 3500, 1, false);
Check(!taps.Change(false, 3560, 1, false), "Slow taps start a new sequence.");
Check(!taps.Change(false, 3590, 1, false), "Stray releases never trigger.");
Check(!taps.Change(true, 3600, 0, false), "Missing foreground windows cannot trigger.");
Console.WriteLine($"Passed {checks} checks.");
