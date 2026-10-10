-- Treesitter injection of the deployed target language into gotmpl buffers,
-- plus the autocmds that seed each buffer's target filetype/language.
local M = {}

local resolve = require("chezmoi-template.resolve")

local function augroup(name)
  return vim.api.nvim_create_augroup("chezmoi-template." .. name, { clear = true })
end

-- The (text) nodes of a gotmpl tree carry the target file's content; this
-- directive tells treesitter which language to parse them as. It must be
-- registered before any gotmpl tree is parsed (highlighting, vim-matchup,
-- render-markdown, …), so the plugin/ bootstrap registers it at startup —
-- treesitter errors "No handler for inject-chezmoi!" otherwise. Registration is
-- cheap; the callback only touches `resolve` when a tree is actually parsed.
function M.register_directive()
  vim.treesitter.query.add_directive("inject-chezmoi!", function(_, _, source, _, metadata)
    local bufnr = type(source) == "number" and source or vim.api.nvim_get_current_buf()
    -- Checked here, not only when seeding: an unseeded buffer takes the name
    -- fallback below, which would inject anyway.
    local cfg = require("chezmoi-template").config.inject
    if not cfg.enabled then
      return
    end
    local name = vim.api.nvim_buf_get_name(bufnr)
    local nname = vim.fs.normalize(name)
    for _, pat in ipairs(cfg.exclude) do
      if nname:match(pat) then
        return
      end
    end

    local lang = vim.b[bufnr] and vim.b[bufnr].chezmoi_target_lang
    if not lang then
      -- No seeded language (unmanaged *.tmpl, or chezmoi unavailable):
      -- fall back to pure attribute stripping of the buffer name.
      local ft = vim.filetype.match({ filename = resolve.resolve_path(name) })
      lang = ft and (vim.treesitter.language.get_lang(ft) or ft)
    end
    -- A target that is itself a template (literal_x.tmpl, x.tmpl.literal)
    -- would inject gotmpl into its own text nodes, recursively.
    if lang and lang ~= "gotmpl" and resolve.has_parser(lang) then
      metadata["injection.language"] = lang
      metadata["injection.combined"] = true
    end
  end, { force = true })
end

-- Seed a buffer's chezmoi_target_lang from its source path. Callable directly
-- (the lazy bootstrap uses it for the buffer that triggered loading, whose
-- BufReadPre has already passed) or from the BufReadPre autocmd below.
function M.seed_buffer(buf, file)
  if not resolve.is_managed(file) then
    return
  end
  -- Excluded paths stay plain gotmpl (no target-language injection). Match the
  -- normalized (forward-slash) path so patterns are portable across OSes — a
  -- raw autocmd path is backslashed on Windows and would dodge "/"-style patterns.
  local nfile = vim.fs.normalize(file)
  for _, pat in ipairs(require("chezmoi-template").config.inject.exclude) do
    if nfile:match(pat) then
      return
    end
  end
  -- No deploy target (.chezmoitemplates/ partials, .chezmoiscripts/):
  -- infer from the attribute-stripped basename (run_once_foo.sh.tmpl -> foo.sh).
  -- The prefetched source set (one spawn per session) skips the doomed
  -- per-file `target-path` spawn for exactly those files.
  local sset = resolve.source_set()
  local fallback = resolve.resolve_path(vim.fn.fnamemodify(file, ":t"))
  local target
  if sset and not sset[vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))] then
    target = fallback
  else
    target = resolve.target_path(file) or fallback
  end
  local ft
  if target:match("^%.chezmoiignore") or target:match("^%.chezmoiremove") then
    ft = "gitignore"
  else
    ft = resolve.target_ft(target)
  end
  resolve.seed(buf, ft)
end

function M.setup()
  M.register_directive()

  -- Detect target language for *.tmpl files BEFORE FileType/TS sets up.
  -- BufReadPre fires synchronously before the file is read and before TS
  -- initializes, so chezmoi_target_lang is available when the directive runs.
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = augroup("tmpl"),
    pattern = { "*.tmpl", ".chezmoiignore*", ".chezmoiremove*", ".chezmoiexternal*" },
    callback = function(ctx)
      M.seed_buffer(ctx.buf, ctx.file)
    end,
  })

  -- Files chezmoi always interprets as templates regardless of .tmpl extension:
  --   • .chezmoitemplates/ partials (never deployed, no target path)
  --   • .chezmoiignore / .chezmoiremove / .chezmoiexternal.$FORMAT
  -- Extension detection wins over vim.filetype.add patterns, so this runs
  -- BufReadPost after the (wrong) filetype is set: seed chezmoi_target_lang from
  -- the basename, then force filetype = gotmpl, which fires a fresh FileType
  -- event that treesitter attaches to.
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup("templates"),
    pattern = { "**/.chezmoitemplates/**", "**/.chezmoiignore*", "**/.chezmoiremove*", "**/.chezmoiexternal.*" },
    callback = function(ctx)
      -- .tmpl variants already get gotmpl via extension detection + BufReadPre seed
      if vim.bo[ctx.buf].filetype == "gotmpl" then
        return
      end
      if not resolve.is_managed(ctx.file) then
        return
      end
      local basename = vim.fn.fnamemodify(ctx.file, ":t")
      local ft = vim.filetype.match({ filename = basename })
      if ft and ft ~= "" and ft ~= "gotmpl" then
        resolve.seed(ctx.buf, ft)
      end
      vim.bo[ctx.buf].filetype = "gotmpl"
    end,
  })

  -- Plain (non-template) managed sources carry chezmoi attributes in their
  -- name, so nvim detects dot_zshrc as conf (or nothing) instead of zsh. Retype
  -- from the deployed path once the buffer is read. Templates are already
  -- gotmpl by now; encrypted files are typed by encryption.lua after decryption.
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup("plain"),
    pattern = "*",
    callback = function(ctx)
      local nfile = vim.fs.normalize(ctx.file)
      if
        ctx.file == ""
        or vim.bo[ctx.buf].buftype ~= ""
        or vim.bo[ctx.buf].filetype == "gotmpl"
        or nfile:match("%.age$")
        or nfile:match("%.asc$")
        or not resolve.is_managed(ctx.file)
      then
        return
      end
      local target = resolve.target_path(ctx.file)
      if not target then
        return
      end
      local ft = vim.filetype.match({ filename = target, buf = ctx.buf })
      if ft and ft ~= vim.bo[ctx.buf].filetype then
        resolve.seed(ctx.buf, ft)
        vim.bo[ctx.buf].filetype = ft
      end
    end,
  })
end

return M
