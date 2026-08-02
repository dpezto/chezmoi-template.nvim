local M = {}

-- LuaCATS classes for lua-language-server completion in plugin specs:
--   ---@module 'chezmoi-template'
--   ---@type chezmoi-template.Config
--   opts = { ... }

---@class chezmoi-template.Config.inject
---@field enabled? boolean treesitter injection of the target language into *.tmpl buffers
---@field exclude? string[] lua patterns (matched on the normalized "/" path) to leave as plain gotmpl

---@class chezmoi-template.Config.format
---@field enabled? boolean conform formatter that formats templates as their target filetype
---@field indent_directives? boolean depth-pad column-0 `{{-` directive blocks

---@class chezmoi-template.Config.icons
---@field enabled? boolean resolve chezmoi source names to target icons in mini.icons

---@class chezmoi-template.Config.apply
---@field on_save? boolean run `chezmoi apply <target>` after writing a managed source file
---@field notify? boolean notify on successful applies (failures always notify)
---@field force? boolean pass --force (skip chezmoi's prompt on externally-modified targets)

---@class chezmoi-template.Config.preview
---@field live? boolean re-render :Chezmoi preview as you type (false = re-render on write only)
---@field debounce? integer ms of idle before a live re-render
---@field slow_ms? integer a render slower than this pauses live preview to on-write; 0 disables
---@field split? "vertical"|"horizontal" preview window orientation
---@field diff? boolean mark the render against the file currently deployed

---@class chezmoi-template.Config.diagnostics
---@field enabled? boolean surface template errors as diagnostics on write

---@class chezmoi-template.Config.completion
---@field mask? string[] hide values of data keys matching these lua patterns in completion docs

---@class chezmoi-template.Config.picker
---@field backend? "snacks"|"telescope"|"fzf-lua"|"mini"|"select" nil = auto-detect among loaded pickers
---@field display? "target"|"source" entry labels: deployed names (.zshrc) or raw source names (dot_zshrc.tmpl)
---@field exclude? string[]|false lua patterns (vs the source-relative path) hidden on top of the built-in internals list; false = show everything

---@class chezmoi-template.Config.keymaps
---@field enabled? boolean buffer-local `:Chezmoi` bindings in chezmoi source buffers
---@field prefix? string lhs the bindings hang off
---@field icon? string glyph for the which-key group; nil = a built-in default

---@class chezmoi-template.Config.encryption
---@field enabled? boolean transparent decrypt/encrypt of chezmoi-managed encrypted files (*.age, *.asc)
---@field exclude? string[] lua patterns for encrypted paths to leave untouched

---@class chezmoi-template.Config
---@field source_dir? string chezmoi source directory; nil = auto-detect via `chezmoi source-path`
---@field inject? chezmoi-template.Config.inject
---@field format? chezmoi-template.Config.format
---@field icons? chezmoi-template.Config.icons
---@field apply? chezmoi-template.Config.apply
---@field preview? chezmoi-template.Config.preview
---@field notify_on_open? boolean notify when opening a chezmoi-managed source file
---@field redirect? boolean opening a deployed managed file jumps to its chezmoi source
---@field diagnostics? chezmoi-template.Config.diagnostics
---@field completion? chezmoi-template.Config.completion
---@field picker? chezmoi-template.Config.picker|string a backend-name string is shorthand for { backend = ... }
---@field keymaps? chezmoi-template.Config.keymaps
---@field encryption? chezmoi-template.Config.encryption

---@type chezmoi-template.Config
M.config = {
  -- nil = auto-detect via `chezmoi source-path`
  source_dir = nil,
  -- treesitter injection of the deployed target language into *.tmpl buffers
  inject = {
    enabled = true,
    -- lua patterns for source paths to leave as plain gotmpl (no target injection)
    exclude = {},
  },
  -- conform.nvim formatter that formats templates as their target filetype
  format = {
    enabled = true,
    -- rewrite interior padding of column-0 `{{-` directives so template
    -- nesting depth reads as indentation: {{- lvl0 }}, {{-   lvl1 }}, …
    indent_directives = true,
  },
  -- resolve chezmoi source names to target icons in mini.icons
  icons = { enabled = true },
  -- run `chezmoi apply <target>` after writing a managed source file.
  -- force = pass --force (skip chezmoi's prompt on externally-modified targets).
  apply = { on_save = true, notify = true, force = false },
  -- :Chezmoi preview rendered preview. live = re-render as you type (debounced,
  -- ms); false = re-render on write only. Invalid syntax keeps the last valid
  -- render until it parses again. slow_ms: if a render takes longer than this,
  -- live pauses to on-write (guards heavy secret-manager templates); 0 disables.
  -- split: "vertical" | "horizontal" preview window orientation
  -- diff: mark the render against the file currently deployed, so the preview
  -- shows what the edit changes out there, not only what it renders
  preview = { live = true, debounce = 150, slow_ms = 500, split = "vertical", diff = false },
  -- notify when opening a chezmoi-managed source file (à la chezmoi.nvim)
  notify_on_open = false,
  -- opening a deployed managed file jumps to its chezmoi source (opt-in)
  redirect = false,
  -- surface template errors (via `chezmoi execute-template`) as diagnostics on write
  diagnostics = { enabled = true },
  -- blink.cmp source behavior
  completion = {
    -- hide values of data keys matching these lua patterns in completion docs
    mask = { "secret", "token", "passw", "key", "api" },
  },
  -- :Chezmoi pick source-file picker (a plain string is shorthand for { backend = ... })
  picker = {
    -- "snacks" | "telescope" | "fzf-lua" | "mini" | "select";
    -- nil = auto-detect among loaded pickers, falling back to vim.ui.select
    backend = nil,
    -- entry labels: "target" = deployed names (dot_zshrc.tmpl -> .zshrc),
    -- "source" = raw source-relative names
    display = "target",
    -- lua patterns (vs the source-relative path) hidden on top of the built-in
    -- internals list (picker.DEFAULT_EXCLUDE: .git/, .chezmoi.$FORMAT.tmpl,
    -- .chezmoiversion, .chezmoiroot, .chezmoidata.*); false = show everything
    exclude = {},
  },
  -- buffer-local bindings in chezmoi source buffers (opt-in): p preview,
  -- a apply, d diff, t open target, s open source, e edit, f pick. Registers a
  -- which-key group with the same keys when which-key is loaded.
  keymaps = {
    enabled = false,
    prefix = "<localleader>c",
    -- glyph for the which-key group; nil = a built-in Nerd Font home icon
    icon = nil,
  },
  -- transparent decrypt/encrypt of chezmoi-managed encrypted files (*.age, *.asc)
  -- via `chezmoi decrypt` / `chezmoi encrypt` (age/rage/builtin/gpg, identities,
  -- recipients all come from chezmoi's own encryption config)
  encryption = {
    enabled = false,
    exclude = {}, -- lua patterns for *.age paths to leave untouched
  },
}

-- Static subcommand names for pre-activation tab-completion; the real command
-- (commands.lua) derives its own from the handler table. Kept in sync by hand.
local SUBCOMMANDS = { "apply", "diff", "edit", "pick", "preview", "source", "target" }

-- setup() is cheap: it only registers filetype detection, the treesitter
-- injection directive, and light triggers. The heavy work (module requires,
-- autocmds) is deferred to M._activate(), fired by the first template open or
-- :Chezmoi command — so startup stays cheap whether the plugin is loaded via
-- the plugin/ bootstrap or an eager setup(opts) from a lazy.nvim spec.
---@param opts? chezmoi-template.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._did_setup = true
  M._register()
end

function M._register()
  if M._registered then
    return
  end
  M._registered = true

  -- All *.tmpl files are gotmpl; the real target language is injected by
  -- treesitter (also avoids target-language LSPs choking on template syntax).
  vim.filetype.add({
    extension = { tmpl = "gotmpl" },
    filename = {
      [".chezmoiignore"] = "gitignore",
      [".chezmoiremove"] = "gitignore",
    },
  })

  -- The bundled gotmpl injection query references inject-chezmoi!, and
  -- treesitter parses gotmpl trees (highlighting, vim-matchup, render-markdown)
  -- before activation — the handler must exist up front or those parses error
  -- "No handler for inject-chezmoi!". Registration is cheap; its callback only
  -- touches resolve when a tree is actually parsed.
  require("chezmoi-template.inject").register_directive()

  -- Encryption registers on BufReadPre, and an autocmd created while an event
  -- is already dispatching does not run for that event — so activating from
  -- another BufReadPre handler would be too late and the first encrypted file
  -- of a session would open as ciphertext. Register it up front like the
  -- treesitter directive; setup() only creates an autocmd, and its callback is
  -- what does the work. Unconditional: _register() runs once, but setup() may
  -- run twice (the plugin/ bootstrap, then a lazy.nvim opts merge), and the
  -- second call is usually the one enabling encryption — so the callback reads
  -- config.encryption.enabled itself rather than this deciding for it.
  require("chezmoi-template.encryption").setup()

  local group = vim.api.nvim_create_augroup("chezmoi-template.bootstrap", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = group,
    pattern = { "*.tmpl", ".chezmoiignore*", ".chezmoiremove*", ".chezmoiexternal*" },
    callback = function(ev)
      M._activate()
      -- This buffer's BufReadPre already passed; seed it directly. Use ev.file
      -- (the autocmd <afile>, unresolved) not nvim_buf_get_name (symlink-
      -- resolved), so is_managed matches chezmoi's source dir path form.
      if ev.file ~= "" then
        require("chezmoi-template.inject").seed_buffer(ev.buf, ev.file)
      end
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "gotmpl",
    callback = function()
      M._activate()
    end,
  })
  -- Managed files that are not templates — a plain .lua, a *.age — match none
  -- of the patterns above, so nothing would activate for them and apply-on-save,
  -- transparent encryption, redirect and notify-on-open would quietly do
  -- nothing. Most of a chezmoi source dir is such files, so catch them by
  -- source-dir membership instead of by name. is_managed resolves the source
  -- dir once (one `chezmoi source-path`, cached for the session) and is a
  -- string compare from then on; with no chezmoi it returns false without
  -- spawning anything.
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      if ev.file == "" then
        return
      end
      local resolve = require("chezmoi-template.resolve")
      if resolve.is_managed(ev.file) then
        M._activate()
        -- redirect targets *deployed* files, which live outside the source dir
        -- and so never pass is_managed — without this the option is dead until
        -- something else activates the plugin, and the first file opened from a
        -- dashboard "config" shortcut stays on the target. managed_set is one
        -- `chezmoi managed` spawn, cached for the session, and only paid when
        -- redirect is opted in. Activation during BufReadPre registers the
        -- redirect autocmd in time for this buffer's own BufReadPost (an
        -- autocmd created mid-event skips that event, not later ones).
      elseif M.config.redirect then
        local abs = vim.fs.normalize(vim.fn.fnamemodify(ev.file, ":p"))
        if resolve.managed_set()[abs] then
          M._activate()
        end
      end
    end,
  })
  vim.api.nvim_create_user_command("Chezmoi", function(a)
    M._activate() -- replaces this stub with the real command
    vim.cmd(("Chezmoi%s %s"):format(a.bang and "!" or "", a.args))
  end, {
    bang = true,
    nargs = "*",
    desc = "chezmoi-template (loads on first use)",
    complete = function(arglead)
      return vim.tbl_filter(function(n)
        return n:find(arglead, 1, true) == 1
      end, SUBCOMMANDS)
    end,
  })
end

function M._activate()
  if M._activated then
    return
  end
  M._activated = true
  pcall(vim.api.nvim_del_augroup_by_name, "chezmoi-template.bootstrap")

  if M.config.inject.enabled then
    require("chezmoi-template.inject").setup()
  end
  if M.config.format.enabled then
    require("chezmoi-template.format").setup()
  end
  if M.config.icons.enabled then
    require("chezmoi-template.icons").setup()
  end
  -- encryption is registered in _register(); re-running setup() here would clear
  -- its augroup and drop the buffer-local handlers it just installed.
  require("chezmoi-template.commands").setup()
  if M.config.diagnostics.enabled then
    require("chezmoi-template.diagnostics").setup()
  end

  -- Group for the plugin-level autocmds below; clear = false so it doesn't wipe
  -- inject's autocmds if inject.setup already created and populated it.
  local core = vim.api.nvim_create_augroup("chezmoi-template.tmpl", { clear = false })

  -- Chezmoi state changes outside Neovim (`chezmoi add` in a shell, data
  -- edits) — FocusGained is the natural boundary to drop stale caches.
  -- Rebuilds are lazy, so an unfocused/refocused session with no lookups
  -- costs nothing.
  vim.api.nvim_create_autocmd("FocusGained", {
    group = core,
    callback = function()
      require("chezmoi-template.resolve").invalidate()
      if package.loaded["chezmoi-template.blink"] then
        require("chezmoi-template.blink").invalidate()
      end
    end,
  })

  -- Warm the `chezmoi data` cache off the first template's back, so the first
  -- completion doesn't pay the spawn. Deferred: FileType handlers finish first.
  vim.api.nvim_create_autocmd("FileType", {
    group = core,
    pattern = "gotmpl",
    once = true,
    callback = function()
      vim.defer_fn(function()
        require("chezmoi-template.resolve").data()
      end, 100)
    end,
  })
end

-- Titled so nvim-notify/noice render a "chezmoi" toast; plain vim.notify
-- ignores the opts and the messages still read fine bare.
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "chezmoi" })
end

-- Public API for integrations (statuslines, custom pickers, scripts).

-- All managed files as { source = <abs>, target = <abs> } pairs.
function M.list()
  M._activate()
  return require("chezmoi-template.resolve").list()
end

-- Open the chezmoi source file for a deploy target path.
function M.edit(target)
  M._activate()
  local src = require("chezmoi-template.resolve").source_path(vim.fn.expand(target))
  if not src then
    M.notify(target .. " is not chezmoi-managed", vim.log.levels.WARN)
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(src))
end

return M
