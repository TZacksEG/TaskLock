using TaskLock.Core;
using System.Text.Json;

var tests = new List<(string Name, Action Body)>();
void Test(string name, Action body) => tests.Add((name, body));
void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}, got {actual}"); }
void Throws<T>(Action body) where T : Exception { try { body(); } catch (T) { return; } throw new Exception($"Expected {typeof(T).Name}"); }
DateTimeOffset At(string text) => DateTimeOffset.Parse(text, System.Globalization.CultureInfo.InvariantCulture);
var utc = TimeZoneInfo.Utc;
var id = Guid.NewGuid();
var second = Guid.NewGuid();
var state = new RoutineState { Tasks = [new(id, "Drink water"), new(second, "Stretch")], Enabled = true, CycleKey = "2026-10-04" };
var now = At("2026-10-04T12:00:00Z");

Test("new recipient starts empty and disabled", () => { var s = new RoutineState(); Equal(false, s.Enabled); Equal(false, s.ShouldLock); Equal(0, s.Tasks.Count); });
Test("partial completion stays locked", () => { var s = state.Complete(id); Equal(true, s.ShouldLock); Equal(false, state.CompletedIds.Contains(id)); });
Test("last completion unlocks", () => Equal(false, state.Complete(id).Complete(second).ShouldLock));
Test("unknown completion ignored", () => Equal(true, ReferenceEquals(state, state.Complete(Guid.NewGuid()))));
Test("same day restart preserves completion", () => Equal(1, state.Complete(id).Reconciled(now, utc).CompletedIds.Count));
Test("next day resets once", () => { var s = state.Complete(id).Reconciled(At("2026-10-05T00:00:00Z"), utc); Equal(0, s.CompletedIds.Count); Equal("2026-10-05", s.CycleKey); Equal(true, ReferenceEquals(s, s.Reconciled(At("2026-10-05T00:01:00Z"), utc))); });
Test("clock backwards never reopens completed cycle", () => Equal(2, state.Complete(id).Complete(second).Reconciled(At("2026-10-03T23:59:00Z"), utc).CompletedIds.Count));
Test("missed days advance directly", () => Equal("2026-10-12", state.Reconciled(At("2026-10-12T12:00:00Z"), utc).CycleKey));
Test("custom reset minute boundary", () => { Equal("2026-10-03", DailyCycle.Key(At("2026-10-04T06:29:59Z"), utc, 6, 30)); Equal("2026-10-04", DailyCycle.Key(At("2026-10-04T06:30:00Z"), utc, 6, 30)); });
Test("DST spring gap uses first valid minute", () => { var zone = TimeZoneInfo.FindSystemTimeZoneById("America/New_York"); Equal("2026-03-07", DailyCycle.Key(At("2026-03-08T06:59:59Z"), zone, 2, 30)); Equal("2026-03-08", DailyCycle.Key(At("2026-03-08T07:00:00Z"), zone, 2, 30)); });
Test("DST repeated reset occurs at first instance", () => { var zone = TimeZoneInfo.FindSystemTimeZoneById("America/New_York"); Equal("2026-10-31", DailyCycle.Key(At("2026-11-01T05:29:59Z"), zone, 1, 30)); Equal("2026-11-01", DailyCycle.Key(At("2026-11-01T05:30:00Z"), zone, 1, 30)); Equal("2026-11-01", DailyCycle.Key(At("2026-11-01T06:15:00Z"), zone, 1, 30)); });
Test("local timezone day selection", () => Equal("2026-10-05", DailyCycle.Key(At("2026-10-04T23:00:00Z"), TimeZoneInfo.CreateCustomTimeZone("Plus3", TimeSpan.FromHours(3), "Plus3", "Plus3"), 0, 0)));
Test("invalid config rejected", () => { Throws<RoutineValidationException>(() => (state with { ResetHour = 24 }).Validate()); Throws<RoutineValidationException>(() => (state with { Tasks = [new(id, " ")] }).Validate()); Throws<RoutineValidationException>(() => (state with { Tasks = [new(id, "a"), new(id, "b")] }).Validate()); Throws<RoutineValidationException>(() => (state with { CompletedIds = [Guid.NewGuid()] }).Validate()); });
Test("editing title resets that task only", () => { var repo = new MemoryRepository(state.Complete(id).Complete(second)); var svc = new RoutineService(repo); Equal(true, svc.Configure([new(id, "More water"), new(second, "Stretch")], 0, 0, now, utc)); Equal(false, svc.State.CompletedIds.Contains(id)); Equal(true, svc.State.CompletedIds.Contains(second)); });
Test("saving unchanged preserves completion", () => { var svc = new RoutineService(new MemoryRepository(state.Complete(id))); svc.Configure(state.Tasks, 0, 0, now, utc); Equal(true, svc.State.CompletedIds.Contains(id)); });
Test("no tasks cannot enable", () => { var svc = new RoutineService(new MemoryRepository(state)); Equal(false, svc.Configure([], 0, 0, now, utc)); Equal(true, svc.StorageHealthy); });
Test("install draft persists without activating", () => { var repo = new MemoryRepository(new RoutineState()); var svc = new RoutineService(repo); Equal(true, svc.Configure(state.Tasks, 6, 30, now, utc, enabled: false)); var restarted = new RoutineService(repo); Equal(2, restarted.State.Tasks.Count); Equal(6, restarted.State.ResetHour); Equal(false, restarted.State.ShouldLock); Equal(false, restarted.State.Enabled); });
Test("empty install draft is valid disabled state", () => { var svc = new RoutineService(new MemoryRepository(new RoutineState())); Equal(true, svc.Configure([], 0, 0, now, utc, enabled: false)); Equal(false, svc.State.ShouldLock); });
Test("invalid user input does not disable storage", () => { var svc = new RoutineService(new MemoryRepository(state)); Equal(false, svc.Configure([new(id, " ")], 0, 0, now, utc)); Equal(true, svc.StorageHealthy); Equal(true, svc.Complete(id, now, utc)); });
Test("write failure latches and preserves unsaved state", () => { var repo = new MemoryRepository(state) { FailSave = true }; var svc = new RoutineService(repo); Equal(false, svc.Complete(id, now, utc)); Equal(false, svc.StorageHealthy); Equal(0, svc.State.CompletedIds.Count); repo.FailSave = false; Equal(false, svc.Complete(id, now, utc)); Equal(true, svc.RetryStorage()); Equal(1, svc.ConfigurationRevision); Equal(true, svc.Complete(id, now, utc)); });
Test("read failure leaves corrupt state untouched", () => { var repo = new MemoryRepository(state) { FailLoad = true }; var svc = new RoutineService(repo); Equal(false, svc.StorageHealthy); Equal(false, svc.Persist(new())); Equal(0, repo.SaveCount); Equal(false, svc.RetryStorage()); Equal(0, repo.SaveCount); });
Test("completion after midnight reconciles before checking", () => { var svc = new RoutineService(new MemoryRepository(state.Complete(second))); svc.Complete(id, At("2026-10-05T00:00:00Z"), utc); Equal(true, svc.State.CompletedIds.SetEquals([id])); Equal("2026-10-05", svc.State.CycleKey); });

var folder = Path.Combine(Path.GetTempPath(), $"TaskLock-tests-{Guid.NewGuid():N}");
Directory.CreateDirectory(folder);
Test("atomic repository saves and reloads", () => { var path = Path.Combine(folder, "roundtrip.json"); var repo = new RoutineRepository(path); Equal(false, repo.Load().Enabled); repo.Save(state); repo.Save(state.Complete(id)); var restored = new RoutineRepository(path).Load(); Equal(true, restored.CompletedIds.Contains(id)); Equal(2, restored.Tasks.Count); Equal(0, Directory.GetFiles(folder, ".tasklock-*.tmp").Length); });
Test("corrupt JSON remains byte-for-byte untouched", () => { var path = Path.Combine(folder, "broken.json"); File.WriteAllText(path, "not json"); var svc = new RoutineService(new RoutineRepository(path)); Equal(false, svc.StorageHealthy); svc.RetryStorage(); Equal("not json", File.ReadAllText(path)); });
Test("missing required JSON fields rejected", () => { var path = Path.Combine(folder, "incomplete.json"); File.WriteAllText(path, "{}"); Throws<JsonException>(() => new RoutineRepository(path).Load()); });
Test("bad saved identifiers rejected", () => { var path = Path.Combine(folder, "invalid.json"); File.WriteAllText(path, "{\"tasks\":[],\"completedIds\":[\"11111111-1111-1111-1111-111111111111\"],\"cycleKey\":\"2026-10-04\",\"resetHour\":0,\"resetMinute\":0,\"enabled\":true}"); Throws<RoutineValidationException>(() => new RoutineRepository(path).Load()); });
Test("directory at file path is error, not fresh state", () => { var path = Path.Combine(folder, "directory"); Directory.CreateDirectory(path); var svc = new RoutineService(new RoutineRepository(path)); Equal(false, svc.StorageHealthy); });
Test("write failure does not replace previous bytes", () => { var path = Path.Combine(folder, "invalid-write.json"); var repo = new RoutineRepository(path); repo.Save(state); var bytes = File.ReadAllText(path); Throws<RoutineValidationException>(() => repo.Save(state with { ResetMinute = 60 })); Equal(bytes, File.ReadAllText(path)); });
var rectangle = new GateRect(-1500, 100, -900, 800);
Test("only left click in task region allowed", () => { var p = new PointerPolicy(); Equal(false, p.ShouldBlock(0x201, -1200, 400, [rectangle], true)); Equal(false, p.ShouldBlock(0x202, -1200, 400, [rectangle], true)); Equal(true, p.ShouldBlock(0x201, 100, 100, [rectangle], true)); Equal(true, p.ShouldBlock(0x202, -1200, 400, [rectangle], true)); });
Test("pointer right boundary excludes outside pixel", () => { Equal(false, rectangle.Contains(-900, 400)); Equal(true, rectangle.Contains(-901, 400)); });
Test("foreground other app blocks task-region clicks", () => Equal(true, new PointerPolicy().ShouldBlock(0x201, -1200, 400, [rectangle], false)));
Test("right middle buttons and wheel outside blocked", () => { var p = new PointerPolicy(); foreach (var message in new[] { 0x204, 0x207, 0x20b }) Equal(true, p.ShouldBlock(message, -1200, 400, [rectangle], true)); Equal(true, p.ShouldBlock(0x20a, 0, 0, [rectangle], true)); Equal(false, p.ShouldBlock(0x20a, -1200, 400, [rectangle], true)); });
Test("movement stays free and accepted drag releases", () => { var p = new PointerPolicy(); Equal(false, p.ShouldBlock(0x200, 0, 0, [], false)); p.ShouldBlock(0x201, -1200, 400, [rectangle], true); Equal(false, p.ShouldBlock(0x202, 0, 0, [rectangle], true)); Equal(true, p.ShouldBlock(0x202, 0, 0, [rectangle], true)); });

var failures = 0;
try
{
    foreach (var test in tests)
    {
        try { test.Body(); Console.WriteLine($"PASS {test.Name}"); }
        catch (Exception ex) { failures++; Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}"); }
    }
}
finally { Directory.Delete(folder, true); }
Console.WriteLine($"{tests.Count - failures}/{tests.Count} passed");
return failures == 0 ? 0 : 1;

sealed class MemoryRepository(RoutineState initial) : IRoutineRepository
{
    public bool FailSave { get; set; }
    public bool FailLoad { get; set; }
    public int SaveCount { get; private set; }
    private RoutineState saved = initial;
    public RoutineState Load() => FailLoad ? throw new JsonException("test corrupt data") : saved;
    public void Save(RoutineState state) { if (FailSave) throw new IOException("test disk unavailable"); SaveCount++; saved = state; }
}
