//! What the dock shows: the pinned apps, then the running ones, each with
//! its open windows, and what a click on one does.

use std::collections::BTreeMap;

use mochi_core::compositor::Toplevel;
use mochi_core::desktop::{self, App};
use serde::Serialize;

/// One icon in the dock.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Entry {
    /// The desktop id without `.desktop`, or the window's app id when no
    /// desktop entry claims it.
    pub key: String,
    pub name: String,
    /// A theme icon's name or a picture's path.
    pub icon: String,
    /// What the launcher's `launch` takes; none for a window without a
    /// desktop entry, which can't be started again.
    pub desktop: Option<String>,
    pub pinned: bool,
    /// Its windows in the order they opened.
    pub windows: Vec<Window>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Window {
    pub id: u32,
    pub title: String,
    pub focused: bool,
    pub minimized: bool,
    pub outputs: Vec<String>,
    /// Its place in the focus order, 0 for the one focused last.
    #[serde(skip)]
    pub recent: usize,
}

fn key_of(app: &App) -> String {
    app.id
        .strip_suffix(".desktop")
        .unwrap_or(&app.id)
        .to_owned()
}

/// The pinned app with this id, with or without `.desktop`, or else the one
/// it names the way a window's app id does.
fn pinned_app<'a>(apps: &'a [App], pin: &str) -> Option<&'a App> {
    let id = format!("{}.desktop", pin.strip_suffix(".desktop").unwrap_or(pin));
    apps.iter()
        .find(|app| app.id == id)
        .or_else(|| desktop::find(apps, &[pin]))
}

/// A running app's windows and the entry they belong to.
struct Group<'a> {
    app: Option<&'a App>,
    app_id: String,
    windows: Vec<Window>,
}

/// The dock's icons: the pinned apps in their order, then, with `running`,
/// the other apps with windows open, in the order they started. `order`
/// keeps that order from one call to the next, so an app keeps its place
/// while focus moves.
pub fn entries(
    pinned: &[String],
    running: bool,
    apps: &[App],
    toplevels: &[Toplevel],
    order: &mut Vec<String>,
) -> Vec<Entry> {
    let mut groups: BTreeMap<String, Group> = BTreeMap::new();
    for (recent, toplevel) in toplevels.iter().enumerate() {
        let app = desktop::find(apps, &[&toplevel.app_id]);
        let key = match app {
            Some(app) => key_of(app),
            None if toplevel.app_id.is_empty() => format!("window-{}", toplevel.id),
            None => toplevel.app_id.to_lowercase(),
        };
        let group = groups.entry(key).or_insert_with(|| Group {
            app,
            app_id: toplevel.app_id.clone(),
            windows: Vec::new(),
        });
        group.windows.push(Window {
            id: toplevel.id,
            title: toplevel.title.clone(),
            focused: toplevel.focused,
            minimized: toplevel.minimized,
            outputs: toplevel.outputs.clone(),
            recent,
        });
    }
    for group in groups.values_mut() {
        group.windows.sort_by_key(|window| window.id);
    }

    let mut shown = Vec::new();
    for pin in pinned {
        let app = pinned_app(apps, pin);
        let key = app.map_or_else(|| pin.clone(), key_of);
        if shown.iter().any(|entry: &Entry| entry.key == key) {
            continue;
        }
        let windows = groups
            .remove(&key)
            .map(|group| group.windows)
            .unwrap_or_default();
        shown.push(Entry {
            name: app.map_or_else(|| pin.clone(), |app| app.name.clone()),
            icon: app.and_then(|app| app.icon.clone()).unwrap_or(key.clone()),
            desktop: app.map(|app| app.id.clone()),
            pinned: true,
            windows,
            key,
        });
    }

    // Apps keep their place; new ones go after, the one opened first first.
    order.retain(|key| groups.contains_key(key));
    let mut new: Vec<(&String, u32)> = groups
        .iter()
        .filter(|(key, _)| !order.contains(key))
        .map(|(key, group)| (key, group.windows[0].id))
        .collect();
    new.sort_by_key(|(_, first)| *first);
    order.extend(new.into_iter().map(|(key, _)| key.clone()));
    if !running {
        return shown;
    }
    for key in order.iter() {
        let Some(group) = groups.remove(key) else {
            continue;
        };
        let title = group.windows[0].title.clone();
        let name = match group.app {
            Some(app) => app.name.clone(),
            None if group.app_id.is_empty() => title,
            None => group.app_id.clone(),
        };
        shown.push(Entry {
            key: key.clone(),
            name,
            icon: group
                .app
                .and_then(|app| app.icon.clone())
                .unwrap_or(group.app_id),
            desktop: group.app.map(|app| app.id.clone()),
            pinned: false,
            windows: group.windows,
        });
    }
    shown
}

/// What a click on an icon does.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    /// Start the app, by desktop id.
    Launch(String),
    Focus(u32),
    Minimize(u32),
}

impl Entry {
    /// Its windows on `output`, or all of them without one.
    fn windows_on(&self, output: Option<&str>) -> Vec<&Window> {
        self.windows
            .iter()
            .filter(|window| {
                output.is_none_or(|output| window.outputs.iter().any(|on| on == output))
            })
            .collect()
    }

    /// A click: start the app when it has no window; focus the window it
    /// used last; minimize its only window when that one has focus; with
    /// several, go to the next.
    pub fn click(&self, output: Option<&str>) -> Option<Step> {
        let windows = self.windows_on(output);
        if windows.is_empty() {
            return self.desktop.clone().map(Step::Launch);
        }
        if let Some(focused) = windows.iter().find(|window| window.focused) {
            if windows.len() == 1 {
                return Some(Step::Minimize(focused.id));
            }
            return self.cycle(output, 1).map(Step::Focus);
        }
        windows
            .iter()
            .min_by_key(|window| window.recent)
            .map(|window| Step::Focus(window.id))
    }

    /// The window `by` steps from the focused one, in the order they
    /// opened, wrapping around: the first or the last when none has focus.
    pub fn cycle(&self, output: Option<&str>, by: i32) -> Option<u32> {
        let windows = self.windows_on(output);
        let count = windows.len() as i32;
        if count == 0 {
            return None;
        }
        let next = match windows.iter().position(|window| window.focused) {
            Some(at) => (at as i32 + by).rem_euclid(count),
            None if by > 0 => 0,
            None => count - 1,
        };
        Some(windows[next as usize].id)
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn app(id: &str, name: &str, wm_class: Option<&str>) -> App {
        App {
            id: format!("{id}.desktop"),
            name: name.into(),
            generic: None,
            comment: None,
            icon: Some(id.into()),
            exec: id.into(),
            terminal: false,
            keywords: Vec::new(),
            path: None,
            wm_class: wm_class.map(str::to_owned),
            actions: Vec::new(),
            file: PathBuf::from(format!("/apps/{id}.desktop")),
        }
    }

    fn window(id: u32, app_id: &str, focused: bool) -> Toplevel {
        Toplevel {
            id,
            title: format!("{app_id} {id}"),
            app_id: app_id.into(),
            focused,
            minimized: false,
            outputs: vec!["DP-1".into()],
        }
    }

    fn apps() -> Vec<App> {
        vec![
            app("firefox", "Firefox", None),
            app("com.obsproject.Studio", "OBS Studio", Some("obs")),
            app("kitty", "kitty", None),
        ]
    }

    fn keys(entries: &[Entry]) -> Vec<&str> {
        entries.iter().map(|entry| entry.key.as_str()).collect()
    }

    #[test]
    fn pinned_apps_come_first_and_running_ones_keep_their_place() {
        let pinned = vec!["firefox".to_owned(), "com.obsproject.Studio".to_owned()];
        let mut order = Vec::new();
        let open = [
            window(7, "kitty", true),
            window(5, "obs", false),
            window(9, "spotify", false),
        ];
        let shown = entries(&pinned, true, &apps(), &open, &mut order);
        assert_eq!(
            keys(&shown),
            ["firefox", "com.obsproject.Studio", "kitty", "spotify"]
        );
        assert!(shown[0].windows.is_empty());
        assert_eq!(shown[1].windows[0].id, 5);
        // An app without a desktop entry still shows, by its app id.
        assert_eq!(shown[3].name, "spotify");
        assert_eq!(shown[3].desktop, None);

        // Focus moving to spotify doesn't move it ahead of kitty.
        let open = [
            window(9, "spotify", true),
            window(7, "kitty", false),
            window(5, "obs", false),
        ];
        let shown = entries(&pinned, true, &apps(), &open, &mut order);
        assert_eq!(
            keys(&shown),
            ["firefox", "com.obsproject.Studio", "kitty", "spotify"]
        );

        // Without `running`, only the pins.
        let shown = entries(&pinned, false, &apps(), &open, &mut order);
        assert_eq!(keys(&shown), ["firefox", "com.obsproject.Studio"]);
    }

    #[test]
    fn a_click_starts_focuses_minimizes_or_moves_on() {
        let pinned = vec!["firefox".to_owned(), "kitty".to_owned()];
        let mut order = Vec::new();
        let open = [
            window(3, "kitty", true),
            window(8, "kitty", false),
            window(4, "firefox", false),
        ];
        let shown = entries(&pinned, true, &apps(), &open, &mut order);
        let (firefox, kitty) = (&shown[0], &shown[1]);
        assert_eq!(firefox.click(None), Some(Step::Focus(4)));
        // kitty has focus with two windows: the next one.
        assert_eq!(kitty.click(None), Some(Step::Focus(8)));
        assert_eq!(kitty.cycle(None, -1), Some(8));
        // Only firefox's window on another monitor: this one starts it.
        assert_eq!(
            firefox.click(Some("HDMI-A-1")),
            Some(Step::Launch("firefox.desktop".into()))
        );

        let open = [window(4, "firefox", true)];
        let shown = entries(&pinned, true, &apps(), &open, &mut order);
        assert_eq!(shown[0].click(None), Some(Step::Minimize(4)));
        assert_eq!(
            shown[1].click(None),
            Some(Step::Launch("kitty.desktop".into()))
        );
    }
}
