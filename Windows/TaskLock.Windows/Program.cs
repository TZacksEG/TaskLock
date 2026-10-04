namespace TaskLock.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Contains("--remove-startup"))
        {
            try { Startup.SetEnabled(false); } catch (Exception ex) { MessageBox.Show(ex.Message, "TaskLock"); }
            return;
        }
        if (args.Contains("--install") && !Startup.IsInstalled)
        {
            try { Startup.Install(); Startup.StartInstalled(); } catch (Exception ex) { MessageBox.Show($"تعذّر التثبيت: {ex.Message}", "TaskLock"); }
            return;
        }
        using var instance = new Mutex(false, @"Local\TaskLock.Desktop");
        var owned = false;
        try
        {
            try { owned = instance.WaitOne(args.Contains("--settings") ? 4000 : 0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) { if (!args.Contains("--startup")) MessageBox.Show("TaskLock يعمل بالفعل. افتح الإعدادات من أيقونته بجوار الساعة.", "TaskLock"); return; }
            using var context = new Coordinator(args.Contains("--startup"));
            Application.Run(context);
        }
        finally { if (owned) instance.ReleaseMutex(); }
    }
}
