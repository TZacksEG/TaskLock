using TaskLock.Core;

namespace TaskLock.Windows;

internal sealed class SettingsForm : Form
{
    private readonly RoutineService service;
    private readonly DataGridView tasks;
    private readonly DateTimePicker reset;
    private readonly Label status;
    private readonly CheckBox startup;
    private readonly Button save;
    private readonly Button pause;
    private readonly Button retry;
    private readonly Action preview;
    private readonly Action install;
    private readonly Action beforeActivation;
    private int loadedRevision = -1;
    private bool refreshing;
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal string? RuntimeError { get; set; }

    internal SettingsForm(RoutineService service, Action preview, Action install, Action beforeActivation)
    {
        this.service = service; this.preview = preview; this.install = install; this.beforeActivation = beforeActivation;
        Text = "TaskLock · روتينك اليومي"; Icon = Theme.Icon(); Size = new Size(760, 780); MinimumSize = new Size(620, 660);
        StartPosition = FormStartPosition.CenterScreen; BackColor = Theme.Canvas; ForeColor = Color.White;
        Font = new Font("Segoe UI", 11); RightToLeft = RightToLeft.Yes; AutoScaleMode = AutoScaleMode.Dpi;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(28), RowCount = 9, ColumnCount = 1 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var height in new[] { 52, 58, 84, -1, 52, 48, 52, 55, 38 }) layout.RowStyles.Add(new RowStyle(height == -1 ? SizeType.Percent : SizeType.Absolute, height == -1 ? 100 : height));
        var title = Theme.Label("روتينك قبل الكمبيوتر", 26, true);
        var subtitle = Theme.Label("مهام بتعملها بعيد عن الجهاز. أضف مهامك، وجرّب المعاينة أولًا.\nنسخة ويندوز التجريبية 1.1.0-beta.1", 11); subtitle.ForeColor = Theme.Muted; subtitle.Dock = DockStyle.Fill;
        status = Theme.Label("", 11); status.Dock = DockStyle.Fill; status.ForeColor = Theme.Mint;
        tasks = new DataGridView { Dock = DockStyle.Fill, BackgroundColor = Theme.Panel, BorderStyle = BorderStyle.None, RowHeadersVisible = true,
            AllowUserToAddRows = true, AllowUserToDeleteRows = true, AllowUserToResizeRows = false, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            RowTemplate = { Height = 42 }, MultiSelect = false, SelectionMode = DataGridViewSelectionMode.CellSelect, EnableHeadersVisualStyles = false };
        tasks.DefaultCellStyle = new DataGridViewCellStyle { BackColor = Theme.Panel, ForeColor = Color.White, SelectionBackColor = Color.FromArgb(40, 70, 60), SelectionForeColor = Color.White, Padding = new Padding(6), WrapMode = DataGridViewTriState.False };
        tasks.ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle { BackColor = Theme.Canvas, ForeColor = Theme.Mint };
        tasks.Columns.Add(new DataGridViewTextBoxColumn { Name = "title", HeaderText = "المهمة · اكتب في السطر الأخير للإضافة", MaxInputLength = 240, FillWeight = 85 });
        tasks.Columns.Add(new DataGridViewTextBoxColumn { Name = "done", HeaderText = "اليوم", ReadOnly = true, FillWeight = 15 });
        var resetLine = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft };
        var resetLabel = Theme.Label("بداية يوم جديد", 11); resetLabel.Width = 150; resetLabel.Dock = DockStyle.None;
        reset = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "HH:mm", ShowUpDown = true, Width = 100 };
        resetLine.Controls.Add(resetLabel); resetLine.Controls.Add(reset);
        startup = new CheckBox { Text = "يعمل تلقائيًا بعد تسجيل الدخول إلى ويندوز", Dock = DockStyle.Fill, AutoSize = true };
        startup.CheckedChanged += (_, _) =>
        {
            if (refreshing) return;
            try { Startup.SetEnabled(startup.Checked); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or System.Security.SecurityException)
            { MessageBox.Show(this, ex.Message, "TaskLock", MessageBoxButtons.OK, MessageBoxIcon.Information); }
            RefreshStatus();
        };
        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft };
        save = Theme.Button("حفظ وتفعيل القفل", true); save.Click += (_, _) => Save();
        var demo = Theme.Button("معاينة ١٥ ثانية"); demo.Click += (_, _) => this.preview();
        pause = Theme.Button("إيقاف التفعيل"); pause.Click += (_, _) => service.Persist(service.State with { Enabled = false });
        actions.Controls.Add(save); actions.Controls.Add(demo); actions.Controls.Add(pause);
        var utility = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft };
        var installButton = Theme.Button("حفظ مسودة وتثبيت"); installButton.Enabled = !Startup.IsInstalled; installButton.Click += (_, _) => this.install();
        retry = Theme.Button("إعادة محاولة التخزين"); retry.Click += (_, _) => { if (service.RetryStorage()) Reload(); };
        var remove = Theme.Button("حذف المهمة المحددة"); remove.Click += (_, _) => { if (tasks.CurrentRow is { IsNewRow: false } row) tasks.Rows.Remove(row); };
        utility.Controls.Add(installButton); utility.Controls.Add(remove); utility.Controls.Add(retry);
        var foot = Theme.Label("القفل بعد تسجيل الدخول فقط. قائمة TaskLock بجوار الساعة لفتح الإعدادات أو الخروج.", 9); foot.ForeColor = Theme.Muted;
        layout.Controls.Add(title, 0, 0); layout.Controls.Add(subtitle, 0, 1); layout.Controls.Add(status, 0, 2); layout.Controls.Add(tasks, 0, 3);
        layout.Controls.Add(resetLine, 0, 4); layout.Controls.Add(startup, 0, 5); layout.Controls.Add(actions, 0, 6); layout.Controls.Add(utility, 0, 7); layout.Controls.Add(foot, 0, 8);
        Controls.Add(layout); Reload();
    }
    private List<RoutineTask> ReadDraft()
    {
        tasks.EndEdit();
        var entries = new List<RoutineTask>();
        foreach (DataGridViewRow row in tasks.Rows)
        {
            if (row.IsNewRow) continue;
            var title = Convert.ToString(row.Cells[0].Value)?.Trim() ?? "";
            // New, empty rows are ignored. An existing task cannot silently disappear.
            if (title.Length == 0 && row.Tag is null) continue;
            entries.Add(new RoutineTask(row.Tag is Guid id ? id : Guid.NewGuid(), title));
        }
        return entries;
    }
    internal bool SaveInstallationDraft() => service.Configure(ReadDraft(), reset.Value.Hour, reset.Value.Minute, DateTimeOffset.Now, TimeZoneInfo.Local, enabled: false);
    private void Save()
    {
        var entries = ReadDraft();
        beforeActivation();
        if (service.Configure(entries, reset.Value.Hour, reset.Value.Minute, DateTimeOffset.Now, TimeZoneInfo.Local)) Reload();
        else RefreshStatus();
    }
    internal void Reload()
    {
        loadedRevision = service.ConfigurationRevision;
        tasks.Rows.Clear();
        foreach (var task in service.State.Tasks)
        {
            var index = tasks.Rows.Add(task.Title, service.State.CompletedIds.Contains(task.Id) ? "✓" : "○"); tasks.Rows[index].Tag = task.Id;
        }
        reset.Value = DateTime.Today.AddHours(service.State.ResetHour).AddMinutes(service.State.ResetMinute);
        RefreshStatus();
    }
    internal void RefreshStatus()
    {
        if (loadedRevision != service.ConfigurationRevision) { Reload(); return; }
        refreshing = true;
        try { startup.Checked = Startup.Enabled; } catch { startup.Checked = false; }
        refreshing = false;
        status.Text = service.Error ?? RuntimeError ?? (service.State.Enabled ? $"مفعّل · أنجزت {service.State.CompletedIds.Count} من {service.State.Tasks.Count} اليوم" : "أضف مهامك ثم اضغط حفظ وتفعيل القفل.");
        status.ForeColor = service.StorageHealthy && RuntimeError is null ? Theme.Mint : Color.Salmon;
        save.Enabled = service.StorageHealthy; pause.Enabled = service.StorageHealthy && service.State.Enabled; retry.Visible = !service.StorageHealthy;
        foreach (DataGridViewRow row in tasks.Rows) if (row.Tag is Guid id) row.Cells[1].Value = service.State.CompletedIds.Contains(id) ? "✓" : "○";
    }
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
}
