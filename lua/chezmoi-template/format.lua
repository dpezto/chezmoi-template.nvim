-- conform.nvim formatter: format a chezmoi *.tmpl by masking Go-template spans,
-- running the target filetype's formatter on the masked source, then restoring
-- the spans.
-- Per line: a line that is ONLY template directives -> a comment placeholder
-- (structurally inert; also covers multi-line {{ … }} spans); inline {{…}} ->
-- a unique token, quoted where it stands alone as a value so JSON/TOML stay
-- valid, bare where it is glued to identifier characters or sits inside a
-- string, so it nests into keys and words.
-- Not every line has a valid token form (`k = {{ .x }}suffix`,
-- `{{ if .on }}k = 1{{ end }}`), so a rejected mask is retried with every
-- template line replaced by a comment placeholder: those lines come back
-- untouched instead of failing the whole file.
local M = {}

M.formatter = {
  format = function(_, ctx, lines, callback)
    -- Normally seeded on BufReadPre; a new/unseeded buffer (BufNewFile,
    -- lazy-load) has none, so resolve the target filetype from the name here.
    local target_ft = vim.b[ctx.buf].chezmoi_target_ft
    if not target_ft or target_ft == "" then
      local name = vim.api.nvim_buf_get_name(ctx.buf)
      if name ~= "" then
        local resolve = require("chezmoi-template.resolve")
        local target = resolve.target_path(name) or resolve.resolve_path(vim.fn.fnamemodify(name, ":t"))
        target_ft = resolve.target_ft(target)
      end
    end
    if not target_ft or target_ft == "" or target_ft == "gotmpl" then
      return callback(nil, lines)
    end

    local is_json = target_ft:match("^json")
    local cms_ok, cms = pcall(vim.filetype.get_option, target_ft, "commentstring")
    cms = (not is_json and cms_ok) and cms or nil
    -- Split commentstring around %s: block-comment languages (html, css, c)
    -- need the closing part too or the placeholder is an unclosed comment.
    local prefix, suffix = is_json and "//" or "#", ""
    if cms and cms:find("%%s") then
      local p = vim.trim(cms:match("^(.-)%%s") or "")
      if p ~= "" then
        prefix = p
      end
      suffix = vim.trim(cms:match("%%s(.*)$") or "")
    end

    -- If the file itself contains the sentinel, restoring would corrupt it;
    -- lengthen until unique.
    local sentinel = "CHEZMOI_TMPL_"
    do
      local all = table.concat(lines, "\n")
      while all:find(sentinel, 1, true) do
        sentinel = sentinel .. "X"
      end
    end

    -- Two masking strengths. Fine (the default) turns each inline {{…}} into a
    -- token, so the formatter still lays the surrounding line out. Coarse
    -- replaces every template-bearing line with a comment placeholder: those
    -- lines come back untouched, but the placeholder is inert in any syntax, so
    -- the rest of the file still formats. Coarse is the retry for lines the
    -- fine pass cannot express — a template glued to a bare word
    -- (`k = {{ .x }}suffix`) or a control-flow pair wrapping content
    -- (`{{ if .on }}k = 1{{ end }}`); neither has a valid token form.
    -- map: placeholder -> original text. quoted: inline tokens the mask wrapped
    -- in quotes. cont: continuation lines of a multi-line span.
    local function build_mask(coarse)
      local masked, map, quoted, cont, open = {}, {}, {}, {}, false
      for i, line in ipairs(lines) do
        local key = prefix .. " " .. sentinel .. i .. (suffix ~= "" and " " .. suffix or "")
        local indent = line:match("^(%s*)")
        if open then -- continuation of a multi-line {{ … }} span
          masked[i] = key
          map[key] = line
          cont[key] = true
          open = not line:match("}}")
        elseif line:match("{{") and not line:match("}}") then -- opens a multi-line span
          open = true
          masked[i] = indent .. key
          map[key] = line:sub(#indent + 1)
        elseif line:match("{{") and (coarse or line:gsub("{{.-}}", ""):match(is_json and "^[%s,]*$" or "^%s*$")) then -- whole-line directive(s), or any template line under coarse masking
          masked[i] = indent .. key
          map[key] = line:sub(#indent + 1)
        elseif line:match("{{") then -- inline template(s) embedded in code
          local res, pos, j = "", 1, 0
          while pos <= #line do
            local s, e = line:find("{{", pos, true)
            if not s then
              res = res .. line:sub(pos)
              break
            end
            res = res .. line:sub(pos, s - 1)
            local t_end = e + 1
            while true do
              local e2 = line:find("}}", t_end, true)
              if not e2 then
                t_end = #line
                break
              end
              local _, q = line:sub(e + 1, e2 - 1):gsub('\\"', ""):gsub('"', "")
              if q % 2 == 0 then
                t_end = e2 + 1
                break
              end
              t_end = e2 + 2
            end
            j = j + 1
            local tmpl = line:sub(s, t_end)
            -- Quote only a standalone token (value position). A token glued to
            -- identifier chars is part of a bare key or word (`is_{{ $r }}`) —
            -- quoting it there splits the identifier and breaks TOML/JSON.
            local _, q = res:gsub('\\"', ""):gsub('"', "")
            local adjacent = res:sub(-1):match("[%w_%-%.]") or line:sub(t_end + 1, t_end + 1):match("[%w_%-%.]")
            -- The trailing "_" ends the token, so restore() can tell 1_1 from
            -- 1_11 even when digits follow it in the line.
            local k = sentinel .. i .. "_" .. j .. "_"
            map[k] = tmpl
            if q % 2 == 0 and not res:match('"$') and not adjacent then
              quoted[k] = true
              k = '"' .. k .. '"'
            end
            res = res .. k
            pos = t_end + 1
          end
          masked[i] = res
        else
          masked[i] = line
        end
      end
      return masked, map, quoted, cont
    end

    -- Format in a throwaway buffer named after the target in the source file's
    -- own directory, so formatters find the repo's config (stylua.toml,
    -- taplo.toml). The name drops .tmpl, so *.tmpl autocmds never fire on it;
    -- set the name and filetype with noautocmd so no LSP attaches to a buffer
    -- we delete mid-async. A formatter that needs a real file (stdin = false)
    -- gets a .conform.* temp file beside it; chezmoi ignores source names
    -- starting with a dot, so one left by an interrupted format is never applied.
    local function run(masked, cb)
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.bo[scratch].buftype = ""
      vim.api.nvim_buf_set_lines(scratch, 0, -1, false, masked)
      local real_name = vim.api.nvim_buf_get_name(ctx.buf)
      local name
      if real_name ~= "" then
        -- Encryption suffixes come last in a source name (foo.tmpl.age)
        name = real_name:gsub("%.age$", ""):gsub("%.asc$", ""):gsub("%.tmpl$", "")
        -- Ensure JSON targets are formatted as JSONC so the formatter accepts
        -- // comment placeholders
        if is_json then
          name = name:gsub("%.jsonc?$", ".jsonc")
          if not name:match("%.jsonc$") then
            name = name .. ".jsonc"
          end
        end
      end
      -- pcall: a second format started before the first finishes asks for the
      -- same name (E95); fail that one cleanly instead of leaking the scratch.
      local ok, setup_err = pcall(vim.api.nvim_buf_call, scratch, function()
        if name then
          vim.cmd("noautocmd keepalt file " .. vim.fn.fnameescape(name))
        end
        -- json.jsonc: conform tries jsonc formatters first, then json ones, so
        -- a formatter configured for json alone is still found.
        local scratch_ft = (target_ft == "json") and "json.jsonc" or target_ft
        vim.cmd("noautocmd setlocal filetype=" .. scratch_ft)
      end)
      if not ok then
        vim.api.nvim_buf_delete(scratch, { force = true })
        return cb(setup_err)
      end

      require("conform").format({ bufnr = scratch, async = true, lsp_format = "fallback" }, function(err, _)
        if err then
          vim.api.nvim_buf_delete(scratch, { force = true })
          return cb(err)
        end
        -- No early return when the underlying formatter changed nothing: the
        -- opener-indent pairing in restore() must still run.
        local formatted = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
        vim.api.nvim_buf_delete(scratch, { force = true })
        cb(nil, formatted)
      end)
    end

    -- Returns the restored lines, or nil when the formatter output cannot be
    -- mapped back exactly: a placeholder dropped, duplicated, or rewritten
    -- (an inline token's quotes escaped or removed). Accepting that output
    -- would silently delete template actions.
    local token_pat = "([\"']?)(" .. sentinel .. "%d+_%d+_)%1"
    local function restore(formatted, map, quoted, cont)
      local expected, restored = vim.tbl_count(map), 0

      -- Whole-line placeholders get the formatter's indent, except closing
      -- directives: formatters misplace a comment sitting before a closing
      -- token (shfmt leaves it at col 0 before `fi`), so pair {{end}}/{{else}}
      -- with their opener's indent via a stack instead.
      local indent_directives = require("chezmoi-template").config.format.indent_directives
      local final, stack = {}, {}
      for _, line in ipairs(formatted) do
        local indent = line:match("^(%s*)")
        local stripped = line:sub(#indent + 1)
        local tmpl = map[stripped]
        if tmpl then
          restored = restored + 1
          -- Depth of this line = stack size before its own pops/pushes;
          -- end/else belong to their opener's level.
          local depth = #stack
          local first_kw = tmpl:match("^{{%-?%s*(%w+)")
          if first_kw == "end" or first_kw == "else" then
            depth = math.max(0, depth - 1)
          end
          local first = true
          for kw in tmpl:gmatch("{{%-?%s*(%w+)") do
            if kw == "end" then
              local opener = table.remove(stack)
              if first and opener then
                indent = opener
              end
            elseif kw == "else" then
              if first and stack[#stack] then
                indent = stack[#stack]
              end
            elseif kw == "if" or kw == "range" or kw == "with" or kw == "block" or kw == "define" then
              stack[#stack + 1] = indent
            end
            first = false
          end
          if cont[stripped] then
            -- Inside a multi-line action: target-language indent would change
            -- the action itself (a raw string's interior lines), so verbatim.
            final[#final + 1] = tmpl
          else
            -- Directive-interior indent, only for column-0 `{{-` directives
            -- (data-munging header blocks): encode template nesting depth as
            -- padding INSIDE the action (1 space + 2 per level). Directives that
            -- participate in code layout (non-empty leading indent) keep their
            -- single space — the code indent already shows structure.
            if indent_directives and indent == "" and tmpl:match("^{{%-%s") then
              tmpl = tmpl:gsub("^{{%-%s+", "{{-" .. string.rep(" ", 1 + 2 * depth), 1)
            end
            final[#final + 1] = indent .. tmpl
          end
        else
          -- One pass per line. The mask's own quotes come off whichever quote
          -- character the formatter settled on; a bare token keeps whatever
          -- quotes surround it.
          line = line:gsub(token_pat, function(q, tok)
            local orig = map[tok]
            if not orig or (quoted[tok] and q == "") then
              return nil
            end
            restored = restored + 1
            return quoted[tok] and orig or q .. orig .. q
          end)
          if line:find(sentinel, 1, true) then
            return nil
          end
          final[#final + 1] = line
        end
      end

      if restored ~= expected then
        return nil
      end
      return final
    end

    local fine, fine_map, fine_quoted, fine_cont = build_mask(false)
    run(fine, function(err, formatted)
      local final = not err and restore(formatted, fine_map, fine_quoted, fine_cont)
      if final then
        return callback(nil, final)
      end
      -- The fine mask produced something the target formatter rejects, or
      -- output its tokens cannot be restored from. Retry with every template
      -- line inert, so one unmaskable line cannot block formatting the rest
      -- of the file.
      local coarse, coarse_map, coarse_quoted, coarse_cont = build_mask(true)
      run(coarse, function(coarse_err, coarse_formatted)
        if coarse_err then
          return callback(coarse_err)
        end
        local coarse_final = restore(coarse_formatted, coarse_map, coarse_quoted, coarse_cont)
        if not coarse_final then
          return callback("chezmoi: formatter output lost template placeholders")
        end
        callback(nil, coarse_final)
      end)
    end)
  end,
}

function M.setup()
  local function register()
    if not package.loaded["conform"] and not pcall(require, "conform") then
      return false
    end
    local conform = require("conform")
    conform.formatters.chezmoi = M.formatter
    if conform.formatters_by_ft.gotmpl == nil then
      conform.formatters_by_ft.gotmpl = { "chezmoi" }
    end
    return true
  end

  -- Don't force-load conform at startup; formatting can't happen before the
  -- first gotmpl FileType anyway. With a lazy-loaded conform the require can
  -- fail on early FileType events, so retry until it succeeds (returning true
  -- removes the autocmd).
  if not register() then
    vim.api.nvim_create_autocmd({ "FileType", "BufWritePre" }, {
      group = vim.api.nvim_create_augroup("chezmoi-template.format", { clear = true }),
      callback = function()
        return register()
      end,
    })
  end
end

return M
