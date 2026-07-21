-- Template-error diagnostics: on write, render the buffer through
-- `chezmoi execute-template` and surface failures as vim.diagnostic entries.
local M = {}

local resolve = require("chezmoi-template.resolve")
local ns = vim.api.nvim_create_namespace("chezmoi-template")

-- Parse a chezmoi/text-template error into a diagnostic.
-- Shapes: `template: <name>:12:34: message` and `template: <name>:12: message`
-- (stdin templates report as "default" or "stdin" depending on version).
function M.parse(stderr)
  if not stderr or stderr == "" then
    return nil
  end
  local lnum, col, msg = stderr:match("template:[^:]*:(%d+):(%d+):%s*(.+)")
  if not lnum then
    lnum, msg = stderr:match("template:[^:]*:(%d+):%s*(.+)")
  end
  if not lnum then
    -- No position info: attach to line 1 so the failure is still visible
    return {
      lnum = 0,
      col = 0,
      message = vim.trim(stderr),
      severity = vim.diagnostic.severity.ERROR,
      source = "chezmoi",
    }
  end
  return {
    lnum = tonumber(lnum) - 1,
    col = col and tonumber(col) - 1 or 0,
    message = vim.trim(msg or stderr),
    severity = vim.diagnostic.severity.ERROR,
    source = "chezmoi",
  }
end

function M.check(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  resolve.execute_template(text, function(ret)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if ret.code == 0 then
        vim.diagnostic.set(ns, buf, {})
      else
        vim.diagnostic.set(ns, buf, { M.parse(ret.stderr) })
      end
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = "chezmoi-template.diagnostics",
    pattern = "*.tmpl",
    callback = function(ctx)
      if vim.bo[ctx.buf].filetype == "gotmpl" and resolve.is_managed(ctx.file) then
        M.check(ctx.buf)
      end
    end,
  })
end

return M
