-- User commands, apply-on-save, and deployed-file -> source redirect.
local M = {}

local resolve = require("chezmoi-template.resolve")

local uv = vim.uv or vim.loop

-- Titled so nvim-notify/noice render a "chezmoi" toast; plain vim.notify
-- ignores the opts and the messages still read fine bare.
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "chezmoi" })
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

-- `q` closes plugin-owned scratch splits (diff, preview)
local function map_close(buf)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, { buffer = buf, nowait = true, desc = "close chezmoi split" })
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
  map_close(buf)
  return buf
end

-- :ChezmoiPreview — render the current template via execute-template into a
-- vsplit typed as the target filetype; re-renders live as you type (or on write
-- when preview.live is false). Running it again closes the preview.
-- state: src buf -> { dest, timer, tick, rendering, pending, live, slow_ms,
--                     last_output, stale }
local preview_state = {}

-- Freeing a preview's window handle + debounce timer, from either the toggle-off
-- path or when the dest buffer turns out to be gone.
local function preview_teardown(src)
  local st = preview_state[src]
  if st and st.timer then
    st.timer:stop()
    st.timer:close()
    st.timer = nil
  end
  preview_state[src] = nil
end

-- Flip the stale marker on the preview window's winbar. Shown when the template
-- fails to render so the frozen last-valid output doesn't read as current. Only
-- touches the window when the state actually changes.
local function set_stale(st, dest, stale)
  if st and st.stale == stale then
    return
  end
  if st then
    st.stale = stale
  end
  local win = vim.fn.bufwinid(dest)
  if win ~= -1 then
    vim.wo[win].winbar = stale and "%#WarningMsg#⚠ preview stale (invalid template)%*" or ""
  end
end

-- Live re-rendering runs the whole template on every idle window; a template
-- calling secret managers or the network can be slow. If a render blows past
-- slow_ms, drop this preview to on-write so leaving it on can't hammer them.
local function maybe_backoff(st, ms)
  if not st or not st.live or st.slow_ms <= 0 or ms <= st.slow_ms then
    return
  end
  st.live = false
  if st.timer then
    st.timer:stop()
    st.timer:close()
    st.timer = nil
  end
  notify(string.format("live preview paused (slow template, %dms) — updates on write", ms), vim.log.levels.WARN)
end

local function preview_render(src, dest)
  local st = preview_state[src]
  local text = table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "\n") .. "\n"
  local t0 = uv.hrtime()
  if st then
    st.rendering = true
    st.tick = vim.api.nvim_buf_get_changedtick(src)
  end
  resolve.execute_template(text, function(ret)
    vim.schedule(function()
      if st then
        st.rendering = false
        -- Only back off if this is still the active preview (not one torn down
        -- while its render was in flight).
        if preview_state[src] == st then
          maybe_backoff(st, (uv.hrtime() - t0) / 1e6)
        end
      end
      if not vim.api.nvim_buf_is_valid(dest) then
        return
      end
      if ret.code == 0 then
        -- Skip the rewrite (redraw + treesitter reparse) when output is
        -- unchanged — editing logic/comments/whitespace often renders identical.
        if not st or ret.stdout ~= st.last_output then
          local lines = vim.split(ret.stdout, "\n")
          if lines[#lines] == "" then
            table.remove(lines)
          end
          vim.bo[dest].modifiable = true
          vim.api.nvim_buf_set_lines(dest, 0, -1, false, lines)
          vim.bo[dest].modifiable = false
          if st then
            st.last_output = ret.stdout
          end
        end
        set_stale(st, dest, false)
      else
        -- Invalid template: keep the last valid render, flag it stale.
        set_stale(st, dest, true)
      end
      -- A change landed mid-render — re-run so the preview settles on it.
      if st and st.pending then
        st.pending = false
        preview_render(src, dest)
      end
    end)
  end)
end

-- Debounced re-render driver: collapses a burst of keystrokes into one spawn,
-- skips redundant spawns when the buffer hasn't changed, and defers rather than
-- stacking a spawn while one is already in flight.
local function schedule_render(src)
  local st = preview_state[src]
  if not st or not st.timer then
    return
  end
  local delay = require("chezmoi-template").config.preview.debounce
  st.timer:stop()
  st.timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      local s = preview_state[src]
      if not s or not vim.api.nvim_buf_is_valid(s.dest) or not vim.api.nvim_buf_is_valid(src) then
        return
      end
      if vim.api.nvim_buf_get_changedtick(src) == s.tick then
        return -- nothing changed since the last render started
      end
      if s.rendering then
        s.pending = true
        return
      end
      preview_render(src, s.dest)
    end)
  )
end

local function preview_toggle()
  local src = vim.api.nvim_get_current_buf()
  local existing = preview_state[src]
  if existing and vim.api.nvim_buf_is_valid(existing.dest) then
    vim.api.nvim_buf_delete(existing.dest, { force = true })
    preview_teardown(src)
    return
  end

  -- Non-template buffers (plain managed files, anything else) have nothing to
  -- render — chezmoi only templates gotmpl-typed sources. Same guard shape as
  -- the other commands: warn, don't open a useless split.
  if vim.bo[src].filetype ~= "gotmpl" then
    return notify("not a chezmoi template buffer", vim.log.levels.WARN)
  end

  local target_ft = vim.b[src].chezmoi_target_ft
  vim.cmd("vertical botright new")
  local dest = vim.api.nvim_get_current_buf()
  vim.bo[dest].buftype = "nofile"
  vim.bo[dest].bufhidden = "wipe"
  vim.bo[dest].swapfile = false
  -- Named after the deploy target so statuslines/tabs show the rendered
  -- file's identity (dot_zshrc.tmpl previews as .zshrc); the protocol prefix
  -- keeps it distinct from the real target buffer and unique per source.
  local src_file = vim.api.nvim_buf_get_name(src)
  local target_name = resolve.target_path(src_file) or resolve.resolve_path(vim.fn.fnamemodify(src_file, ":t"))
  -- pcall: a second preview with the same target name would E95 on collision
  pcall(vim.api.nvim_buf_set_name, dest, "chezmoi-preview://" .. target_name)
  if target_ft and target_ft ~= "gotmpl" then
    vim.bo[dest].filetype = target_ft
  end
  map_close(dest)
  vim.cmd.wincmd("p")

  local cfg = require("chezmoi-template").config.preview
  local st = {
    dest = dest,
    timer = cfg.live and uv.new_timer() or nil,
    tick = -1,
    rendering = false,
    pending = false,
    live = cfg.live,
    slow_ms = cfg.slow_ms,
    last_output = nil,
    stale = false,
  }
  preview_state[src] = st

  -- One autocmd on all three events: live edits debounce-render, and BufWritePost
  -- renders once live has been dropped to on-write (config or backoff), so the
  -- single callback covers both modes without re-registering.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = "chezmoi-template.commands",
    buffer = src,
    callback = function(ev)
      if not vim.api.nvim_buf_is_valid(dest) then
        preview_teardown(src)
        return true -- preview closed; drop the autocmd
      end
      if st.live then
        if ev.event ~= "BufWritePost" then
          schedule_render(src)
        end
      elseif ev.event == "BufWritePost" then
        preview_render(src, dest)
      end
    end,
  })

  -- Closing the preview (q / :q) wipes dest — free the timer right away instead
  -- of waiting for the next keystroke to notice.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = "chezmoi-template.commands",
    buffer = dest,
    callback = function()
      preview_teardown(src)
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
    desc = "toggle rendered preview of the current template (updates live as you type)",
  })

  vim.api.nvim_create_user_command("ChezmoiPick", function()
    require("chezmoi-template.picker").open()
  end, { desc = "pick a chezmoi source file (snacks/telescope/fzf-lua/mini.pick/select)" })
end

function M.setup()
  local config = require("chezmoi-template").config
  vim.api.nvim_create_augroup("chezmoi-template.commands", { clear = true })
  define_commands()

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

  if config.notify_on_open then
    vim.api.nvim_create_autocmd("BufReadPost", {
      group = "chezmoi-template.commands",
      callback = function(ctx)
        if vim.b[ctx.buf].chezmoi_notified or not resolve.is_managed(ctx.file) then
          return
        end
        vim.b[ctx.buf].chezmoi_notified = true
        local target = resolve.target_path(ctx.file)
        local msg = "chezmoi-managed" .. (target and (" → " .. vim.fn.fnamemodify(target, ":~")) or "")
        if config.apply.on_save then
          msg = msg .. " — applies on save"
        end
        notify(msg)
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
