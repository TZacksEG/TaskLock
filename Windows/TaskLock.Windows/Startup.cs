using Microsoft.Win32;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace TaskLock.Windows;

internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "TaskLock";
    internal static string InstalledPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "TaskLock", "TaskLock.exe");
    internal static bool IsInstalled => string.Equals(Environment.ProcessPath, InstalledPath, StringComparison.OrdinalIgnoreCase);
    private static string Command => $"\"{InstalledPath}\" --startup";
    internal static bool Enabled
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(RunKey); return string.Equals(key?.GetValue(ValueName) as string, Command, StringComparison.OrdinalIgnoreCase); }
    }
    internal static void SetEnabled(bool enabled)
    {
        if (enabled && !IsInstalled) throw new InvalidOperationException("ثبّت التطبيق في حسابك أولًا ليظل مساره ثابتًا عند بدء ويندوز.");
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, true);
        if (enabled) key.SetValue(ValueName, Command, RegistryValueKind.String);
        else if (Enabled) key.DeleteValue(ValueName, false);
    }
    internal static void Install()
    {
        if (IsInstalled) return;
        Directory.CreateDirectory(Path.GetDirectoryName(InstalledPath)!);
        File.Copy(Environment.ProcessPath ?? throw new IOException("تعذّر تحديد ملف التطبيق."), InstalledPath, true);
        var assembly = System.Reflection.Assembly.GetExecutingAssembly();
        foreach (var name in new[] { "DOTNET-LICENSE.txt", "DOTNET-THIRD-PARTY-NOTICES.txt" })
        {
            using var source = assembly.GetManifestResourceStream($"TaskLock.Notices.{name}") ?? throw new IOException("Missing runtime notices.");
            using var target = File.Create(Path.Combine(Path.GetDirectoryName(InstalledPath)!, name));
            source.CopyTo(target);
        }
        var shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType is not null)
        {
            object? shellObject = null, shortcutObject = null;
            try
            {
                shellObject = Activator.CreateInstance(shellType)!;
                dynamic shell = shellObject;
                shortcutObject = shell.CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "TaskLock.lnk"));
                dynamic shortcut = shortcutObject;
                shortcut.TargetPath = InstalledPath;
                shortcut.WorkingDirectory = Path.GetDirectoryName(InstalledPath);
                shortcut.Description = "TaskLock — Daily offline routine";
                shortcut.Save();
            }
            finally
            {
                if (shortcutObject is not null) Marshal.FinalReleaseComObject(shortcutObject);
                if (shellObject is not null) Marshal.FinalReleaseComObject(shellObject);
            }
        }
    }
    internal static void StartInstalled() => Process.Start(new ProcessStartInfo(InstalledPath, "--settings") { UseShellExecute = true });
}
