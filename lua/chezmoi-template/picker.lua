-- Source-file picker over the chezmoi source directory, backend-agnostic.
-- Entries are built by the plugin (fs walk + exclude patterns + display
-- mapping) so every backend shows the same list: deployed target names by
-- default (dot_zshrc.tmpl -> .zshrc), chezmoi internals hidden. Each backend's
-- previewer seeds the preview buffer's chezmoi_target_lang before treesitter
-- parses it, so the inject-chezmoi! directive highlights the target language —
-- preview buffers are nameless scratch buffers, so the directive's
-- buffer-name fallback never fires for them.
-- config.picker.backend picks the backend explicitly; nil auto-detects among
-- loaded pickers (snacks > telescope > fzf-lua > mini.pick) and falls back to
-- vim.ui.select. Auto-detection only sees pickers that are on the runtimepath
-- when invoked — with aggressive lazy-loading, set backend explicitly.
local M = {}

local resolve = require("chezmoi-template.resolve")

-- Hidden by default: never-edited chezmoi internals. Deliberately keeps
-- .chezmoiignore, .chezmoiscripts/, .chezmoitemplates/ and .chezmoiexternal*
-- (all editable with target-language support). config.picker.exclude = {}
-- shows everything; a non-nil list replaces this one.
M.DEFAULT_EXCLUDE = {
  "^%.git/",
  "^%.chezmoi%.%w+%.tmpl$", -- .chezmoi.toml.tmpl / .chezmoi.yaml.tmpl config template
  "^%.chezmoiversion",
  "^%.chezmoiroot$",
  "^%.chezmoidata[./]", -- .chezmoidata.$FORMAT and .chezmoidata/ dir form
}

-- Normalized picker config: a plain string is shorthand for { backend = str }
-- (pre-1.2 config shape); missing fields get defaults. Normalization lives
-- here, not in the setup() merge — tbl_deep_extend can't merge string→table.
local function conf()
  local c = require("chezmoi-template").config.picker
  if type(c) == "string" then
    c = { backend = c }
  end
  c = c or {}
  return {
    backend = c.backend,
    display = c.display or "target",
    exclude = c.exclude or M.DEFAULT_EXCLUDE,
  }
end

-- Source-relative file paths under src (forward-slash, the same form
-- inject.exclude patterns match). Prefer `git ls-files` (tracked + untracked
-- minus gitignored — chezmoi source dirs are git repos and carry index/cache
-- junk the old fd-backed pickers never showed); fall back to a plain fs walk,
-- pruning .git directories, for non-git source dirs.
function M.walk(src)
  local ok, ret = pcall(function()
    return vim
      .system(
        { "git", "-c", "core.quotepath=false", "-C", src, "ls-files", "--cached", "--others", "--exclude-standard" },
        { text = true }
      )
      :wait()
  end)
  if ok and ret.code == 0 then
    local rels = {}
    for line in ret.stdout:gmatch("[^\n]+") do
      rels[#rels + 1] = line
    end
    if #rels > 0 then
      return rels
    end
  end
  local rels = {}
  for name, t in
    vim.fs.dir(src, {
      depth = math.huge,
      skip = function(d)
        return vim.fs.basename(d) ~= ".git"
      end,
    })
  do
    if t == "file" then
      rels[#rels + 1] = name
    end
  end
  return rels
end

-- Pure transform: exclude filtering + display mapping, sorted by display.
-- Display collisions (dot_foo and dot_foo.tmpl both resolve to .foo) get a
-- " (rel)" suffix — fzf-lua maps display→path by string, so displays must be
-- unique. cfg = { display = "target"|"source", exclude = {patterns} }.
function M.build(rels, src, cfg)
  local out, seen = {}, {}
  for _, rel in ipairs(rels) do
    rel = vim.fs.normalize(rel) -- defensive: exclude patterns assume "/" separators
    local skip = false
    for _, pat in ipairs(cfg.exclude) do
      if rel:match(pat) then
        skip = true
        break
      end
    end
    if not skip then
      local display = cfg.display == "source" and rel or resolve.resolve_path(rel)
      if seen[display] then
        display = display .. " (" .. rel .. ")"
      end
      seen[display] = true
      out[#out + 1] = { rel = rel, abs = src .. rel, display = display }
    end
  end
  table.sort(out, function(a, b)
    return a.display < b.display
  end)
  return out
end

-- Seed target ft/lang on a preview buffer BEFORE its gotmpl tree parses, so
-- inject-chezmoi! injects the target language into nameless scratch buffers.
-- Clears stale vars first (snacks/telescope reuse preview buffers across
-- entries); if the backend already started treesitter, restart to re-run
-- injection with the vars in place.
local function seed_preview(buf, abs)
  vim.b[buf].chezmoi_target_ft = nil
  vim.b[buf].chezmoi_target_lang = nil
  require("chezmoi-template.inject").seed_buffer(buf, abs)
  if vim.treesitter.highlighter.active[buf] then
    vim.treesitter.stop(buf)
    pcall(vim.treesitter.start, buf, "gotmpl")
  end
end
M._seed_preview = seed_preview

local function edit(abs)
  vim.cmd.edit(vim.fn.fnameescape(abs))
end

local backends = {
  snacks = {
    avail = function()
      return pcall(require, "snacks")
    end,
    open = function(entries)
      local Snacks = require("snacks")
      Snacks.picker.pick({
        title = "Chezmoi",
        items = vim.tbl_map(function(e)
          return { text = e.display, file = e.abs }
        end, entries),
        format = function(item)
          local icon, hl = Snacks.util.icon(vim.fs.basename(item.text), "file")
          return { { icon .. " ", hl }, { item.text } }
        end,
        preview = function(ctx)
          -- ctx.buf is live (always the current preview win buffer); the stock
          -- file previewer's reset() may swap in a fresh scratch buffer, so
          -- seed before (fast path: buffer reused, vars present at first
          -- parse) and reseed only if the buffer changed underneath us.
          local buf = ctx.buf
          seed_preview(buf, ctx.item.file)
          local ret = require("snacks.picker.preview").file(ctx)
          if ctx.buf ~= buf then
            seed_preview(ctx.buf, ctx.item.file)
          end
          return ret
        end,
        -- default confirm jumps to item.file
      })
    end,
  },
  telescope = {
    avail = function()
      return pcall(require, "telescope.builtin")
    end,
    open = function(entries)
      local pickers = require("telescope.pickers")
      local finders = require("telescope.finders")
      local previewers = require("telescope.previewers")
      local tconf = require("telescope.config").values
      pickers
        .new({}, {
          prompt_title = "Chezmoi source files",
          finder = finders.new_table({
            results = entries,
            entry_maker = function(e)
              return { value = e, display = e.display, ordinal = e.display, path = e.abs, filename = e.abs }
            end,
          }),
          sorter = tconf.generic_sorter({}),
          previewer = previewers.new_buffer_previewer({
            title = "Chezmoi",
            get_buffer_by_name = function(_, entry)
              return entry.value.abs
            end,
            define_preview = function(self, entry)
              -- maker reads + highlights async, so the synchronous seed
              -- lands before its treesitter start
              seed_preview(self.state.bufnr, entry.value.abs)
              tconf.buffer_previewer_maker(entry.value.abs, self.state.bufnr, { bufname = self.state.bufname })
            end,
          }),
          -- default select action edits entry.path
        })
        :find()
    end,
  },
  ["fzf-lua"] = {
    avail = function()
      return pcall(require, "fzf-lua")
    end,
    open = function(entries)
      local fzf = require("fzf-lua")
      local by_display, lines = {}, {}
      for _, e in ipairs(entries) do
        by_display[e.display], lines[#lines + 1] = e.abs, e.display
      end
      local builtin = require("fzf-lua.previewer.builtin")
      local P = builtin.buffer_or_file:extend()
      function P:new(o, opts, fzf_win)
        P.super.new(self, o, opts, fzf_win)
        setmetatable(self, P)
        return self
      end
      function P:parse_entry(entry_str)
        return { path = by_display[entry_str] or entry_str }
      end
      function P:preview_buf_post(entry, min_winopts)
        P.super.preview_buf_post(self, entry, min_winopts)
        -- runs after fzf-lua's own highlight; seed_preview restarts
        -- treesitter so injection picks the vars up
        if self.preview_bufnr and vim.api.nvim_buf_is_valid(self.preview_bufnr) then
          seed_preview(self.preview_bufnr, entry.path)
        end
      end
      fzf.fzf_exec(lines, {
        prompt = "Chezmoi> ",
        previewer = P,
        actions = {
          ["default"] = function(selected)
            local abs = selected[1] and by_display[selected[1]]
            if abs then
              edit(abs)
            end
          end,
        },
      })
    end,
  },
  mini = {
    avail = function()
      return pcall(require, "mini.pick")
    end,
    open = function(entries)
      local MiniPick = require("mini.pick")
      MiniPick.start({
        source = {
          name = "Chezmoi",
          items = vim.tbl_map(function(e)
            return { text = e.display, path = e.abs }
          end, entries),
          preview = function(buf_id, item)
            seed_preview(buf_id, item.path)
            MiniPick.default_preview(buf_id, item)
          end,
          -- default choose opens item.path
        },
      })
    end,
  },
  select = {
    avail = function()
      return true
    end,
    open = function(entries)
      vim.ui.select(entries, {
        prompt = "chezmoi source files",
        format_item = function(e)
          return e.display
        end,
      }, function(choice)
        if choice then
          edit(choice.abs)
        end
      end)
    end,
  },
}

local ORDER = { "snacks", "telescope", "fzf-lua", "mini", "select" }

function M.open()
  local notify = require("chezmoi-template").notify
  local src = resolve.source_dir()
  if not src then
    return notify("source directory not found", vim.log.levels.ERROR)
  end
  local c = conf()
  local entries = M.build(M.walk(src), src, c)
  if #entries == 0 then
    return notify("no source files to pick", vim.log.levels.WARN)
  end
  if c.backend then
    local backend = backends[c.backend]
    if not backend then
      return notify("unknown picker '" .. c.backend .. "'", vim.log.levels.ERROR)
    end
    return backend.open(entries)
  end
  for _, name in ipairs(ORDER) do
    if backends[name].avail() then
      return backends[name].open(entries)
    end
  end
end

return M
