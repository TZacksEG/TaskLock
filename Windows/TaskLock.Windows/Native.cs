using System.Runtime.InteropServices;
using System.Text;

namespace TaskLock.Windows;

internal static class Native
{
    internal delegate nint HookProc(int code, nint wParam, nint lParam);
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct MouseData { public Point Point; public uint Mouse, Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)] internal struct Message { public nint Window; public uint Id; public nuint W; public nint L; public uint Time; public Point Point; }
    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SetWindowsHookExW(int hook, HookProc proc, nint module, uint threadId);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint w, nint l);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern nint GetModuleHandleW(string? name);
    [DllImport("kernel32.dll")] internal static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool PostThreadMessageW(uint id, uint message, nuint w, nint l);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool PeekMessageW(out Message message, nint window, uint min, uint max, uint remove);
    [DllImport("user32.dll", SetLastError = true)] internal static extern nint OpenInputDesktop(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetUserObjectInformationW(nint handle, int index, StringBuilder information, uint length, out uint needed);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseDesktop(nint desktop);

    internal static bool OwnsForeground()
    {
        GetWindowThreadProcessId(GetForegroundWindow(), out var id);
        return id == Environment.ProcessId;
    }
    internal static bool IsDefaultInputDesktop()
    {
        var desktop = OpenInputDesktop(0, false, 1);
        if (desktop == 0) return false;
        try { var name = new StringBuilder(256); return GetUserObjectInformationW(desktop, 2, name, 512, out _) && name.ToString() == "Default"; }
        finally { CloseDesktop(desktop); }
    }
}
