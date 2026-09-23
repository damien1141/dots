use std::time::Instant;

use ratatui::{
    Frame,
    layout::{Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{
        Block, Borders, Cell, Clear, List, ListItem, Padding, Paragraph, Row, Table, Wrap,
    },
};

use crate::app::{App, IndexRow};
use crate::db::{current_totp_code, Entry, Group};
use crate::theme::Theme;
use crate::util::wrap_help_items;

fn help_items(slim_mode: bool) -> &'static [&'static str] {
    if slim_mode {
        &[
            "[↑↓]", "[←→]", "[tab]", "[^k]", "[^u]", "[^p]", "[^t]", "[^r]", "[^o]", "[^a]",
            "[^s]", "[enter]", "[esc]",
        ]
    } else {
        &[
            "[↑↓] navigate",
            "[←] parent [→] enter group",
            "[tab] detail",
            "[^k] palette",
            "[^u] cp_user",
            "[^p] cp_password",
            "[^t] cp_totp",
            "[^r] cp_url",
            "[^o] open_url",
            "[^a] add_entry",
            "[^s] settings",
            "[enter] expand_entry",
            "[esc] quit",
        ]
    }
}

fn masked_password<'a>(entry: &'a Entry, theme: &Theme) -> Line<'a> {
    let normal = Style::new().fg(theme.text);
    let warning = Style::new().fg(theme.warning);

    let mut spans = vec![Span::styled("•••••", normal)];

    if entry.password_reuse_count > 1 {
        spans.push(Span::styled(
            format!(" [{}]", entry.password_reuse_count),
            warning,
        ));
    }

    Line::from(spans)
}

fn masked_user<'a>(entry: &'a Entry, theme: &Theme) -> Line<'a> {
    let normal = Style::new().fg(theme.text);
    let warning = Style::new().fg(theme.warning);

    let mut spans = vec![Span::styled(entry.user.as_str(), normal)];

    if entry.duplicate_user_count > 1 {
        spans.push(Span::styled(
            format!(" [{}]", entry.duplicate_user_count),
            warning,
        ));
    }

    Line::from(spans)
}

fn slim_row<'a>(entry: &'a Entry, theme: &Theme) -> Line<'a> {
    let normal = Style::new().fg(theme.text);
    let warning = Style::new().fg(theme.warning);

    let mut spans = vec![Span::styled(format!("  {}", entry.name), normal)];

    if entry.duplicate_user_count > 1 {
        spans.push(Span::styled(
            format!(" u[{}]", entry.duplicate_user_count),
            warning,
        ));
    }

    if entry.password_reuse_count > 1 {
        spans.push(Span::styled(
            format!(" p[{}]", entry.password_reuse_count),
            warning,
        ));
    }

    Line::from(spans)
}

pub fn draw_index(frame: &mut Frame, app: &mut App) {
    let full_area = frame.area();

    let help_width = full_area.width.saturating_sub(2);
    let help_lines = wrap_help_items(help_items(app.slim_mode), help_width);
    let help_height = help_lines.len() as u16;

    // Always reserve one row for the breadcrumb path so layout indices stay fixed.
    let breadcrumb_height: u16 = 1;

    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(breadcrumb_height),
            Constraint::Fill(1),
            Constraint::Length(1),
            Constraint::Length(help_height),
        ])
        .split(full_area);

    let query_row = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Length(1),
            Constraint::Fill(1),
            Constraint::Length(1),
        ])
        .split(vertical[0]);

    let _query_area = vertical[0];
    let breadcrumb_area = vertical[1];
    let table_area = vertical[2];
    let separator_area = vertical[3];
    let help_area = vertical[4];

    let separator = Block::default()
        .borders(Borders::TOP)
        .border_style(Style::new().fg(app.theme.border));

    frame.render_widget(separator, separator_area);

    // Breadcrumb path
    {
        let path = build_group_path(&app.theme, app.current_group, &app.groups);

        let breadcrumb = Paragraph::new(path)
            .style(Style::new().fg(app.theme.accent))
            .block(
                Block::default()
                    .borders(Borders::BOTTOM)
                    .border_style(Style::new().fg(app.theme.border))
                    .padding(Padding::horizontal(1)),
            );

        frame.render_widget(breadcrumb, breadcrumb_area);
    }

    let help_text = help_lines
        .iter()
        .map(|line| format!("  {line}"))
        .collect::<Vec<_>>()
        .join("\n");

    let help = if let Some(timer) = &app.clipboard_timer {
        let remaining = timer
            .clear_at
            .saturating_duration_since(Instant::now())
            .as_secs()
            + 1;

        Paragraph::new(format!(
            "  Copied {} :: clearing in {remaining}s",
            timer.label
        ))
        .style(Style::new().fg(app.theme.warning))
    } else if let Some(status) = &app.status {
        Paragraph::new(format!("  {status}")).style(Style::new().fg(app.theme.warning))
    } else {
        Paragraph::new(help_text).style(Style::new().fg(app.theme.accent))
    };

    frame.render_widget(help, help_area);

    let groups: Vec<Group> = app.current_child_groups().into_iter().cloned().collect();
    let row_order = app.index_rows();

    let rows = build_rows(
        app.slim_mode,
        &app.theme,
        &row_order,
        &groups,
        &app.entries,
    );

    let column_widths = if app.slim_mode {
        vec![Constraint::Percentage(100)]
    } else {
        vec![
            Constraint::Percentage(30),
            Constraint::Percentage(40),
            Constraint::Percentage(15),
            Constraint::Percentage(15),
        ]
    };

    let mut table_index = Table::new(rows, column_widths)
        .column_spacing(1)
        .style(Style::new().fg(app.theme.text))
        .row_highlight_style(
            Style::new()
                .fg(app.theme.selection_fg)
                .bg(app.theme.selection_bg)
                .bold(),
        );

    if !app.slim_mode {
        table_index = table_index.header(
            Row::new(["  Name", "User", "Password", "Last Modified"])
                .style(Style::new().bold().fg(app.theme.header))
                .bottom_margin(1),
        );
    }

    let _index_area = table_area;

    let detail_entry: Option<Entry> = if app.detail_open {
        app.selected_entry().cloned()
    } else {
        None
    };

    if app.detail_open && table_area.width >= 90 {
        let columns = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(60),
                Constraint::Percentage(40),
            ])
            .split(table_area);

        frame.render_stateful_widget(table_index, columns[0], &mut app.index_state);

        if let Some(entry) = detail_entry.as_ref() {
            draw_entry_detail(frame, columns[1], entry, &app.theme);
        } else {
            draw_empty_detail(frame, columns[1], &app.theme);
        }
    } else {
        frame.render_stateful_widget(table_index, table_area, &mut app.index_state);
    }

    let query_area = query_row[1];

    app.max_len = query_area.width.saturating_sub(4) as usize;

    let input_text = app.query.clone();
    let input_style = Style::default().fg(app.theme.text);

    let input = Paragraph::new(input_text.as_str())
        .style(input_style)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .padding(Padding::horizontal(1))
                .border_style(Style::default().fg(app.theme.border)),
        );

    let cursor_x = query_area
        .x
        .saturating_add(2)
        .saturating_add((input_text.chars().count() as u16).min(query_area.width.saturating_sub(3)));

    frame.set_cursor_position((cursor_x, query_area.y + 1));

    frame.render_widget(input, query_area);

    if app.palette_open {
        draw_palette(frame, app);
    }
}

fn build_group_path<'a>(
    theme: &'a Theme,
    current_group: Option<keepass::db::GroupId>,
    groups: &'a [Group],
) -> Line<'a> {
    let mut names = Vec::new();
    let mut current = current_group;

    while let Some(gid) = current {
        let Some(group) = find_group_by_id(groups, gid) else {
            break;
        };

        names.push(group.name.clone());

        current = group
            .parent_id
            .and_then(|pid| find_group_by_id(groups, pid).map(|_| pid));
    }

    names.reverse();

    let mut spans = vec![
        Span::styled("📁 ", Style::new().fg(theme.accent)),
        Span::styled("Root", Style::new().bold().fg(theme.text)),
    ];

    for name in names {
        spans.push(Span::styled(" / ", Style::new().fg(theme.border)));
        spans.push(Span::styled(name, Style::new().bold().fg(theme.text)));
    }

    Line::from(spans)
}

fn find_group_by_id<'a>(groups: &'a [Group], target_id: keepass::db::GroupId) -> Option<&'a Group> {
    for group in groups {
        if group.id == target_id {
            return Some(group);
        }
        if let Some(found) = find_group_by_id(&group.children, target_id) {
            return Some(found);
        }
    }
    None
}

fn build_rows<'a>(
    slim_mode: bool,
    theme: &'a Theme,
    row_order: &'a [IndexRow],
    groups: &'a [Group],
    entries: &'a [Entry],
) -> Vec<Row<'a>> {
    let mut rows = Vec::new();

    for row in row_order {
        match row {
            IndexRow::Group(group_idx) => {
                let Some(group) = groups.get(*group_idx) else {
                    continue;
                };

                let group_row = if slim_mode {
                    Row::new([Cell::from(Line::from(vec![
                        Span::styled("📁  ", Style::new().fg(theme.accent)),
                        Span::styled(group.name.clone(), Style::new().bold().fg(theme.text)),
                    ]))])
                } else {
                    Row::new([
                        Cell::from(Line::from(vec![
                            Span::styled("📁  ", Style::new().fg(theme.accent)),
                            Span::styled(group.name.clone(), Style::new().bold().fg(theme.text)),
                        ])),
                        Cell::from(""),
                        Cell::from(""),
                        Cell::from(""),
                    ])
                };

                rows.push(group_row);
            }

            IndexRow::Entry(entry_idx) => {
                let Some(entry) = entries.get(*entry_idx) else {
                    continue;
                };

                let password = masked_password(entry, theme);
                let user = masked_user(entry, theme);

                if slim_mode {
                    rows.push(Row::new([Cell::from(slim_row(entry, theme))]));
                } else {
                    rows.push(Row::new([
                        Cell::from(format!("  {}", entry.name)),
                        Cell::from(user),
                        Cell::from(password),
                        Cell::from(entry.date_last_modify.as_str()),
                    ]));
                }
            }
        }
    }

    rows
}

fn draw_palette(frame: &mut Frame, app: &mut App) {
    let area = centered_rect(60, 50, frame.area());

    let items = app.palette_items();

    let list_items: Vec<ListItem> = items
        .iter()
        .map(|(label, _)| ListItem::new(Line::from(label.clone())))
        .collect();

    let title = if app.palette_query.trim().is_empty() {
        " Palette ".to_string()
    } else {
        format!(" Palette: {} ", app.palette_query)
    };

    let list = List::new(list_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::new().fg(app.theme.border))
                .title(title),
        )
        .highlight_style(
            Style::new()
                .fg(app.theme.selection_fg)
                .bg(app.theme.selection_bg)
                .bold(),
        );

    frame.render_widget(Clear, area);
    frame.render_stateful_widget(list, area, &mut app.palette_state);
}

fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(area);

    let horizontal = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(vertical[1]);

    horizontal[1]
}

fn draw_empty_detail(frame: &mut Frame, area: Rect, theme: &Theme) {
    let paragraph = Paragraph::new("select an entry")
        .style(Style::new().fg(theme.border).italic())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::new().fg(theme.border))
                .title(" Detail "),
        );

    frame.render_widget(paragraph, area);
}

fn draw_entry_detail(frame: &mut Frame, area: Rect, entry: &Entry, theme: &Theme) {
    let mut lines: Vec<Line> = Vec::new();

    let label = Style::new().fg(theme.header).bold();
    let normal = Style::new().fg(theme.text);
    let warning = Style::new().fg(theme.warning);
    let placeholder = Style::new().fg(theme.border).italic();

    // Name
    lines.push(Line::from(Span::styled("Name", label)));
    lines.push(Line::from(Span::styled(
        if entry.name.trim().is_empty() {
            "(no title)".to_string()
        } else {
            entry.name.clone()
        },
        normal,
    )));
    lines.push(Line::from(""));

    // User
    lines.push(Line::from(Span::styled("User", label)));
    if entry.user.trim().is_empty() {
        lines.push(Line::from(Span::styled("(empty)", placeholder)));
    } else {
        let mut user_spans = vec![Span::styled(entry.user.clone(), normal)];

        if entry.duplicate_user_count > 1 {
            user_spans.push(Span::styled(
                format!(" [{}]", entry.duplicate_user_count),
                warning,
            ));
        }

        lines.push(Line::from(user_spans));
    }
    lines.push(Line::from(""));

    // Password
    lines.push(Line::from(Span::styled("Password", label)));
    if entry.password.trim().is_empty() {
        lines.push(Line::from(Span::styled("(empty)", placeholder)));
    } else {
        lines.push(Line::from(Span::styled(
            format!("••••• ({} chars)", entry.password.chars().count()),
            normal,
        )));
    }

    if entry.password_reuse_count > 1 {
        lines.push(Line::from(Span::styled(
            format!("warning: password reused {} times", entry.password_reuse_count),
            warning,
        )));
    }
    lines.push(Line::from(""));

    // URL
    lines.push(Line::from(Span::styled("URL", label)));
    if entry.url.trim().is_empty() {
        lines.push(Line::from(Span::styled("(empty)", placeholder)));
    } else {
        lines.push(Line::from(Span::styled(entry.url.clone(), normal)));
    }
    lines.push(Line::from(""));

    // TOTP
    lines.push(Line::from(Span::styled("TOTP", label)));
    if entry.totp.trim().is_empty() {
        lines.push(Line::from(Span::styled("(not set)", placeholder)));
    } else {
        match current_totp_code(&entry.totp) {
            Some(code) => {
                lines.push(Line::from(vec![
                    Span::styled(code.code, normal.bold()),
                    Span::styled(
                        format!("  expires in {}s", code.valid_for.as_secs() + 1),
                        warning,
                    ),
                ]));
            }
            None => {
                lines.push(Line::from(Span::styled(
                    "invalid TOTP value",
                    warning,
                )));
            }
        }
    }
    lines.push(Line::from(""));

    // Last copied
    lines.push(Line::from(Span::styled("Last copied", label)));
    if entry.last_copied == 0 {
        lines.push(Line::from(Span::styled("never", placeholder)));
    } else {
        lines.push(Line::from(Span::styled(
            format!("epoch {}", entry.last_copied),
            normal,
        )));
    }
    lines.push(Line::from(""));

    // Notes
    lines.push(Line::from(Span::styled("Notes", label)));
    if entry.notes.trim().is_empty() {
        lines.push(Line::from(Span::styled("(empty)", placeholder)));
    } else {
        for line in entry.notes.lines() {
            lines.push(Line::from(Span::styled(line.to_string(), normal)));
        }
    }

    // Custom fields
    if !entry.custom_fields.is_empty() {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled("Custom fields", label)));

        for (key, value) in &entry.custom_fields {
            lines.push(Line::from(Span::styled(
                format!("{key} [custom]"),
                label,
            )));

            if value.trim().is_empty() {
                lines.push(Line::from(Span::styled("(empty)", placeholder)));
            } else {
                lines.push(Line::from(Span::styled(value.clone(), normal)));
            }
        }
    }

    let paragraph = Paragraph::new(lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::new().fg(theme.border))
                .title(" Detail "),
        )
        .wrap(Wrap { trim: false });

    frame.render_widget(paragraph, area);
}
