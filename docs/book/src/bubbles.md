# Bubbles

Bubbles are small round status items next to the island, like the music playing or missed notifications. The screen edge has five areas, from left to right: `left`, `center-left`, `center`, `center-right` and `right`. The island sits in one of them, `center` unless the [theme](theme.md) says otherwise.

Each module places its bubbles where it thinks best. Settings › Bubbles shows the five areas side by side with a bubble for each module that has some, a dot on the ones showing now, and the island where it sits. Drag a bubble to sort it within its area or to move it to another area, or drag it to Hidden to stop it showing. Click one for its options: shown or not, with text when its module has a wide view, kept out of a merged shape, and which bubble it shares a pill with. With the keyboard, Tab to a bubble, then use Left and Right to sort it, Shift with Left or Right to move it to the next area, Delete to hide it, and Enter for its options.

The page writes what you arrange to `config.toml`'s `[bubbles]` sections, which you can also edit by hand:

```toml
{{#include ../../../crates/mochi-core/defaults/bubbles.toml}}
```

## Hidden bubbles

Past `max_per_area`, an area leaves out its least important bubbles and shows a "+N" pill with how many. Click it and the island lists them, each drawn as its module draws the bubble, with text when the module has a wide view. Click one to do what a click on the bubble does; the list closes. Escape, a click outside or a second click on "+N" closes it too. The list follows changes while it's open, and closes when the area has room for everything again.

## Merging

An area set to `"merged"` draws one shape around its bubbles instead of a pill for each. Each bubble keeps its own clicks, tooltip and a highlight under the pointer. In notch mode the shape hangs from the edge like the island, with ears at its ends; against the screen's side it meets that side too.

`"island"` merges the area into the island's shape instead of a shape of its own. The island's shape reaches out to the area wherever it is, across the gap to the screen's side too, so `right = "island"` makes one notch, or one floating pill, from the island to the bubbles at the right edge. Bubbles of other areas on the way draw on that shape as well. A panel the island opens grows out of it the way it grows out of the bar.

`merge = false` in a module's `[bubbles.<module>]` keeps its bubbles in pills of their own, beside the shape on the side away from the island.

In bar mode the bar already draws one shape for everything, so merging changes nothing there.

## Stacking

`"stacked"` shows one bubble instead of a row: the most important in front, and up to two more peeking out behind it, smaller, on the side away from the island. Hover the stack and it fans out into the row, each bubble clickable; it folds back a moment after the pointer leaves.

A bubble with news comes to the front for `news_ms`, 4 seconds by default, then goes back behind the most important one. News is a bubble appearing, or a change its module calls news: one more missed notification, another network, a device connecting, the battery turning critical, an app asking for attention in the tray, a reading turning critical. Changes that come all the time, like a timer or the CPU's use, never do. A module marks a showing as news with `BubbleSpec::news()`; a bubble's priority decides which is in front otherwise.

Resting the pointer on a bubble for `tooltip_ms`, 600 milliseconds by default, shows a tooltip beside it with more: the track and the artist, the network and its VPN, the battery's time left, who uses the microphone or the camera, how far a conversion is. `tooltip_ms = 0` turns them off. A module sets one with `BubbleSpec::tooltip(text)`, and a bubble's view can work one out from its payload with a `tooltip` property, which wins.

A stack holds every bubble of its area, so `max_per_area` doesn't apply to it.

Before each area had its own setting, `stack = true` stacked every area. It still stacks the areas `config.toml` doesn't set; an area it sets wins.
