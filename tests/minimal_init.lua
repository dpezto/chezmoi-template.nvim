-- Run from the repo root: nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

-- COVERAGE=1: record line coverage with luacov (must start before the plugin
-- modules load; jit.off() because compiled traces bypass the line hook)
if os.getenv("COVERAGE") then
  jit.off()
  require("luacov")
end

-- Stub conform: identity "formatter" so tests exercise masking/restore/indent
-- logic without any external formatter binaries. Captures the masked scratch
-- buffer for assertions. Setting _G.conform_reject to a predicate over the
-- masked lines makes the stub reject that buffer, which is how the coarse
-- fallback pass is exercised without a real formatter.
_G.captured_masked = nil
_G.conform_reject = nil
package.preload["conform"] = function()
  local M = { formatters = {}, formatters_by_ft = {} }
  function M.format(opts, cb)
    local masked = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
    _G.captured_masked = masked
    _G.captured_name = vim.api.nvim_buf_get_name(opts.bufnr)
    if _G.conform_reject and _G.conform_reject(masked) then
      return cb("stub: masked buffer rejected")
    end
    cb(nil, false)
  end
  return M
end

-- normalize getcwd so the source dir uses forward slashes on Windows too
-- (matches how resolve.lua normalizes both sides of every path compare)
require("chezmoi-template").setup({ source_dir = vim.fs.normalize(vim.fn.getcwd()) .. "/tests" })
