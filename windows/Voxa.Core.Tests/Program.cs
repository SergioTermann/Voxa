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
Console.WriteLine($"Passed {checks} checks.");
