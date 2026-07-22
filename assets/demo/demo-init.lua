-- Recording shim, loaded by every tape via `nvim --cmd 'luafile assets/demo/demo-init.lua'`.
-- Runs before plugins, so config specs can read the flag at startup.
vim.g.chezmoi_demo = 1

-- The plugin's rtp ships queries/gotmpl/injections.scm, which references the
-- custom inject-chezmoi! directive. The injection tape sets the load guard, so
-- setup() never registers the directive and the gotmpl highlighter would die on
-- the unknown name (all-white buffer). Pre-register a no-op; the real one
-- replaces it (both use force=true) once setup() runs.
vim.treesitter.query.add_directive("inject-chezmoi!", function() end, { force = true })

-- sidekick.nvim is disabled during recordings (its spec reads chezmoi_demo),
-- but LazyVim's sidekick extra still inserts lualine components that
-- require("sidekick.status") — stub it so lualine loads cleanly.
package.preload["sidekick.status"] = function()
  return {
    get = function() end,
    cli = function()
      return {}
    end,
  }
end

-- Freeze the statusline clock so GIFs are reproducible and don't leak the real
-- wall-clock. The lualine clock component reads os.date("%R") (HH:MM) and
-- os.date("%I") (hour → clock-face glyph); pin just those two to 13:37 ("leet").
-- Every other os.date format passes through, so dashboard dates and note
-- timestamps stay live.
local real_date = os.date
---@diagnostic disable-next-line: duplicate-set-field
os.date = function(fmt, t)
  if fmt == "%R" then
    return "13:37"
  elseif fmt == "%I" then
    return "01" -- 1 o'clock face for the 13:37 hour
  end
  return real_date(fmt, t)
end

