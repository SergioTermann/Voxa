using System;
using System.Speech.Recognition;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace Voxa;

internal enum Phase { Idle, Listening, Finishing }

internal sealed class DictationController : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(150) };
    private SpeechRecognitionEngine? engine;
    private TranscriptBuffer buffer = new("en-US");
    private long session, started, lastText, lastVoice, finishStarted;
    private bool speaking, autoFinish;
    private InsertionTarget? destination;
    internal Phase Phase { get; private set; }
    internal string Preview => buffer.Preview;
    internal string LastResult { get; private set; } = "";
    internal string Message { get; private set; } = "点击输入框，双击右 Ctrl 开始听写。";
    internal event Action? Changed;
    internal int AudioLevel { get; private set; }

    internal DictationController(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        timer.Tick += (_, _) => Tick();
    }

    private void Publish(string? message = null)
    {
        if (message != null) Message = message;
        Changed?.Invoke();
    }

    private void Dispatch(long id, Action action)
    {
        if (dispatcher.HasShutdownStarted) return;
        try { dispatcher.BeginInvoke((Action)(() => { if (id == session && engine != null) action(); })); }
        catch (InvalidOperationException) { /* Closing the app. */ }
    }

    internal void Toggle(RecognizerInfo? recognizer, bool finishAfterPause)
    {
        if (Phase == Phase.Listening) { Finish(); return; }
        if (Phase != Phase.Idle) return;
        if (recognizer == null)
        {
            Publish("没有兼容的本机语音识别引擎。请安装 Windows 语音组件后重新启动 Voxa，详见 Windows README。");
            return;
        }
        if (InsertionTarget.Capture() == null)
        {
            Publish("请先点击其他应用的可编辑输入框。密码框及无法确认可编辑的控件不支持自动输入。");
            return;
        }
        long id = ++session;
        buffer = new TranscriptBuffer(recognizer.Culture.Name);
        destination = null;
        autoFinish = finishAfterPause;
        speaking = false;
        AudioLevel = 0;
        started = lastText = lastVoice = Environment.TickCount64;
        try
        {
            engine = new SpeechRecognitionEngine(recognizer);
            engine.LoadGrammar(new DictationGrammar());
            engine.InitialSilenceTimeout = TimeSpan.FromSeconds(15);
            engine.BabbleTimeout = TimeSpan.FromSeconds(15);
            engine.EndSilenceTimeout = TimeSpan.FromMilliseconds(700);
            engine.EndSilenceTimeoutAmbiguous = TimeSpan.FromMilliseconds(1000);
            engine.SpeechHypothesized += (_, e) => Dispatch(id, () =>
            {
                buffer.Hypothesize(e.Result.Text);
                lastText = lastVoice = Environment.TickCount64;
                Publish();
            });
            engine.SpeechRecognized += (_, e) => Dispatch(id, () =>
            {
                buffer.Commit(e.Result.Text);
                lastText = Environment.TickCount64;
                Publish();
            });
            engine.SpeechRecognitionRejected += (_, _) => Dispatch(id, () =>
            {
                buffer.Hypothesize("");
                Publish();
            });
            engine.AudioLevelUpdated += (_, e) => Dispatch(id, () => AudioLevel = e.AudioLevel);
            engine.AudioStateChanged += (_, e) => Dispatch(id, () =>
            {
                speaking = e.AudioState == AudioState.Speech;
                lastVoice = Environment.TickCount64;
            });
            engine.RecognizeCompleted += (_, e) => Dispatch(id, () =>
                _ = CompleteAsync(id, e.Error, e.Cancelled));
            engine.SetInputToDefaultAudioDevice();
            Phase = Phase.Listening;
            engine.RecognizeAsync(RecognizeMode.Multiple);
            timer.Start();
            Publish("正在聆听；双击右 Ctrl 完成，Ctrl + Alt + Esc 取消。");
        }
        catch (Exception e)
        {
            ReleaseEngine();
            Phase = Phase.Idle;
            Publish("无法启动语音识别。请检查默认麦克风、桌面应用麦克风权限和语音组件。" + e.Message);
        }
    }

    private void Tick()
    {
        long now = Environment.TickCount64;
        if (Phase == Phase.Listening)
        {
            if (speaking) lastVoice = now;
            if (now - started >= 55000 || (autoFinish &&
                DictationPolicy.ShouldFinish(now, lastText, lastVoice, buffer.Final.Length > 0))) Finish();
        }
        else if (Phase == Phase.Finishing && engine != null && now - finishStarted >= 5000)
        {
            LastResult = buffer.Final;
            ++session;
            ReleaseEngine();
            Phase = Phase.Idle;
            Publish("识别结束超时，已保留确认识别的文字，请手动复制。");
        }
    }

    private void Finish()
    {
        if (Phase != Phase.Listening) return;
        destination = InsertionTarget.Capture();
        Phase = Phase.Finishing;
        finishStarted = Environment.TickCount64;
        Publish("正在完成识别，请保持输入框焦点不变……");
        try { engine?.RecognizeAsyncStop(); }
        catch (Exception e) { _ = CompleteAsync(session, e, false); }
    }

    private async Task CompleteAsync(long id, Exception? error, bool cancelled)
    {
        if (id != session) return;
        // An unsolicited completion (silence, device loss, etc.) never inserts text.
        bool insert = Phase == Phase.Finishing && error == null && !cancelled;
        var target = destination;
        LastResult = buffer.Final;
        ReleaseEngine();
        Phase = Phase.Finishing;
        string message;
        if (error != null) message = "语音识别失败，已有文字已保留：" + error.Message;
        else if (cancelled) message = "已取消识别。";
        else if (LastResult.Length == 0) message = "未识别到有效语音，请检查麦克风和所选语言。";
        else if (!insert || target == null) message = "文字已保留；当前没有安全的目标输入框，请手动复制。";
        else
        {
            try { message = await target.InsertAsync(LastResult, () => id == session); }
            catch (Exception e) { message = "输入失败，文字已保留，请手动复制：" + e.Message; }
        }
        if (id != session) return;
        Phase = Phase.Idle;
        Publish(message);
    }

    internal void Cancel()
    {
        if (Phase == Phase.Idle) return;
        ++session;
        ReleaseEngine();
        buffer = new TranscriptBuffer("en-US");
        Phase = Phase.Idle;
        Publish("已取消；未发送新的文字。上次完成的结果仍可复制。");
    }

    internal void Clear()
    {
        if (Phase != Phase.Idle) return;
        LastResult = "";
        buffer = new TranscriptBuffer("en-US");
        Publish("已清除识别文字。");
    }

    private void ReleaseEngine()
    {
        timer.Stop();
        var old = engine;
        engine = null;
        AudioLevel = 0;
        if (old == null) return;
        try { old.RecognizeAsyncCancel(); }
        catch (InvalidOperationException) { }
        old.Dispose();
    }

    public void Dispose()
    {
        ++session;
        ReleaseEngine();

    }
}
