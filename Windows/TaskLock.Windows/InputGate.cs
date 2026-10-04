using System.Diagnostics;
using System.Runtime.InteropServices;
using TaskLock.Core;

namespace TaskLock.Windows;

/// Hooks live on a dedicated message-loop thread; no disk/UI work occurs in callbacks.
internal sealed class InputGate : IDisposable
{
    private Thread? worker;
    private CancellationTokenSource? cancellation;
    private uint threadId;
    private volatile bool enabled;
    private volatile bool failed;
    private GateRect[] regions = [];
    private long heartbeat;
    private long uiHeartbeat;
    private long blockedKeys;
    private long acceptedClicks;
    private const uint PulseMessage = 0x804D;
    public bool Active => enabled && worker?.IsAlive == true && !failed;
    public long BlockedKeys => Interlocked.Read(ref blockedKeys);
    public long AcceptedClicks => Interlocked.Read(ref acceptedClicks);
    public void SetRegions(GateRect[] next) => Volatile.Write(ref regions, next);

    public bool Start()
    {
        if (Active) return true;
        Stop();
        // Never overlap hooks if an old loop did not finish promptly.
        if (worker?.IsAlive == true) return false;
        failed = false;
        blockedKeys = acceptedClicks = 0;
        Interlocked.Exchange(ref uiHeartbeat, Stopwatch.GetTimestamp());
        var ready = new ManualResetEventSlim();
        cancellation = new CancellationTokenSource();
        var token = cancellation.Token;
        worker = new Thread(() => Run(ready, token)) { IsBackground = true, Name = "TaskLock input filter" };
        worker.SetApartmentState(ApartmentState.STA);
        worker.Start();
        if (!ready.Wait(TimeSpan.FromSeconds(3)) || !Active) { Stop(); return false; }
        return true;
    }

    private void Run(ManualResetEventSlim ready, CancellationToken token)
    {
        nint keyboard = 0, mouse = 0;
        var policy = new PointerPolicy();
        using var watchdog = new System.Windows.Forms.Timer { Interval = 100 };
        var lastTick = Stopwatch.GetTimestamp();
        watchdog.Tick += (_, _) =>
        {
            var elapsed = Stopwatch.GetElapsedTime(lastTick);
            lastTick = Stopwatch.GetTimestamp();
            // Hook removal is not observable. A long scheduling gap makes this
            // session untrusted even if the message-loop heartbeat recovers.
            if (token.IsCancellationRequested || elapsed > TimeSpan.FromMilliseconds(750) || !CanFilter(token))
            { failed = true; enabled = false; Application.ExitThread(); }
        };
        var filter = new HeartbeatFilter(() => Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp()));
        Native.HookProc keyboardCallback = (code, w, l) =>
        {
            if (code < 0 || !CanFilter(token)) return Native.CallNextHookEx(0, code, w, l);
            Interlocked.Increment(ref blockedKeys);
            return 1;
        };
        Native.HookProc mouseCallback = (code, w, l) =>
        {
            if (code < 0 || !CanFilter(token)) return Native.CallNextHookEx(0, code, w, l);
            try
            {
                var point = Marshal.PtrToStructure<Native.MouseData>(l).Point;
                var block = policy.ShouldBlock((int)w, point.X, point.Y, Volatile.Read(ref regions), Native.OwnsForeground());
                if (!block && (int)w == 0x0201) Interlocked.Increment(ref acceptedClicks);
                return block ? 1 : Native.CallNextHookEx(0, code, w, l);
            }
            catch { failed = true; enabled = false; return Native.CallNextHookEx(0, code, w, l); }
        };
        try
        {
            threadId = Native.GetCurrentThreadId();
            Native.PeekMessageW(out _, 0, 0, 0, 0);
            keyboard = Native.SetWindowsHookExW(13, keyboardCallback, Native.GetModuleHandleW(null), 0);
            mouse = Native.SetWindowsHookExW(14, mouseCallback, Native.GetModuleHandleW(null), 0);
            enabled = keyboard != 0 && mouse != 0 && !token.IsCancellationRequested;
            failed = !enabled;
            Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp());
            Application.AddMessageFilter(filter);
            ready.Set();
            if (enabled && !token.IsCancellationRequested) { watchdog.Start(); Application.Run(); }
        }
        catch { failed = true; enabled = false; ready.Set(); }
        finally
        {
            watchdog.Stop();
            enabled = false;
            if (keyboard != 0) Native.UnhookWindowsHookEx(keyboard);
            if (mouse != 0) Native.UnhookWindowsHookEx(mouse);
            Application.RemoveMessageFilter(filter);
            GC.KeepAlive(keyboardCallback); GC.KeepAlive(mouseCallback);
        }
    }

    private bool CanFilter(CancellationToken token)
    {
        if (!enabled || token.IsCancellationRequested) return false;
        if (Stopwatch.GetElapsedTime(Interlocked.Read(ref uiHeartbeat)) <= TimeSpan.FromSeconds(3)) return true;
        failed = true; enabled = false; return false;
    }

    // Liveness only: Windows supplies no API to prove a low-level hook still exists.
    public bool Pulse()
    {
        Interlocked.Exchange(ref uiHeartbeat, Stopwatch.GetTimestamp());
        if (!Active) return false;
        if (!Native.PostThreadMessageW(threadId, PulseMessage, 0, 0)) return false;
        return Stopwatch.GetElapsedTime(Interlocked.Read(ref heartbeat)) < TimeSpan.FromSeconds(3);
    }
    public void Stop()
    {
        cancellation?.Cancel();
        enabled = false;
        if (threadId != 0) Native.PostThreadMessageW(threadId, 0x0012, 0, 0);
        if (worker is not null && worker != Thread.CurrentThread) worker.Join(1500);
        if (worker?.IsAlive != true) { worker = null; threadId = 0; cancellation?.Dispose(); cancellation = null; }
        SetRegions([]);
    }
    public void Dispose() => Stop();
    private sealed class HeartbeatFilter(Action pulse) : IMessageFilter
    {
        public bool PreFilterMessage(ref System.Windows.Forms.Message m) { if (m.Msg != PulseMessage) return false; pulse(); return true; }
    }
}
