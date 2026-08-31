-- Cmd+V image paste for terminal coding agents.
--
-- Ghostty's paste_from_clipboard only knows how to send text, so an image on
-- the clipboard (Cmd+Ctrl+Shift+4, or Cmd+Shift+5 with Destination=Clipboard)
-- pastes nothing. Claude Code works around this with its own Ctrl+V handler
-- that reads the clipboard directly, but Ctrl+V is quoted-insert in zsh and
-- literal-insert in nvim, so it can't just be remapped onto Cmd+V terminal-wide.
--
-- Ghostty can't make the decision itself: `performable:` would be the right
-- lever, but it is a no-op on macOS because the AppKit apprt has no synchronous
-- clipboard check, so clipboardRequest always reports success. See
-- ghostty-org/ghostty#11444, closed as not planned.
--
-- So the branch lives up here, above the terminal, where the clipboard can be
-- inspected before the keystroke is delivered:
--   image on clipboard + Ghostty focused -> send Ctrl+V
--   anything else                        -> fall through to the real Cmd+V
--
-- Branching on clipboard contents rather than on the focused program is what
-- makes this safe. Ctrl+V only ever fires when an image is on the clipboard,
-- and Cmd+V with an image was already dead at a zsh prompt, so nothing that
-- used to work stops working. Text paste is never touched.

local GHOSTTY_BUNDLE = "com.mitchellh.ghostty"

-- The tap only exists while Hammerspoon runs, so a paste that silently does
-- nothing after a reboot is the expected failure. Register the login item from
-- the config itself rather than the preferences checkbox, so stowing this file
-- on a new machine is enough.
hs.autoLaunch(true)

imagePasteTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local flags = event:getFlags()
    local isCmdV = event:getKeyCode() == hs.keycodes.map["v"]
        and flags.cmd and not flags.alt and not flags.ctrl and not flags.shift
    if not isCmdV then return false end

    -- Scoped to Ghostty on purpose. Slack, Figma and friends paste images
    -- natively on Cmd+V; sending them Ctrl+V instead would break that.
    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= GHOSTTY_BUNDLE then return false end

    -- readImage returns nil for text, which is the common case: fall through
    -- and let Ghostty's own paste_from_clipboard handle it untouched.
    if not hs.pasteboard.readImage() then return false end

    -- Claude Code reads the clipboard itself on Ctrl+V, so it receives real
    -- image bytes and renders [Image #1] rather than a path it has to go open.
    hs.eventtap.keyStroke({ "ctrl" }, "v", 0)
    return true
end)

imagePasteTap:start()
