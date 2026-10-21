//! Dock: the pinned apps and the running ones as a row of icons in one
//! bubble, with a line between them and a button that opens the launcher.
//! A click starts an app, focuses its window, or goes to its next window;
//! a middle click starts another one; the wheel goes through its windows.
//! Under each icon, a dot for each open window.
//!
//! Windows come from wlr-foreign-toplevel-management. Without it, the dock
//! shows the pinned apps only, and starts them.
//!
//! Settings in `config.toml`, all optional:
//!
//! ```toml
//! [module.dock]
//! pinned = ["firefox", "org.gnome.Nautilus"]
//! running = true      # the running apps that aren't pinned too
//! per_monitor = false # each monitor's dock shows its own windows only
//! separator = true   # a line between the pinned apps and the others
//! show_apps = "end"   # a button that opens the launcher: "start", "end" or "off"
//! ```

mod apps;

use std::collections::HashSet;

use include_dir::{Dir, include_dir};
use mochi_core::compositor::{Compositor, Toplevel};
use mochi_core::desktop::{self, App, Locale};
use mochi_core::{
    ActionSpec, Area, ArgSpec, Assets, BoxFuture, BubbleHome, BubbleId, BubbleSpec, CallError,
    Module, ModuleCommand, ModuleCtx, ModuleError, ModuleEvent,
};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::apps::{Entry, Step};

static QML: Dir = include_dir!("$CARGO_MANIFEST_DIR/qml");

/// The left end, where a taskbar starts, in a pill of its own even where
/// the area merges its bubbles: one row of icons reads as a dock.
const BUBBLES: BubbleHome = BubbleHome::new(Area::Left).apart();

#[derive(Debug, Default)]
pub struct Dock;

#[derive(Debug, Deserialize, PartialEq, schemars::JsonSchema)]
#[serde(default, deny_unknown_fields)]
struct Settings {
    #[schemars(extend("x-source" = "app"))]
    pinned: Vec<String>,
    running: bool,
    per_monitor: bool,
    separator: bool,
    show_apps: ShowApps,
}

/// Where the button that opens the launcher goes, as GNOME's dash has one.
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
enum ShowApps {
    Start,
    #[default]
    End,
    Off,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            pinned: Vec::new(),
            running: true,
            per_monitor: false,
            separator: true,
            show_apps: ShowApps::End,
        }
    }
}

impl Module for Dock {
    fn id(&self) -> &'static str {
        "dock"
    }

    fn assets(&self) -> Assets {
        Assets::new(&QML, concat!(env!("CARGO_MANIFEST_DIR"), "/qml"))
    }

    fn settings_example(&self) -> &'static str {
        include_str!("../settings.toml")
    }

    fn settings_schema(&self) -> Option<serde_json::Value> {
        Some(mochi_core::options::schema_of::<Settings>())
    }

    fn check_settings(&self, table: &mochi_core::toml::Table) -> Result<(), String> {
        mochi_core::settings::<Settings>(table)
            .map(drop)
            .map_err(|error| error.to_string())
    }

    fn bubbles(&self) -> Option<BubbleHome> {
        Some(BUBBLES)
    }

    fn actions(&self) -> Vec<ActionSpec> {
        let key = || ArgSpec::string("app", "The app's desktop id without .desktop, like firefox");
        let output = || {
            ArgSpec::string("output", "The monitor whose dock it is, for per_monitor")
                .optional()
                .source("output")
        };
        vec![
            ActionSpec::new(
                "activate",
                "Do what a click on an app does: start it, focus it, or go to its next window",
            )
            .arg(key())
            .arg(output()),
            ActionSpec::new("launch", "Start another one of an app").arg(key()),
            ActionSpec::new("cycle", "Focus an app's next or previous window")
                .arg(key())
                .arg(ArgSpec::choice(
                    "direction",
                    "Which way",
                    ["next", "previous"],
                ))
                .arg(output()),
        ]
    }

    fn run(self: Box<Self>, mut ctx: ModuleCtx) -> BoxFuture<'static, Result<(), ModuleError>> {
        Box::pin(async move {
            let settings: Settings = ctx.settings()?;
            let compositor = ctx.compositor().clone();
            let mut toplevels = compositor.subscribe_toplevels();
            let mut watching = true;
            let mut dock = State {
                apps: read_apps().await,
                missed: HashSet::new(),
                order: Vec::new(),
                shown: Vec::new(),
                bubble: None,
            };
            let windows = toplevels.borrow_and_update().clone();
            dock.refresh(&ctx, &settings, &windows).await;

            loop {
                tokio::select! {
                    event = ctx.next_event() => match event {
                        None => return Ok(()),
                        Some(ModuleEvent::Command(command)) => {
                            dock.command(&ctx, &compositor, &settings, command);
                        }
                        Some(_) => {}
                    },
                    changed = toplevels.changed(), if watching => {
                        if changed.is_err() {
                            // No windows from the compositor: the pins stay.
                            watching = false;
                            continue;
                        }
                        let windows = toplevels.borrow_and_update().clone();
                        dock.refresh(&ctx, &settings, &windows).await;
                    }
                }
            }
        })
    }
}

struct State {
    apps: Vec<App>,
    /// App ids no desktop entry claimed, after reading them again.
    missed: HashSet<String>,
    /// The running apps' order; see [`apps::entries`].
    order: Vec<String>,
    shown: Vec<Entry>,
    bubble: Option<BubbleId>,
}

impl State {
    async fn refresh(&mut self, ctx: &ModuleCtx, settings: &Settings, windows: &[Toplevel]) {
        // An app installed since the last look isn't known yet.
        let unknown: Vec<String> = windows
            .iter()
            .map(|window| window.app_id.clone())
            .filter(|app_id| {
                !app_id.is_empty()
                    && !self.missed.contains(app_id)
                    && desktop::find(&self.apps, &[app_id]).is_none()
            })
            .collect();
        if !unknown.is_empty() {
            self.apps = read_apps().await;
            self.missed.extend(unknown);
        }
        let shown = apps::entries(
            &settings.pinned,
            settings.running,
            &self.apps,
            windows,
            &mut self.order,
        );
        if shown == self.shown && self.bubble.is_some() {
            return;
        }
        self.shown = shown;
        // The launcher's button keeps the dock up with no apps in it.
        if self.shown.is_empty() && settings.show_apps == ShowApps::Off {
            if let Some(bubble) = self.bubble.take() {
                ctx.hide_bubble(bubble);
            }
            return;
        }
        let payload = json!({
            "apps": self.shown,
            "per_monitor": settings.per_monitor,
            "separator": settings.separator,
            "show_apps": settings.show_apps,
        });
        match self.bubble {
            Some(bubble) => ctx.update_bubble(bubble, payload),
            None => {
                let spec = BubbleSpec::new("Dock")
                    .key("dock")
                    .at(&BUBBLES)
                    .payload(payload);
                self.bubble = Some(ctx.show_bubble(spec));
            }
        }
    }

    fn command(
        &self,
        ctx: &ModuleCtx,
        compositor: &Compositor,
        settings: &Settings,
        command: ModuleCommand,
    ) {
        let key = command.args.str("app").unwrap_or_default().to_owned();
        let Some(entry) = self.shown.iter().find(|entry| entry.key == key) else {
            command.reply(Err(format!("no app {key} in the dock")));
            return;
        };
        // Without per_monitor, every monitor's dock is the same.
        let output = command
            .args
            .str("output")
            .filter(|_| settings.per_monitor)
            .map(str::to_owned);
        let output = output.as_deref();
        let action = command.action.clone();
        let step = match action.as_str() {
            "activate" => entry.click(output),
            "launch" => entry.desktop.clone().map(Step::Launch),
            "cycle" => {
                let by = if command.args.str("direction") == Some("previous") {
                    -1
                } else {
                    1
                };
                entry.cycle(output, by).map(Step::Focus)
            }
            other => {
                command.reply(Err(format!("dock has no action {other}")));
                return;
            }
        };
        let result = match step {
            None if entry.windows.is_empty() || action == "launch" => Err(format!(
                "{} has no desktop entry to start it from",
                entry.name
            )),
            None => Ok(()),
            Some(Step::Focus(window)) => compositor
                .activate_toplevel(window)
                .map_err(|error| error.to_string()),
            Some(Step::Minimize(window)) => compositor
                .minimize_toplevel(window)
                .map_err(|error| error.to_string()),
            Some(Step::Launch(desktop)) => {
                let launched = ctx.call("launcher", "launch", &[&desktop]);
                // The launcher may take a moment: the dock goes on meanwhile.
                tokio::spawn(async move {
                    command.reply(launched.await.map_err(|error| match error {
                        CallError::NotEnabled(_) => {
                            "the launcher module starts apps: turn it on to start them from the dock"
                                .to_owned()
                        }
                        error => error.to_string(),
                    }));
                });
                return;
            }
        };
        command.reply(result);
    }
}

async fn read_apps() -> Vec<App> {
    let desktops = desktop::current_desktops();
    let directories = desktop::directories();
    tokio::task::spawn_blocking(move || desktop::scan(&directories, &Locale::from_env(), &desktops))
        .await
        .unwrap_or_default()
}
