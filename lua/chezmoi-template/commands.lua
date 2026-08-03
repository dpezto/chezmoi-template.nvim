-- User commands, apply-on-save, and deployed-file -> source redirect.
local M = {}

local resolve = require("chezmoi-template.resolve")

local uv = vim.uv or vim.loop

local notify = require("chezmoi-template").notify

local function buf_target(buf)
  local file = vim.api.nvim_buf_get_name(buf or 0)
  if file == "" or not resolve.is_managed(file) then
    return nil
  end
  return resolve.target_path(file)
end

-- 'includeexpr' for managed buffers, so `gf` on a name inside
-- {{ template "name" . }} or {{ includeTemplate "name" . }} opens the file it
-- names. chezmoi reads those from .chezmoitemplates/ in the source root, which
-- is nowhere near the including file, so plain `gf` never finds them. Quotes
-- are not in 'isfname', so v:fname already arrives as the bare name.
-- Returns fname untouched when it names nothing, leaving `gf` its own behaviour.
function M.includeexpr(fname)
  local dir = resolve.source_dir()
  if not dir then
    return fname
  end
  local path = dir .. ".chezmoitemplates/" .. fname
  local stat = uv.fs_stat(path)
  if stat and stat.type == "file" then
    return path
  end
  return fname
end

-- chezmoi apply, whole state or a single target (async)
local function apply(target)
  local args = { "apply" }
  if require("chezmoi-template").config.apply.force then
    table.insert(args, "--force")
  end
  if target then
    table.insert(args, target)
  end
  resolve.chezmoi(args, { text = true }, function(ret)
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

-- `q` closes the preview split
local function map_close(buf)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, { buffer = buf, nowait = true, desc = "close chezmoi split" })
end

-- Lines currently on disk at the deploy target. Missing file = everything the
-- template renders reads as added, which is the truth.
local function deployed_lines(target)
  if not target or vim.fn.filereadable(target) ~= 1 then
    return {}
  end
  return vim.fn.readfile(target)
end

-- :Chezmoi preview — render the current template via execute-template into a
-- vsplit typed as the target filetype; re-renders live as you type (or on write
-- when preview.live is false). Running it again closes the preview.
-- With preview.diff, a second pane holds the deployed file and the two are put
-- in diff mode, so the render reads as "what this edit will change out there"
-- rather than just "what this renders to". Neovim's diff engine sees the
-- rendered text directly, which is the one comparison git tooling cannot make:
-- the deployed state is not in any repository.
-- state: src buf -> { dest, deployed, target, timer, tick, rendering, pending,
--                     live, slow_ms, last_output, stale }
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
  -- The deployed pane exists only to be diffed against the render; on its own
  -- it is a copy of a file the user can just open.
  if st and st.deployed and vim.api.nvim_buf_is_valid(st.deployed) then
    vim.api.nvim_buf_delete(st.deployed, { force = true })
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
    -- Restore whatever the pane said before, not "": in diff mode the winbar
    -- is what tells the two sides apart.
    vim.wo[win].winbar = stale and "%#WarningMsg#⚠ preview stale (invalid template)%*" or (st and st.winbar or "")
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
        -- Re-read the deployed side every render: apply-on-save rewrites that
        -- file underneath the preview, and a diff against a stale copy reports
        -- changes that have already landed.
        -- ponytail: one small readfile per render; cache on mtime if it ever
        -- shows up next to the execute-template spawn it rides along with.
        if st and st.deployed and vim.api.nvim_buf_is_valid(st.deployed) then
          vim.bo[st.deployed].modifiable = true
          vim.api.nvim_buf_set_lines(st.deployed, 0, -1, false, deployed_lines(st.target))
          vim.bo[st.deployed].modifiable = false
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

-- want_diff overrides preview.diff for one invocation (`:Chezmoi diff`).
local function preview_toggle(want_diff)
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

  local cfg = require("chezmoi-template").config.preview
  local target_ft = vim.b[src].chezmoi_target_ft
  local src_file = vim.api.nvim_buf_get_name(src)
  local target = resolve.target_path(src_file)
  -- Nothing deployed to compare against: .chezmoitemplates/, .chezmoiscripts/,
  -- an unapplied new file. Render without the second pane rather than refuse.
  local diff = (want_diff == nil and cfg.diff or want_diff) and target ~= nil
  local src_win = vim.api.nvim_get_current_win()

  vim.cmd((cfg.split == "horizontal" and "" or "vertical ") .. "botright new")
  local deployed
  if diff then
    deployed = vim.api.nvim_get_current_buf()
    vim.bo[deployed].buftype = "nofile"
    vim.bo[deployed].bufhidden = "wipe"
    vim.bo[deployed].swapfile = false
    vim.api.nvim_buf_set_lines(deployed, 0, -1, false, deployed_lines(target))
    vim.bo[deployed].modifiable = false
    if target_ft and target_ft ~= "gotmpl" then
      vim.bo[deployed].filetype = target_ft
    end
    -- pcall: a second preview of the same target would E95 on the name collision
    pcall(vim.api.nvim_buf_set_name, deployed, "chezmoi-deployed://" .. target)
    vim.wo.winbar = "deployed  " .. vim.fn.fnamemodify(target, ":~")
    -- Side by side whatever preview.split says: a diff read top to bottom is
    -- not a diff anyone reads.
    vim.cmd("vertical rightbelow new")
  end

  local dest = vim.api.nvim_get_current_buf()
  vim.bo[dest].buftype = "nofile"
  vim.bo[dest].bufhidden = "wipe"
  vim.bo[dest].swapfile = false
  -- Named after the deploy target so statuslines/tabs show the rendered
  -- file's identity (dot_zshrc.tmpl previews as .zshrc); the protocol prefix
  -- keeps it distinct from the real target buffer and unique per source.
  local target_name = target or resolve.resolve_path(vim.fn.fnamemodify(src_file, ":t"))
  -- pcall: a second preview with the same target name would E95 on collision
  pcall(vim.api.nvim_buf_set_name, dest, "chezmoi-preview://" .. target_name)
  if target_ft and target_ft ~= "gotmpl" then
    vim.bo[dest].filetype = target_ft
  end
  map_close(dest)
  local base_winbar = ""
  if diff then
    base_winbar = "will deploy  " .. vim.fn.fnamemodify(target, ":~")
    vim.wo.winbar = base_winbar
    vim.api.nvim_win_call(vim.fn.bufwinid(deployed), function()
      vim.cmd("diffthis")
    end)
    vim.cmd("diffthis")
    map_close(deployed)
    -- However the deployed pane goes away (`q`, :q, a window close wiping it),
    -- the render goes with it: left alone it is a copy of a file the user could
    -- have opened, still stuck in diff mode against nothing.
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = "chezmoi-template.commands",
      buffer = deployed,
      callback = function()
        if vim.api.nvim_buf_is_valid(dest) then
          vim.api.nvim_buf_delete(dest, { force = true })
        end
      end,
    })
  end
  -- Two windows may have been opened; `wincmd p` would land on the wrong one.
  if vim.api.nvim_win_is_valid(src_win) then
    vim.api.nvim_set_current_win(src_win)
  end

  local st = {
    dest = dest,
    deployed = deployed,
    target = target,
    winbar = base_winbar,
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

  -- A source can be a bare passthrough to .chezmoitemplates/, in which case
  -- every line worth previewing lives in a file this autocmd would otherwise
  -- ignore. execute-template reads those from disk, so an unwritten edit is
  -- invisible to chezmoi and there is nothing to render until the write —
  -- unlike the source buffer, this cannot follow the keystrokes.
  -- ponytail: any .chezmoitemplates write re-renders every open preview, no
  -- dependency tracking. An unrelated write costs one spawn and the last_output
  -- check above keeps the buffer untouched; parse the include names at toggle
  -- time if that ever shows up in a profile.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = "chezmoi-template.commands",
    callback = function(ev)
      -- Path match, not an autocmd pattern: a raw ev.file is backslashed on
      -- Windows and would dodge a "/"-style glob.
      if not vim.fs.normalize(ev.file):find("/.chezmoitemplates/", 1, true) then
        return
      end
      if not vim.api.nvim_buf_is_valid(dest) then
        preview_teardown(src)
        return true -- preview closed; drop the autocmd
      end
      preview_render(src, dest)
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

-- Whether a preview split is open for a buffer. Public so a statusline or a
-- which-key `desc`/`icon` function can label the toggle with its current state.
function M.preview_is_open(buf)
  if buf == nil or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local st = preview_state[buf]
  return st ~= nil and vim.api.nvim_buf_is_valid(st.dest)
end

-- obsidian.nvim-style single command: `:Chezmoi <sub>` dispatches to one of
-- these. Each run() takes a ctx carrying the bang; none take value args.
local subcommands = {
  apply = {
    desc = "apply current buffer's target (! = all)",
    run = function(ctx)
      if ctx.bang then
        return apply(nil)
      end
      local target = buf_target(0)
      if not target then
        return notify("buffer has no chezmoi target (use :Chezmoi! apply for all)", vim.log.levels.WARN)
      end
      apply(target)
    end,
  },

  diff = {
    desc = "preview the current template diffed against the deployed file",
    run = function()
      -- Source state that deploys nowhere (.chezmoitemplates/,
      -- .chezmoiscripts/, .chezmoiignore) has no file of its own to compare
      -- against. Whole-tree diffs are a git question; git tooling answers it.
      if vim.bo.filetype == "gotmpl" and not buf_target(vim.api.nvim_get_current_buf()) then
        return notify("buffer has no chezmoi target", vim.log.levels.WARN)
      end
      preview_toggle(true)
    end,
  },

  target = {
    desc = "show current buffer's deploy target (! = open it)",
    run = function(ctx)
      local target = buf_target(0)
      if not target then
        return notify("buffer has no chezmoi target", vim.log.levels.WARN)
      end
      if ctx.bang then
        vim.cmd.edit(vim.fn.fnameescape(target))
      else
        notify(vim.fn.fnamemodify(target, ":~"))
      end
    end,
  },

  source = {
    desc = "jump from a deployed file to its chezmoi source",
    run = function()
      local file = vim.api.nvim_buf_get_name(0)
      if file == "" then
        return notify("unnamed buffer", vim.log.levels.WARN)
      end
      if resolve.is_managed(file) then
        return notify("already in the chezmoi source directory")
      end
      local src = resolve.source_path(file)
      if not src then
        return notify("not a chezmoi-managed file", vim.log.levels.WARN)
      end
      vim.cmd.edit(vim.fn.fnameescape(src))
    end,
  },

  edit = {
    desc = "open the chezmoi source for a target path",
    run = function(ctx)
      local target = ctx.fargs[1]
      if not target or target == "" then
        return notify("usage: :Chezmoi edit <target>", vim.log.levels.WARN)
      end
      require("chezmoi-template").edit(target)
    end,
    complete = function(arglead)
      local expanded = vim.fn.expand(arglead)
      local out = {}
      for t in pairs(resolve.managed_set()) do -- cached absolute target paths
        if arglead == "" or t:find(expanded, 1, true) == 1 then
          out[#out + 1] = t
        end
      end
      table.sort(out)
      return out
    end,
  },

  preview = {
    desc = "toggle rendered preview of the current template (updates live as you type)",
    run = function()
      preview_toggle()
    end,
  },

  pick = {
    desc = "pick a chezmoi source file (snacks/telescope/fzf-lua/mini.pick/select)",
    run = function()
      require("chezmoi-template.picker").open()
    end,
  },
}

local sub_names = vim.tbl_keys(subcommands)
table.sort(sub_names)

local function define_commands()
  vim.api.nvim_create_user_command("Chezmoi", function(o)
    local sub = o.fargs[1]
    local entry = sub and subcommands[sub]
    if not entry then
      return notify(("usage: :Chezmoi <%s>"):format(table.concat(sub_names, "|")), vim.log.levels.WARN)
    end
    entry.run({ bang = o.bang, fargs = vim.list_slice(o.fargs, 2) })
  end, {
    bang = true,
    nargs = "*",
    desc = "chezmoi-template",
    complete = function(arglead, cmdline)
      -- Word 2 is the subcommand; past it, delegate to its value completion.
      local words = vim.split(vim.trim(cmdline), "%s+")
      local sub = words[2]
      local entry = sub and subcommands[sub]
      if entry and entry.complete and (sub ~= arglead) then
        return entry.complete(arglead)
      end
      return vim.tbl_filter(function(n)
        return n:find(arglead, 1, true) == 1
      end, sub_names)
    end,
  })
end

-- Buffer-local bindings, off by default. A plugin claiming global keys collides
-- with whatever already owns the prefix (LazyVim's chezmoi extra takes
-- <leader>sz), but scoped to chezmoi source buffers a default prefix costs
-- nothing elsewhere. `edit` takes a target, so it leaves the cmdline open.
-- Nerd Font glyphs by codepoint. Pasting them literally into source is fragile:
-- private-use characters do not survive every editor, terminal or patch tool,
-- and a stripped glyph fails silently as a blank icon.
local NF = {
  home = 0xf015, -- the group
  check = 0xf00c, -- apply
  arrow_right = 0xf061, -- source -> deployed
  arrow_left = 0xf060, -- deployed -> source
  pencil = 0xf040, -- edit
  search = 0xf002, -- pick
  toggle_on = 0xf205, -- preview open (the pair snacks.nvim uses)
  toggle_off = 0xf204, -- preview closed
}

local function icon(cp, color)
  return { icon = vim.fn.nr2char(cp) .. " ", color = color }
end

local keymap_specs = {
  { key = "p", rhs = "<cmd>Chezmoi preview<cr>", desc = "Preview" },
  { key = "a", rhs = "<cmd>Chezmoi apply<cr>", desc = "Apply", icon = icon(NF.check, "green") },
  -- mini.icons/nvim-web-devicons already have a diff glyph; let which-key ask
  { key = "d", rhs = "<cmd>Chezmoi diff<cr>", desc = "Diff", icon = { cat = "filetype", name = "diff" } },
  { key = "t", rhs = "<cmd>Chezmoi! target<cr>", desc = "Open Target", icon = icon(NF.arrow_right, "orange") },
  { key = "s", rhs = "<cmd>Chezmoi source<cr>", desc = "Open Source", icon = icon(NF.arrow_left, "blue") },
  { key = "e", rhs = ":Chezmoi edit ", desc = "Edit Target", icon = icon(NF.pencil, "purple") },
  { key = "f", rhs = "<cmd>Chezmoi pick<cr>", desc = "Find Source File", icon = icon(NF.search, "green") },
}

local function preview_label()
  return M.preview_is_open(0) and "Close Preview" or "Preview"
end

local function preview_icon()
  if M.preview_is_open(0) then
    return icon(NF.toggle_on, "green")
  end
  return icon(NF.toggle_off, "yellow")
end

-- which-key evaluates a spec's desc/icon functions every time the popup opens,
-- so the preview entry reports the split's current state without this plugin
-- depending on which-key (or snacks) to provide a toggle abstraction.
local function which_key_add(buf, prefix, group_icon)
  local spec = {
    {
      prefix,
      group = "chezmoi",
      icon = group_icon and { icon = group_icon, color = "cyan" } or icon(NF.home, "cyan"),
      buffer = buf,
    },
  }
  for _, s in ipairs(keymap_specs) do
    spec[#spec + 1] = {
      prefix .. s.key,
      buffer = buf,
      desc = s.key == "p" and preview_label or s.desc,
      icon = s.key == "p" and preview_icon or s.icon,
    }
  end
  require("which-key").add(spec)
end

local function attach_buffer(buf, config)
  -- `gf` only consults 'includeexpr' when the name is not a readable path as
  -- written, so this costs nothing for ordinary paths. Never overwrite a value
  -- the user or another plugin set.
  if vim.bo[buf].includeexpr == "" then
    vim.bo[buf].includeexpr = "v:lua.require'chezmoi-template.commands'.includeexpr(v:fname)"
  end
  if not config.keymaps.enabled then
    return
  end
  local prefix = config.keymaps.prefix
  for _, s in ipairs(keymap_specs) do
    vim.keymap.set("n", prefix .. s.key, s.rhs, { buffer = buf, desc = "chezmoi: " .. s.desc })
  end
  if package.loaded["which-key"] then
    which_key_add(buf, prefix, config.keymaps.icon)
  end
end

-- Last chezmoi warning reported after a source-state write, so a standing one
-- is not repeated on every save. nil = nothing outstanding.
local last_warning

function M.setup()
  local config = require("chezmoi-template").config
  vim.api.nvim_create_augroup("chezmoi-template.commands", { clear = true })
  define_commands()
  last_warning = nil

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = "chezmoi-template.commands",
    callback = function(ctx)
      if resolve.is_managed(ctx.file) then
        attach_buffer(ctx.buf, config)
      end
    end,
  })
  -- Activation can come from a :Chezmoi command in an already-open source
  -- buffer, whose BufReadPost is long past — that buffer would otherwise wait
  -- for a reload to get its bindings.
  local cur = vim.api.nvim_get_current_buf()
  if resolve.is_managed(vim.api.nvim_buf_get_name(cur)) then
    attach_buffer(cur, config)
  end

  if config.apply.on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = "chezmoi-template.commands",
      callback = function(ctx)
        if not resolve.is_managed(ctx.file) then
          return
        end
        -- chezmoi's own source state (.chezmoi.<fmt>.tmpl, .chezmoiignore,
        -- .chezmoidata/, …) deploys nowhere, so there is nothing to apply.
        -- Editing it can still invalidate the generated config, which only
        -- chezmoi can judge — report what it says instead of staying silent.
        if resolve.is_source_state(ctx.file) then
          return resolve.warnings(function(warnings)
            -- A warning describes standing state, not this write: it holds
            -- until something is done about it, and would otherwise repeat on
            -- every save, including writes that changed nothing. Report each
            -- distinct warning once and re-arm when it clears.
            local text = warnings and table.concat(warnings, "\n") or nil
            if text == last_warning then
              return
            end
            last_warning = text
            if text then
              vim.schedule(function()
                notify(text, vim.log.levels.WARN)
              end)
            end
          end)
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
        local src = resolve.source_path(abs)
        if not src then
          return
        end
        vim.schedule(function()
          -- Redirect in whichever window shows the target, not only when it is
          -- current: pickers/dashboards juggle float focus between this
          -- buffer's read and the scheduled callback. bufwinid -1 means the
          -- buffer was loaded in the background (a preview) — leave it alone.
          local win = vim.fn.bufwinid(ctx.buf)
          if win == -1 then
            return
          end
          vim.api.nvim_win_call(win, function()
            vim.cmd.edit(vim.fn.fnameescape(src))
          end)
          -- Wipe the target buffer so only the source remains: a lingering
          -- listed target sits in bufferlines one accidental edit away from
          -- being clobbered on the next apply.
          if vim.api.nvim_buf_is_valid(ctx.buf) and not vim.bo[ctx.buf].modified then
            pcall(vim.api.nvim_buf_delete, ctx.buf, {})
          end
          notify("redirected to source " .. vim.fn.fnamemodify(src, ":~"))
        end)
      end,
    })
  end
end

return M
