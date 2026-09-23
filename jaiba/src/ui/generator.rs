use ratatui::{
    Frame,
    layout::Margin,
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Wrap},
};
use crate::app::App;
use crate::generator::GeneratorMode;

pub fn draw_generator(frame: &mut Frame, app: &mut App) {
    let area = frame.area().inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

    let theme = &app.theme;

    let header = Style::new().fg(theme.header).bold();
    let normal = Style::new().fg(theme.text);
    let accent = Style::new().fg(theme.accent);

    let mode_label = match app.generator_mode {
        GeneratorMode::Random => "random",
        GeneratorMode::Passphrase => "passphrase",
        GeneratorMode::Pin => "pin",
        GeneratorMode::Hex => "hex",
    };

    let mut lines: Vec<Line> = Vec::new();

    lines.push(Line::from(Span::styled("Password generator", header)));
    lines.push(Line::from(""));

    lines.push(Line::from(vec![
        Span::styled("Mode: ", header),
        Span::styled(format!("{mode_label}  [tab]"), normal),
    ]));

    match app.generator_mode {
        GeneratorMode::Passphrase => {
            lines.push(Line::from(vec![
                Span::styled("Words: ", header),
                Span::styled(format!("{}  [↑/↓]", app.generator_words), normal),
            ]));
        }
        _ => {
            lines.push(Line::from(vec![
                Span::styled("Length: ", header),
                Span::styled(format!("{}  [↑/↓]", app.generator_length), normal),
            ]));
        }
    }

    if app.generator_mode == GeneratorMode::Random {
        lines.push(Line::from(format!(
            "[u] upper: {}  [d] digits: {}  [s] symbols: {}  [a] exclude ambiguous: {}",
            on(app.generator_use_upper),
            on(app.generator_use_digits),
            on(app.generator_use_symbols),
            on(app.generator_exclude_ambiguous),
        )));
    }

    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled("Result", header)));

    let width = area.width.saturating_sub(4) as usize;
    for chunk in chunk_value(&app.generator_result, width) {
        lines.push(Line::from(Span::styled(chunk, normal.bold())));
    }

    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        "[enter] use  [y] copy  [g] regenerate  [esc] cancel",
        accent,
    )));

    let paragraph = Paragraph::new(lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::new().fg(theme.border))
                .title(" Generator "),
        )
        .wrap(Wrap { trim: false });

    frame.render_widget(paragraph, area);
}

fn on(value: bool) -> &'static str {
    if value {
        "on"
    } else {
        "off"
    }
}

fn chunk_value(value: &str, width: usize) -> Vec<String> {
    let width = width.max(1);
    let mut out = Vec::new();
    let mut current = String::new();
    let mut current_len = 0usize;

    for c in value.chars() {
        current.push(c);
        current_len += 1;

        if current_len >= width {
            out.push(std::mem::take(&mut current));
            current_len = 0;
        }
    }

    if !current.is_empty() || out.is_empty() {
        out.push(current);
    }

    out
}
