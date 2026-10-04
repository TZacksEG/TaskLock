namespace TaskLock.Core;

public readonly record struct GateRect(int Left, int Top, int Right, int Bottom)
{
    public bool Contains(int x, int y) => x >= Left && x < Right && y >= Top && y < Bottom;
}

/// State lives on the hook thread. Coordinates are physical desktop pixels.
public sealed class PointerPolicy
{
    private bool acceptedDown;
    public bool ShouldBlock(int message, int x, int y, GateRect[] regions, bool ownsForeground)
    {
        if (message == 0x0200) return false; // Cursor movement.
        var inside = ownsForeground && Array.Exists(regions, r => r.Contains(x, y));
        if (message == 0x0201) { acceptedDown = inside; return !inside; }
        if (message == 0x0202) { var allowed = acceptedDown && ownsForeground; acceptedDown = false; return !allowed; }
        if (message is 0x020A or 0x020E) return !inside;
        return true;
    }
}
