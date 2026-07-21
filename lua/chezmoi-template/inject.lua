-- Treesitter injection of the deployed target language into gotmpl buffers,
-- plus the autocmds that seed each buffer's target filetype/language.
local M = {}

local resolve = require("chezmoi-template.resolve")

local function augroup(name)
  return vim.api.nvim_create_augroup("chezmoi-template." .. name, { clear = true })
end

function M.setup()
  -- The (text) nodes of a gotmpl tree carry the target file's content; this
  -- directive tells treesitter which language to parse them as.
  vim.treesitter.query.add_directive("inject-chezmoi!", function(_, _, source, _, metadata)
    local bufnr = type(source) == "number" and source or vim.api.nvim_get_current_buf()
    if vim.b[bufnr] and vim.b[bufnr].chezmoi_target_lang then
      if pcall(vim.treesitter.language.add, vim.b[bufnr].chezmoi_target_lang) then
        metadata["injection.language"] = vim.b[bufnr].chezmoi_target_lang
        metadata["injection.combined"] = true
      end
      return
    end

    -- No seeded language (unmanaged *.tmpl, or chezmoi unavailable):
    -- fall back to pure attribute stripping of the buffer name.
    local resolved = resolve.resolve_path(vim.api.nvim_buf_get_name(bufnr))
    local ft = vim.filetype.match({ filename = resolved })
    if ft then
      local lang = vim.treesitter.language.get_lang(ft) or ft
      if pcall(vim.treesitter.language.add, lang) then
        metadata["injection.language"] = lang
        metadata["injection.combined"] = true
      end
    end
  end, { force = true })

  -- Detect target language for *.tmpl files BEFORE FileType/TS sets up.
  -- BufReadPre fires synchronously before the file is read and before TS
  -- initializes, so chezmoi_target_lang is available when the directive runs.
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = augroup("tmpl"),
    pattern = { "*.tmpl", ".chezmoiignore*", ".chezmoiremove*", ".chezmoiexternal*" },
    callback = function(ctx)
      if not resolve.is_managed(ctx.file) then
        return
      end
      -- .chezmoitemplates/ partials have no deploy target; infer from own basename
      local target = resolve.target_path(ctx.file) or vim.fn.fnamemodify(ctx.file, ":t")
      local ft
      if target:match("^%.chezmoiignore") or target:match("^%.chezmoiremove") then
        ft = "gitignore"
      else
        ft = resolve.target_ft(target)
      end
      resolve.seed(ctx.buf, ft)
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
end

return M
