return {
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,
    config = function()
      require('catppuccin').setup {
        flavour = 'mocha', -- latte, frappe, macchiato, mocha
        transparent_background = true,
        -- Mocha's surfaces are cool blue-purple (base #1E1E2E, crust #11111B),
        -- which fights the neutral grays in Ghostty and herdr. Neutralize the
        -- UI surfaces only; the syntax colors below them are left alone.
        -- The first three match the hexes committed in ghostty/ and herdr/.
        color_overrides = {
          mocha = {
            -- Ordered the way catppuccin means them: crust darkest, base
            -- lightest. base is what floats and popups paint, so it gets the
            -- herdr sidebar gray and reads as a panel above the buffer.
            crust = '#0C0C0C', -- Ghostty background
            mantle = '#101010', -- herdr panel_bg
            base = '#161616', -- herdr sidebar_bg; telescope/which-key panels
            surface0 = '#242424', -- herdr active_row_bg; selected rows
            surface1 = '#2E2E2E', -- herdr selection_bg
            surface2 = '#3A3A3A',
            overlay0 = '#5A5A5A',
            overlay1 = '#767676',
            overlay2 = '#8A8A8A',
            subtext0 = '#909090',
            subtext1 = '#B4B4B4',
            text = '#EDEDED',
            -- Mocha's accents are tuned for a purple #1E1E2E ground; on neutral
            -- #0C0C0C they oversaturate. Same hues at 55% saturation, so red
            -- still reads red and diff/diagnostic meaning survives.
            -- `red` is deliberately left at stock: it carries errors and git
            -- deletions, and those should stay catchable in peripheral vision.
            rosewater = '#E6D3CF',
            flamingo = '#E1C4C4',
            pink = '#E2BBD7',
            mauve = '#C0A6DE',
            maroon = '#D3A1A9',
            peach = '#DAAC8F',
            yellow = '#E2D1AD',
            green = '#A4CCA1',
            teal = '#97C9C0',
            sky = '#90C5CE',
            sapphire = '#80B4CB',
            blue = '#91ADDB',
            lavender = '#B1B8E7',
          },
        },
        -- transparent_background sets every float group to NONE, so the palette
        -- above never paints them and popups inherit the terminal background.
        -- These put the floats back on the herdr sidebar gray so a telescope or
        -- which-key panel reads as a panel above the buffer, not a hole in it.
        custom_highlights = function()
          local panel = '#161616' -- herdr sidebar_bg
          local border = '#3A3A3A'
          local sel = '#242424' -- herdr active_row_bg
          return {
            NormalFloat = { bg = panel },
            FloatBorder = { bg = panel, fg = border },
            FloatTitle = { bg = panel, fg = '#EDEDED' },
            Pmenu = { bg = panel },
            PmenuSel = { bg = sel },
            TelescopeNormal = { bg = panel },
            TelescopeBorder = { bg = panel, fg = border },
            TelescopeTitle = { bg = panel, fg = '#EDEDED' },
            TelescopePromptNormal = { bg = panel },
            TelescopePromptBorder = { bg = panel, fg = border },
            TelescopePromptTitle = { bg = panel, fg = '#EDEDED' },
            TelescopeResultsNormal = { bg = panel },
            TelescopeResultsBorder = { bg = panel, fg = border },
            TelescopePreviewNormal = { bg = panel },
            TelescopePreviewBorder = { bg = panel, fg = border },
            TelescopeSelection = { bg = sel },
            WhichKeyNormal = { bg = panel },
            WhichKeyBorder = { bg = panel, fg = border },
            BlinkCmpMenu = { bg = panel },
            BlinkCmpMenuBorder = { bg = panel, fg = border },
            BlinkCmpDoc = { bg = panel },
            BlinkCmpDocBorder = { bg = panel, fg = border },
          }
        end,
      }
      vim.cmd.colorscheme 'catppuccin'
    end,
  },
}
