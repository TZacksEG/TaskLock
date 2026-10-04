using TaskLock.Core;

namespace TaskLock.Windows;

internal sealed class LockForm : Form
{
    private readonly TableLayoutPanel card;
    private readonly FlowLayoutPanel list;
    private readonly Label count;
    private readonly Label note;
    private bool canClose;
    internal event Action? InteractiveRegionChanged;
    internal GateRect InteractiveRegion
    {
        get { var r = list.RectangleToScreen(list.ClientRectangle); return new(r.Left, r.Top, r.Right, r.Bottom); }
    }
    internal LockForm(Screen screen, RoutineState state, bool preview, Action<Guid> complete)
    {
        Text = "TaskLock — مهام اليوم"; Icon = Theme.Icon(); FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual; Bounds = screen.Bounds; TopMost = true; ShowInTaskbar = false;
        BackColor = Theme.Canvas; ForeColor = Color.White; RightToLeft = RightToLeft.Yes; AutoScaleMode = AutoScaleMode.Dpi;
        var logo = Theme.Label("TASKLOCK   ✓", 12, true); logo.TextAlign = ContentAlignment.MiddleCenter; logo.ForeColor = Theme.Mint; logo.Height = 70;
        Controls.Add(logo);
        card = new TableLayoutPanel { ColumnCount = 1, RowCount = 6, BackColor = Theme.Canvas };
        card.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        card.RowStyles.Add(new RowStyle(SizeType.Absolute, 42)); card.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
        card.RowStyles.Add(new RowStyle(SizeType.Absolute, 50)); card.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        card.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); card.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        note = Theme.Label(preview ? "معاينة مؤقتة · ١٥ ثانية" : DateTime.Now.ToString("dddd, dd MMMM")); note.ForeColor = Theme.Mint; note.TextAlign = ContentAlignment.MiddleCenter;
        var title = Theme.Label("وقتك لنفسك أولًا", 30, true); title.TextAlign = ContentAlignment.MiddleCenter;
        var subtitle = Theme.Label("خلّص روتينك، وبعدها الكمبيوتر جاهز لك.", 13); subtitle.ForeColor = Theme.Muted; subtitle.TextAlign = ContentAlignment.MiddleCenter;
        count = Theme.Label("", 12, true); count.ForeColor = Theme.Mint; count.TextAlign = ContentAlignment.MiddleCenter;
        list = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, BackColor = Theme.Canvas, Padding = new Padding(4) };
        foreach (var task in state.Tasks)
        {
            var button = Theme.Button(task.Title); button.AutoSize = false; button.Height = 68; button.TextAlign = ContentAlignment.MiddleRight;
            button.Tag = task; button.Margin = new Padding(2, 5, 2, 5); button.Click += (_, _) => complete(task.Id);
            list.Controls.Add(button);
        }
        var footer = Theme.Label(preview ? "المعاينة تنتهي تلقائيًا · مهام تجريبية فقط" : "التقدم محفوظ · تفتح الشاشة بعد إكمال المهام", 10); footer.ForeColor = Theme.Muted; footer.TextAlign = ContentAlignment.MiddleCenter;
        card.Controls.Add(note, 0, 0); card.Controls.Add(title, 0, 1); card.Controls.Add(subtitle, 0, 2); card.Controls.Add(count, 0, 3); card.Controls.Add(list, 0, 4); card.Controls.Add(footer, 0, 5);
        Controls.Add(card);
        Resize += (_, _) => LayoutCard(); Shown += (_, _) => LayoutCard(); list.Resize += (_, _) => ResizeButtons();
        UpdateState(state);
    }
    private void LayoutCard()
    {
        var scale = DeviceDpi / 96f;
        card.Size = new Size(Math.Min((int)(590 * scale), Math.Max(280, ClientSize.Width - 60)), Math.Min((int)(640 * scale), Math.Max(300, ClientSize.Height - 130)));
        card.Location = new Point((ClientSize.Width - card.Width) / 2, (ClientSize.Height - card.Height) / 2);
        ResizeButtons(); InteractiveRegionChanged?.Invoke();
    }
    private void ResizeButtons()
    {
        foreach (Control button in list.Controls) button.Width = Math.Max(160, list.ClientSize.Width - SystemInformation.VerticalScrollBarWidth - 16);
        InteractiveRegionChanged?.Invoke();
    }
    internal void UpdateState(RoutineState state)
    {
        count.Text = $"{state.Tasks.Count(t => state.CompletedIds.Contains(t.Id))} / {state.Tasks.Count}";
        foreach (Button button in list.Controls)
        {
            var task = (RoutineTask)button.Tag!; var done = state.CompletedIds.Contains(task.Id);
            button.Text = $"{(done ? "✓" : "○")}   {task.Title}"; button.Enabled = !done;
            button.ForeColor = done ? Theme.Muted : Color.White;
        }
    }
    internal void UpdateCountdown(int seconds) => note.Text = $"معاينة مؤقتة · {seconds} ثانية";
    internal void Release() { canClose = true; Close(); Dispose(); }
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!canClose && e.CloseReason is CloseReason.UserClosing or CloseReason.FormOwnerClosing) e.Cancel = true;
        base.OnFormClosing(e);
    }
}
