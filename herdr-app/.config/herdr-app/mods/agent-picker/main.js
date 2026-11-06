// Agent picker: every running agent in one list; Enter jumps to it. A port of
// the TUI herdr `prefix a` fzf popup (bin/bin/herdr-agent-picker).
//
// Vim modes, same as that popup and mods/vim-picker:
//   NORMAL (opens here): j/k move, g/G top/bottom, ctrl-d/ctrl-u half page,
//     enter focuses, / or i searches, esc closes.
//   INSERT (the filter box): type to filter, ctrl-j/ctrl-k move, enter
//     focuses, esc back to NORMAL.
//
// Only rows that want something from you get colour (blocked, idle, done);
// working rows recede to grey so the live ones pop. The colours are the theme's
// status colours, which themes/conductor.json sets to the old picker's values.
//
// clean() and icon() are adapted from Herdr.app's shipped `agents` mod, and the
// layout follows its `picker` mod (Apache License 2.0, v0.1.13).

import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { agents, panes, run, theme, props, closeOverlay, home } from "herdr";

const ROW = 34;
const VISIBLE = 12; // rows shown before the list scrolls
const WANTS = new Set(["blocked", "idle", "done"]);
// Agents prefix their titles with spinner glyphs ("✳ Fix login"); drop them.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();

// The agent's icon from the app's program table (the same one the Agents
// sidebar draws): a one-color glyph tinted with `color`, or a picture.
function icon(p, size, color) {
  if (!p?.icon) return div().w(size).flex_none();
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

export default class AgentPicker extends View {
  init(_props, cx) {
    this.filter = "";
    this.mode = "normal";
    this.at = null;
    this.top = 0;
    this.wheel = 0;
    this.input = InputState.new({ placeholder: "Filter agents…" });
    this.input.on("change", (_e, cx) => {
      this.filter = this.input.value();
      this.at = 0;
      cx.notify();
    });
    this.input.on("submit", () => this.go(this.rows()[this.at]));
    // Escape is the app's: it closes the popup before on_key_down sees it. A
    // key binding in our own context sits deeper and wins (the shipped win98
    // menu does the same).
    try {
      cx.bind_keys([{ keystroke: "escape", action: "agent_picker_escape", context: "AgentPicker" }]);
    } catch {}
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(600, () => (this.mode === "normal" ? this.handle : this.input).focus());
  }

  close() {
    closeOverlay(props().overlay);
  }

  go(r) {
    if (!r) return;
    this.close();
    run("agent.focus", { terminal: r.address });
  }

  rows() {
    const h = home();
    const cwd = new Map(panes().map((p) => [p.pane, p.cwd]));
    const f = this.filter.toLowerCase();
    return agents()
      .map((a) => {
        let dir = cwd.get(a.pane) ?? "";
        if (h && dir.startsWith(h)) dir = "~" + dir.slice(h.length);
        return {
          address: a.address,
          status: a.status,
          focused: a.focused,
          program: a.program,
          title: clean(a.title) || a.program?.name || "agent",
          where: [a.space_name, dir].filter(Boolean).join(" · "),
        };
      })
      .filter((r) => !f || [r.title, r.where, r.status].join(" ").toLowerCase().includes(f));
  }

  render() {
    const t = theme();
    const rows = this.rows();
    const n = rows.length;
    const normal = this.mode === "normal";
    // Opens on the agent you're in.
    if (this.at === null) this.at = Math.max(0, rows.findIndex((r) => r.focused));
    this.at = Math.max(0, Math.min(this.at, n - 1));
    const vis = Math.min(VISIBLE, n);
    if (this.at < this.top) this.top = this.at;
    if (this.at >= this.top + vis) this.top = this.at - vis + 1;
    this.top = Math.max(0, Math.min(this.top, n - vis));
    const half = Math.max(1, Math.floor(VISIBLE / 2));
    const move = (d) => (this.at = Math.max(0, Math.min(n - 1, this.at + d)));

    const row = (r, i) => {
      const on = i === this.at;
      const wants = WANTS.has(r.status);
      const sc = wants ? t[r.status] : t.dim;
      return h_flex()
        .id(`ap-${r.address}`)
        .h(ROW)
        .mx(4)
        .px(10)
        .gap(10)
        .items_center()
        .rounded(7)
        .cursor_pointer()
        .when(on, (el) => el.bg(t.hover))
        .hover((s) => s.bg(t.hover))
        .on_click(() => this.go(r))
        .child(div().w(12).flex_none().text_color(sc).child(r.focused ? "●" : "○"))
        .child(div().w(64).flex_none().text_size(12).text_color(sc).when(r.status === "blocked", (d) => d.font_bold()).child(r.status))
        .child(icon(r.program, 16, wants ? t.foreground : t.muted))
        .child(div().flex_1().truncate().text_color(wants ? t.foreground : t.muted).when(r.focused, (d) => d.font_semibold()).child(r.title))
        .child(div().max_w(280).truncate().text_size(11.5).text_color(t.dim).child(r.where));
    };

    return v_flex()
      .id("agent-picker")
      .key_context("AgentPicker")
      .on_action("agent_picker_escape", (_e, cx) => {
        if (this.mode === "normal") return this.close();
        this.mode = "normal";
        this.handle.focus();
        cx.notify();
      })
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(18)
      .gap(10)
      .bg(t.popover)
      .text_size(13)
      .on_key_down((e, cx) => {
        const k = e.key;
        const ks = e.keystroke;
        if (k === "down" || ks === "ctrl-j" || (normal && ks === "j")) move(1);
        else if (k === "up" || ks === "ctrl-k" || (normal && ks === "k")) move(-1);
        else if (normal && ks === "ctrl-d") move(half);
        else if (normal && ks === "ctrl-u") move(-half);
        else if (normal && ks === "g") this.at = 0;
        else if (normal && (ks === "shift-g" || ks === "G")) this.at = n - 1;
        else if (normal && k === "enter") return this.go(rows[this.at]);
        else if (normal && (ks === "/" || ks === "i")) {
          this.mode = "insert";
          this.input.focus();
        } else return;
        cx.stop_propagation();
        cx.notify();
      })
      .child(
        h_flex()
          .items_center()
          .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Agents"))
          .child(div().text_size(11).text_color(t.dim).child(normal ? "NORMAL  j/k  g/G  / search  enter  Esc" : "INSERT  ctrl-j/k  enter  Esc normal")),
      )
      .child(
        h_flex()
          .id("ap-search")
          .h(36)
          .flex_none()
          .px(10)
          .gap(8)
          .items_center()
          .rounded(9)
          .border_1()
          .border_color(normal ? t.border : t.accent)
          .bg(t.background)
          .on_click((_e, cx) => {
            this.mode = "insert";
            this.input.focus();
            cx.notify();
          })
          .child(Input.new(this.input).flex_1().h_full().text_size(12.8).text_color(t.foreground)),
      )
      .child(
        n === 0
          ? div().px(14).py(10).text_color(t.dim).child(this.filter ? "No agents match." : "No agents running.")
          : v_flex()
              .id("ap-list")
              .h(vis * ROW)
              .mb(6)
              .overflow_hidden()
              .on_scroll_wheel((e, cx) => {
                // Accumulate pixels so a trackpad flick moves a row at a time.
                this.wheel += e.delta.y;
                while (this.wheel >= ROW) (this.wheel -= ROW), move(-1);
                while (this.wheel <= -ROW) (this.wheel += ROW), move(1);
                cx.notify();
              })
              .children(rows.slice(this.top, this.top + vis).map((r, j) => row(r, this.top + j))),
      );
  }
}
