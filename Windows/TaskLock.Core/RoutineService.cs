namespace TaskLock.Core;

public sealed class RoutineService
{
    private readonly IRoutineRepository repository;
    public RoutineState State { get; private set; } = new();
    public bool StorageHealthy { get; private set; } = true;
    public string? Error { get; private set; }
    public int ConfigurationRevision { get; private set; }
    public event Action? Changed;

    public RoutineService(IRoutineRepository repository)
    {
        this.repository = repository;
        try { State = repository.Load(); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or RoutineValidationException)
        { StorageHealthy = false; Error = $"تعذّر قراءة المهام. الملف الأصلي محفوظ. {ex.Message}"; }
    }

    public bool Persist(RoutineState candidate)
    {
        if (!StorageHealthy) return false;
        try { candidate.Validate(); repository.Save(candidate); State = candidate; Error = null; Changed?.Invoke(); return true; }
        catch (RoutineValidationException ex) { Error = ex.Message; Changed?.Invoke(); return false; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        { StorageHealthy = false; Error = $"تعذّر حفظ التقدم. تم إيقاف القفل للحفاظ على إمكانية استخدام الجهاز. {ex.Message}"; Changed?.Invoke(); return false; }
    }

    public void Reconcile(DateTimeOffset now, TimeZoneInfo zone)
    {
        if (!StorageHealthy) return;
        var next = State.Reconciled(now, zone);
        if (!ReferenceEquals(next, State)) Persist(next);
    }
    public bool Complete(Guid id, DateTimeOffset now, TimeZoneInfo zone) => Persist(State.Reconciled(now, zone).Complete(id));

    public bool Configure(List<RoutineTask> tasks, int hour, int minute, DateTimeOffset now, TimeZoneInfo zone, bool enabled = true)
    {
        if (tasks.Count == 0 && enabled) { Error = "أضف مهمة واحدة على الأقل."; Changed?.Invoke(); return false; }
        var current = State.Reconciled(now, zone);
        var clean = tasks.Select(t => t with { Title = t.Title.Trim() }).ToList();
        var retained = clean.Where(t => current.Tasks.Any(old => old.Id == t.Id && old.Title == t.Title)).Select(t => t.Id).ToHashSet();
        return Persist(current with { Tasks = clean, CompletedIds = current.CompletedIds.Intersect(retained).ToHashSet(), ResetHour = hour, ResetMinute = minute,
            CycleKey = DailyCycle.Key(now, zone, hour, minute), Enabled = enabled });
    }

    public bool RetryStorage()
    {
        try
        {
            var loaded = repository.Load();
            repository.Save(loaded);
            State = loaded; StorageHealthy = true; Error = null; ConfigurationRevision++; Changed?.Invoke(); return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or RoutineValidationException)
        { StorageHealthy = false; Error = $"ملف المهام ما زال غير متاح. {ex.Message}"; Changed?.Invoke(); return false; }
    }
}
