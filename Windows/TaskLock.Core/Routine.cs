using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaskLock.Core;

public sealed record RoutineTask(Guid Id, string Title);

public sealed record RoutineState
{
    [JsonRequired] public List<RoutineTask> Tasks { get; init; } = [];
    [JsonRequired] public HashSet<Guid> CompletedIds { get; init; } = [];
    [JsonRequired] public string CycleKey { get; init; } = DailyCycle.Key(DateTimeOffset.Now, TimeZoneInfo.Local, 0, 0);
    [JsonRequired] public int ResetHour { get; init; }
    [JsonRequired] public int ResetMinute { get; init; }
    [JsonRequired] public bool Enabled { get; init; }
    [JsonIgnore] public bool ShouldLock => Enabled && Tasks.Count > 0 && Tasks.Any(t => !CompletedIds.Contains(t.Id));

    public RoutineState Reconciled(DateTimeOffset now, TimeZoneInfo zone)
    {
        var key = DailyCycle.Key(now, zone, ResetHour, ResetMinute);
        return string.CompareOrdinal(key, CycleKey) > 0 ? this with { CycleKey = key, CompletedIds = [] } : this;
    }

    public RoutineState Complete(Guid id) => Tasks.Any(t => t.Id == id)
        ? this with { CompletedIds = new HashSet<Guid>(CompletedIds) { id } } : this;

    public void Validate()
    {
        if (Tasks is null || CompletedIds is null || Tasks.Any(t => t is null)) throw new RoutineValidationException("ملف المهام غير مكتمل.");
        if (ResetHour is < 0 or > 23 || ResetMinute is < 0 or > 59) throw new RoutineValidationException("اختر وقتًا صحيحًا لبداية اليوم.");
        if (CycleKey is null || !DateOnly.TryParseExact(CycleKey, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _)) throw new RoutineValidationException("تاريخ الروتين المحفوظ غير صحيح.");
        if (Tasks.Count > 100) throw new RoutineValidationException("الحد الأقصى ١٠٠ مهمة.");
        if (Tasks.Any(t => string.IsNullOrWhiteSpace(t.Title) || t.Title.Length > 240)) throw new RoutineValidationException("اسم المهمة مطلوب، وبحد أقصى ٢٤٠ حرفًا.");
        if (Tasks.Any(t => t.Id == Guid.Empty) || Tasks.Select(t => t.Id).Distinct().Count() != Tasks.Count) throw new RoutineValidationException("معرّفات المهام غير صحيحة.");
        if (!CompletedIds.IsSubsetOf(Tasks.Select(t => t.Id))) throw new RoutineValidationException("هناك إنجاز لمهمة غير موجودة.");
    }
}

public sealed class RoutineValidationException(string message) : Exception(message);

public static class DailyCycle
{
    public static string Key(DateTimeOffset now, TimeZoneInfo zone, int hour, int minute)
    {
        var local = TimeZoneInfo.ConvertTime(now, zone).DateTime;
        var boundary = DateTime.SpecifyKind(local.Date.AddHours(Math.Clamp(hour, 0, 23)).AddMinutes(Math.Clamp(minute, 0, 59)), DateTimeKind.Unspecified);
        // First valid time after a DST gap, and first occurrence of a repeated time.
        while (zone.IsInvalidTime(boundary)) boundary = boundary.AddMinutes(1);
        var offset = zone.IsAmbiguousTime(boundary) ? zone.GetAmbiguousTimeOffsets(boundary).Max() : zone.GetUtcOffset(boundary);
        var starts = new DateTimeOffset(boundary, offset);
        var date = now < starts ? local.Date.AddDays(-1) : local.Date;
        return date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    }
}

public interface IRoutineRepository
{
    RoutineState Load();
    void Save(RoutineState state);
}

public sealed class RoutineRepository(string path) : IRoutineRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    public RoutineState Load()
    {
        string json;
        try { json = File.ReadAllText(path); }
        catch (FileNotFoundException) { return new RoutineState(); }
        catch (DirectoryNotFoundException) { return new RoutineState(); }
        var state = JsonSerializer.Deserialize<RoutineState>(json, JsonOptions) ?? throw new JsonException("ملف المهام فارغ.");
        state.Validate();
        return state;
    }
    public void Save(RoutineState state)
    {
        state.Validate();
        var folder = Path.GetDirectoryName(Path.GetFullPath(path))!;
        Directory.CreateDirectory(folder);
        var temporary = Path.Combine(folder, $".tasklock-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(file, state, JsonOptions);
                file.Flush(true);
            }
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(temporary, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            if (File.Exists(path)) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
