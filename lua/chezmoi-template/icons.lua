-- Resolve chezmoi source filenames to their deployed targets for icon lookup,
-- so `private_dot_config/ghostty/config.tmpl` shows the ghostty icon instead of
-- a generic template glyph.
--
-- mini.icons has no resolver hook, so this wraps MiniIcons.get(); the wrap is
-- transparent for non-chezmoi names.
local M = {}

local function is_chezmoi_name(name)
  return name:match("%.tmpl$")
    or name:match("%.age$")
    or name:match("/chezmoi/")
    or name:match("^chezmoi/")
    or name:match("/dot_")
    or name:match("^dot_")
    or name:match("/private_")
    or name:match("^private_")
    or name:match("/encrypted_")
    or name:match("^encrypted_")
    or name:match("/exact_")
    or name:match("^exact_")
end

local attached = false

-- Idempotent; returns false while mini.icons is not loaded yet.
function M.attach()
  if attached then
    return true
  end
  if not package.loaded["mini.icons"] then
    return false
  end
  local mi = require("mini.icons")
  local orig_get = mi.get
  mi.get = function(category, name, ...)
    if category == "file" and name and is_chezmoi_name(name) then
      local resolved = require("chezmoi-template.resolve").resolve_path(name)
      if resolved ~= name then
        return orig_get(category, resolved, ...)
      end
    end
    return orig_get(category, name, ...)
  end
  attached = true
  return true
end

-- Icon (glyph, hl) for a chezmoi source path's deployed target, for statusline/
-- bufferline components. Returns nil if `path` is not a chezmoi source
-- (resolves to itself) or mini.icons is unavailable.
function M.get(path)
  if not path or path == "" then
    return nil
  end
  local resolved = require("chezmoi-template.resolve").resolve_path(path)
  if resolved == path then
    return nil
  end
  local ok, mi = pcall(require, "mini.icons")
  if not ok then
    return nil
  end
  return mi.get("file", resolved)
end

function M.setup()
  if M.attach() then
    return
  end
  -- mini.icons not loaded yet (lazy-loaded): retry cheaply until it appears.
  -- If it never loads this session, the autocmd stays as a no-op boolean check.
  vim.api.nvim_create_autocmd({ "UIEnter", "FileType" }, {
    group = vim.api.nvim_create_augroup("chezmoi-template.icons", { clear = true }),
    callback = function()
      return M.attach() -- returning true removes the autocmd
    end,
  })
end

return M
