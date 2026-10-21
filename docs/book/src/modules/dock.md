# Dock

A row of app icons in one bubble: the apps you pin, in your order, then the ones running that aren't pinned, in the order they started. An app keeps its place while focus moves between apps. Under each icon there's a dot for each open window, up to three. The app with focus has its dots joined into one pill, the way the workspaces indicator stretches the active workspace.

- A click on an app that isn't running starts it, and the icon dims and brightens until its first window opens.
- A click on a running app focuses the window it used last. If that app already has focus, a click goes to its next window, or minimizes its only one. Hyprland and niri don't minimize windows, so there the click does nothing.
- A middle click starts another window of the app.
- The wheel goes through the app's windows.
- Resting the pointer on an icon shows the app's name, with its window's title or how many windows it has.

The bubble goes in the `left` area unless you move it in Settings › Bubbles. It keeps a pill of its own even in an area that merges its bubbles; turn on Merge in its bubble options, or set `merge = true` under `[bubbles.dock]`, to put it in the shape. For a taskbar along the bottom, set `mode = "bar"` and `anchor = "bottom"` under `[layout]` in `theme.toml`.

The icons fill the bubble's height, which is Layout › Idle height (`idle_height` under `[layout]`): 18 pixels at the default 34, about 40 at 56. Every bubble and the idle island get that height too.

The [launcher module](launcher.md) starts the apps, so it has to be on for the dock to start them. The windows come from wlr-foreign-toplevel-management, which Hyprland, Sway and niri have. Without it, the dock shows the pinned apps only, and still starts them.

The dock is off by default. Turn it on in Settings › Modules, or add `"dock"` to `modules` in `config.toml`.

```toml
{{#include ../../../../modules/dock/settings.toml}}
```

| Action | What it does |
|---|---|
| `mochi ipc dock activate <app> [monitor]` | What a click does. `<app>` is the desktop id without `.desktop`, like `firefox`. The monitor counts only with `per_monitor` |
| `mochi ipc dock launch <app>` | Starts another window of the app |
| `mochi ipc dock cycle <app> next\|previous [monitor]` | Focuses the app's next or previous window |
