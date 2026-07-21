-- User commands, apply-on-save, and deployed-file -> source redirect.
local M = {}

local resolve = require("chezmoi-template.resolve")

local function notify(msg, level)
  vim.notify("chezmoi: " .. msg, level or vim.log.levels.INFO)
end

local function buf_target(buf)
  local file = vim.api.nvim_buf_get_name(buf or 0)
  if file == "" or not resolve.is_managed(file) then
    return nil
  end
  return resolve.target_path(file)
end

-- chezmoi apply, whole state or a single target (async)
local function apply(target)
  local cmd = { "chezmoi", "apply" }
  if target then
    table.insert(cmd, target)
  end
  vim.system(cmd, { text = true }, function(ret)
    vim.schedule(function()
      if ret.code == 0 then
        if require("chezmoi-template").config.apply.notify then
          notify("applied " .. (target and vim.fn.fnamemodify(target, ":~") or "all targets"))
        end
      else
        notify("apply failed:\n" .. (ret.stderr or ""), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function open_scratch_split(lines, ft)
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if ft then
    vim.bo[buf].filetype = ft
  end
  return buf
end

-- :ChezmoiPreview — render the current template via execute-template into a
-- vsplit typed as the target filetype; re-renders on every write while open.
-- Running it again closes the preview.
local preview_state = {} -- src buf -> { buf = preview buf }

local function preview_render(src, dest)
  local text = table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "\n") .. "\n"
  resolve.execute_template(text, function(ret)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(dest) then
        return
      end
      local lines
      if ret.code == 0 then
        lines = vim.split(ret.stdout, "\n")
        if lines[#lines] == "" then
          table.remove(lines)
        end
      else
        lines = vim.split("-- render failed --\n" .. (ret.stderr or ""), "\n")
      end
      vim.bo[dest].modifiable = true
      vim.api.nvim_buf_set_lines(dest, 0, -1, false, lines)
      vim.bo[dest].modifiable = false
    end)
  end)
end

local function preview_toggle()
  local src = vim.api.nvim_get_current_buf()
  local state = preview_state[src]
  if state and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
    preview_state[src] = nil
    return
  end

  local target_ft = vim.b[src].chezmoi_target_ft
  vim.cmd("vertical botright new")
  local dest = vim.api.nvim_get_current_buf()
  vim.bo[dest].buftype = "nofile"
  vim.bo[dest].bufhidden = "wipe"
  vim.bo[dest].swapfile = false
  if target_ft and target_ft ~= "gotmpl" then
    vim.bo[dest].filetype = target_ft
  end
  vim.cmd.wincmd("p")
  preview_state[src] = { buf = dest }

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = "chezmoi-template.commands",
    buffer = src,
    callback = function()
      if not vim.api.nvim_buf_is_valid(dest) then
        preview_state[src] = nil
        return true -- preview closed; drop the autocmd
      end
      preview_render(src, dest)
    end,
  })
  preview_render(src, dest)
end

local function define_commands()
  vim.api.nvim_create_user_command("ChezmoiApply", function(opts)
    if opts.bang then
      return apply(nil)
    end
    local target = buf_target(0)
    if not target then
      return notify("buffer has no chezmoi target (use :ChezmoiApply! for all)", vim.log.levels.WARN)
    end
    apply(target)
  end, { bang = true, desc = "chezmoi apply current buffer's target (! = all)" })

  vim.api.nvim_create_user_command("ChezmoiDiff", function()
    local target = buf_target(0)
    local cmd = { "chezmoi", "diff" }
    if target then
      table.insert(cmd, target)
    end
    local ret = vim.system(cmd, { text = true }):wait()
    if ret.code ~= 0 and (ret.stderr or "") ~= "" then
      return notify("diff failed:\n" .. ret.stderr, vim.log.levels.ERROR)
    end
    local out = ret.stdout or ""
    if vim.trim(out) == "" then
      return notify("no differences" .. (target and " for " .. vim.fn.fnamemodify(target, ":~") or ""))
    end
    open_scratch_split(vim.split(out, "\n"), "diff")
  end, { desc = "chezmoi diff for current target (whole state on non-chezmoi buffers)" })

  vim.api.nvim_create_user_command("ChezmoiTarget", function(opts)
    local target = buf_target(0)
    if not target then
      return notify("buffer has no chezmoi target", vim.log.levels.WARN)
    end
    if opts.bang then
      vim.cmd.edit(vim.fn.fnameescape(target))
    else
      notify(vim.fn.fnamemodify(target, ":~"))
    end
  end, { bang = true, desc = "show current buffer's deploy target (! = open it)" })

  vim.api.nvim_create_user_command("ChezmoiSource", function()
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" then
      return notify("unnamed buffer", vim.log.levels.WARN)
    end
    if resolve.is_managed(file) then
      return notify("already in the chezmoi source directory")
    end
    local ret = vim.system({ "chezmoi", "source-path", file }, { text = true }):wait()
    if ret.code ~= 0 then
      return notify("not a chezmoi-managed file", vim.log.levels.WARN)
    end
    vim.cmd.edit(vim.fn.fnameescape(vim.trim(ret.stdout)))
  end, { desc = "jump from a deployed file to its chezmoi source" })

  vim.api.nvim_create_user_command("ChezmoiPreview", preview_toggle, {
    desc = "toggle rendered preview of the current template (updates on write)",
  })

  vim.api.nvim_create_user_command("ChezmoiPick", function()
    require("chezmoi-template.picker").open()
  end, { desc = "pick a chezmoi source file (snacks/telescope/fzf-lua/mini.pick/select)" })
end

function M.setup()
  local config = require("chezmoi-template").config
  if config.commands.enabled then
    define_commands()
  end

  if config.apply.on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = "chezmoi-template.commands",
      callback = function(ctx)
        if not resolve.is_managed(ctx.file) then
          return
        end
        local target = resolve.target_path(ctx.file)
        if target then
          apply(target)
        end
      end,
    })
  end

  if config.redirect then
    vim.api.nvim_create_autocmd("BufReadPost", {
      group = "chezmoi-template.commands",
      callback = function(ctx)
        if ctx.file == "" or vim.bo[ctx.buf].buftype ~= "" or resolve.is_managed(ctx.file) then
          return
        end
        local abs = vim.fs.normalize(vim.fn.fnamemodify(ctx.file, ":p"))
        if not resolve.managed_set()[abs] then
          return
        end
        local ret = vim.system({ "chezmoi", "source-path", abs }, { text = true }):wait()
        if ret.code ~= 0 then
          return
        end
        local src = vim.trim(ret.stdout)
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == ctx.buf then
            vim.cmd.edit(vim.fn.fnameescape(src))
            notify("redirected to source " .. vim.fn.fnamemodify(src, ":~"))
          end
        end)
      end,
    })
  end
end

return M
