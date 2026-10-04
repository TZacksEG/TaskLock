using Microsoft.Win32;
using TaskLock.Core;

namespace TaskLock.Windows;

internal sealed class Coordinator : ApplicationContext
{
    private readonly Control dispatcher = new();
    private readonly RoutineService service;
    private readonly SettingsForm settings;
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 500 };
    private readonly InputGate gate = new();
    private readonly List<LockForm> shields = [];
    private bool changing, sessionLocked, suspended, inputFailed, exiting;
    private DateTimeOffset? previewEnd;
    private RoutineState? previewState;
    private string displaySignature = "";
    private long lastBlocked, lastAccepted;
    private bool Locked => shields.Count > 0;

    internal Coordinator(bool startupLaunch)
    {
        _ = dispatcher.Handle;
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TaskLock", "routine.json");
        service = new RoutineService(new RoutineRepository(data));
        settings = new SettingsForm(service, BeginPreview, Install, ResetInputFailure);
        var menu = new ContextMenuStrip();
        menu.Items.Add("TaskLock — الإعدادات", null, (_, _) => ShowSettings());
        menu.Items.Add("خروج", null, (_, _) => { if (!Locked) ExitThread(); });
        menu.Opening += (_, e) => e.Cancel = Locked;
        tray = new NotifyIcon { Icon = Theme.Icon(), Text = "TaskLock — روتينك اليومي", Visible = true, ContextMenuStrip = menu };
        tray.DoubleClick += (_, _) => ShowSettings();
        service.Changed += StateChanged;
        SystemEvents.SessionSwitch += SessionChanged; SystemEvents.PowerModeChanged += PowerChanged;
        SystemEvents.TimeChanged += TimeChanged;
        SystemEvents.DisplaySettingsChanged += DisplaysChanged; SystemEvents.SessionEnding += SessionEnding;
        timer.Tick += (_, _) => Refresh(); timer.Start();
        Refresh();
        if (!Locked && (!startupLaunch || !service.StorageHealthy || service.State.Tasks.Count == 0)) ShowSettings();
    }
    private void ResetInputFailure() { inputFailed = false; settings.RuntimeError = null; }
    private void OnUI(Action action)
    {
        if (exiting || dispatcher.IsDisposed) return;
        try { if (dispatcher.InvokeRequired) dispatcher.BeginInvoke(action); else action(); }
        catch (InvalidOperationException) { }
    }
    private void StateChanged() => OnUI(() => { settings.RefreshStatus(); Refresh(); });
    private void SessionChanged(object sender, SessionSwitchEventArgs e) => OnUI(() =>
    {
        if (e.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.ConsoleDisconnect or SessionSwitchReason.RemoteDisconnect) sessionLocked = true;
        if (e.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect or SessionSwitchReason.SessionLogon) sessionLocked = false;
        Refresh();
    });
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => OnUI(() => { suspended = e.Mode == PowerModes.Suspend || suspended && e.Mode != PowerModes.Resume; Refresh(); });
    private void TimeChanged(object? sender, EventArgs e) => OnUI(() => { TimeZoneInfo.ClearCachedData(); Refresh(); });
    private void DisplaysChanged(object? sender, EventArgs e) => OnUI(() => { displaySignature = ""; Refresh(); });
    private void SessionEnding(object sender, SessionEndingEventArgs e) => OnUI(ExitThread);

    private void Refresh()
    {
        if (changing || exiting) return;
        changing = true;
        try
        {
            service.Reconcile(DateTimeOffset.Now, TimeZoneInfo.Local);
            var preview = previewEnd.HasValue;
            if (preview && DateTimeOffset.UtcNow >= previewEnd)
            {
                EndPreview(); preview = false;
            }
            if (sessionLocked || suspended || !Native.IsDefaultInputDesktop()) { Dismiss(); return; }
            var desired = preview || service.StorageHealthy && service.State.ShouldLock && !inputFailed;
            if (!desired) { Dismiss(); settings.RefreshStatus(); return; }
            var screens = Screen.AllScreens;
            var signature = string.Join(";", screens.Select(s => $"{s.DeviceName}:{s.Bounds}"));
            if (!Locked || signature != displaySignature)
            {
                Dismiss(); settings.Hide(); displaySignature = signature;
                var state = preview ? previewState! : service.State;
                try
                {
                    foreach (var screen in screens)
                    {
                        var window = new LockForm(screen, state, preview, Complete);
                        window.InteractiveRegionChanged += UpdateRegions; shields.Add(window); window.Show();
                    }
                    shields.FirstOrDefault()?.Activate();
                    if (!gate.Start()) { FailInput("تعذّر بدء فلتر الإدخال. لم يتم قفل الجهاز. يمكنك إعادة المحاولة بحفظ وتفعيل القفل."); return; }
                    UpdateRegions();
                }
                catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
                { FailInput($"تعذّر تجهيز شاشة القفل: {ex.Message}"); return; }
            }
            if (!gate.Pulse()) { FailInput("فلتر الإدخال لم يستجب. تم فتح الشاشة؛ أعد الحفظ والتفعيل للمحاولة."); return; }
            var activeState = preview ? previewState! : service.State;
            foreach (var shield in shields)
            {
                shield.UpdateState(activeState);
                if (preview) shield.UpdateCountdown(Math.Max(0, (int)Math.Ceiling((previewEnd!.Value - DateTimeOffset.UtcNow).TotalSeconds)));
                if (!shield.TopMost) shield.TopMost = true;
            }
            if (!Native.OwnsForeground()) shields.FirstOrDefault()?.Activate();
        }
        finally { changing = false; }
    }
    private void UpdateRegions() => gate.SetRegions(shields.Where(s => s.IsHandleCreated && !s.IsDisposed).Select(s => s.InteractiveRegion).ToArray());
    private void Complete(Guid id)
    {
        if (previewState is not null)
        {
            previewState = previewState.Complete(id);
            foreach (var shield in shields) shield.UpdateState(previewState);
        }
        else service.Complete(id, DateTimeOffset.Now, TimeZoneInfo.Local);
    }
    private void BeginPreview()
    {
        if (Locked) return;
        previewState = new RoutineState { Tasks = [new(Guid.NewGuid(), "اشرب كوب مية"), new(Guid.NewGuid(), "اتحرك دقيقة بعيد عن المكتب")], Enabled = true };
        previewEnd = DateTimeOffset.UtcNow.AddSeconds(15);
        Refresh();
    }
    private void EndPreview()
    {
        previewEnd = null; previewState = null; Dismiss();
        settings.RuntimeError = $"انتهت المعاينة · محاولات لوحة مفاتيح محجوبة: {lastBlocked} · نقرات مسموحة: {lastAccepted}";
        settings.Show(); settings.Activate(); settings.RefreshStatus();
    }
    private void Dismiss()
    {
        if (Locked) { lastBlocked = gate.BlockedKeys; lastAccepted = gate.AcceptedClicks; }
        gate.Stop();
        var closing = shields.ToArray(); shields.Clear();
        foreach (var shield in closing) { shield.InteractiveRegionChanged -= UpdateRegions; shield.Release(); }
    }
    private void FailInput(string message)
    {
        inputFailed = true; previewEnd = null; previewState = null; Dismiss();
        settings.RuntimeError = message; settings.RefreshStatus(); settings.Show(); settings.Activate();
    }
    private void ShowSettings()
    {
        if (Locked) return;
        settings.RefreshStatus(); settings.Show(); settings.WindowState = FormWindowState.Normal; settings.Activate();
    }
    private void Install()
    {
        if (Locked || Startup.IsInstalled) return;
        try
        {
            if (!settings.SaveInstallationDraft()) return;
            Startup.Install();
            // Release the single-instance mutex only after this process ends; the new instance waits briefly.
            Startup.StartInstalled(); ExitThread();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException or System.ComponentModel.Win32Exception)
        { MessageBox.Show(settings, $"تعذّر التثبيت: {ex.Message}", "TaskLock", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
    protected override void ExitThreadCore()
    {
        if (exiting) return;
        exiting = true; timer.Stop(); timer.Dispose();
        SystemEvents.SessionSwitch -= SessionChanged; SystemEvents.PowerModeChanged -= PowerChanged;
        SystemEvents.TimeChanged -= TimeChanged;
        SystemEvents.DisplaySettingsChanged -= DisplaysChanged; SystemEvents.SessionEnding -= SessionEnding;
        service.Changed -= StateChanged;
        Dismiss(); gate.Dispose(); tray.Visible = false; tray.Dispose(); settings.Dispose(); dispatcher.Dispose();
        base.ExitThreadCore();
    }
}
