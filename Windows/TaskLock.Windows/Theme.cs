using System.Reflection;

namespace TaskLock.Windows;

internal static class Theme
{
    internal static readonly Color Canvas = Color.FromArgb(9, 13, 17);
    internal static readonly Color Panel = Color.FromArgb(20, 25, 29);
    internal static readonly Color Mint = Color.FromArgb(148, 232, 196);
    internal static readonly Color Muted = Color.FromArgb(151, 164, 169);
    internal static Icon Icon()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("TaskLock.Windows.Assets.TaskLock.ico");
        if (stream is null) return (Icon)SystemIcons.Shield.Clone();
        using var icon = new Icon(stream);
        return (Icon)icon.Clone();
    }
    internal static Label Label(string text, float size = 12, bool bold = false) => new()
    { Text = text, Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular), ForeColor = Color.White, AutoSize = false, TextAlign = ContentAlignment.MiddleRight, Dock = DockStyle.Top, Height = (int)(size * 2.8), RightToLeft = RightToLeft.Yes };
    internal static Button Button(string text, bool primary = false) => new()
    { Text = text, Height = 42, AutoSize = true, MinimumSize = new Size(115, 42), FlatStyle = FlatStyle.Flat, ForeColor = primary ? Canvas : Color.White, BackColor = primary ? Mint : Panel, Font = new Font("Segoe UI", 11, FontStyle.Bold), Padding = new Padding(10, 4, 10, 4), Cursor = Cursors.Hand };
}
