-- conform.nvim formatter: format a chezmoi *.tmpl by masking Go-template spans,
-- running the target filetype's formatter on the masked source, then restoring
-- the spans.
-- Per line: a line that is ONLY template directives -> a comment placeholder
-- (structurally inert; also covers multi-line {{ … }} spans); inline {{…}} ->
-- a unique token, quoted after = / : so JSON/TOML stay valid, bare otherwise
-- so it nests inside strings and identifiers.
local M = {}

M.formatter = {
  format = function(_, ctx, lines, callback)
    local target_ft = vim.b[ctx.buf].chezmoi_target_ft
    if not target_ft then
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

    local masked, map, open = {}, {}, false
    for i, line in ipairs(lines) do
      local key = prefix .. " " .. sentinel .. i .. (suffix ~= "" and " " .. suffix or "")
      local indent = line:match("^(%s*)")
      if open then -- continuation of a multi-line {{ … }} span
        masked[i] = key
        map[key] = line
        open = not line:match("}}")
      elseif line:match("{{") and not line:match("}}") then -- opens a multi-line span
        open = true
        masked[i] = indent .. key
        map[key] = line:sub(#indent + 1)
      elseif line:match("{{") and line:gsub("{{.-}}", ""):match(is_json and "^[%s,]*$" or "^%s*$") then -- whole-line directive(s)
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
          local _, q = res:gsub('\\"', ""):gsub('"', "")
          local k = sentinel .. i .. "_" .. j
          k = (q % 2 == 0 and not res:match('"$')) and '"' .. k .. '"' or k
          map[k] = tmpl
          res = res .. k
          pos = t_end + 1
        end
        masked[i] = res
      else
        masked[i] = line
      end
    end

    -- Format in a throwaway buffer named in a temp dir (NOT the chezmoi source
    -- dir) so *.tmpl autocmds never fire on it; set the name and filetype with
    -- noautocmd so no LSP attaches to a buffer we delete mid-async.
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.bo[scratch].buftype = ""
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, masked)
    local real_name = vim.api.nvim_buf_get_name(ctx.buf)
    local name
    if real_name ~= "" then
      name = real_name:gsub("%.tmpl$", ""):gsub("%.age$", "")
      -- Ensure JSON targets are formatted as JSONC so the formatter accepts
      -- // comment placeholders
      if is_json then
        name = name:gsub("%.jsonc?$", ".jsonc")
        if not name:match("%.jsonc$") then
          name = name .. ".jsonc"
        end
      end
    end
    vim.api.nvim_buf_call(scratch, function()
      if name then
        vim.cmd("noautocmd keepalt file " .. vim.fn.fnameescape(name))
      end
      local scratch_ft = (target_ft == "json") and "jsonc" or target_ft
      vim.cmd("noautocmd setlocal filetype=" .. scratch_ft)
    end)

    require("conform").format({ bufnr = scratch, async = true, lsp_format = "fallback" }, function(err, _)
      if err then
        vim.api.nvim_buf_delete(scratch, { force = true })
        return callback(err)
      end
      -- No early return when the underlying formatter changed nothing: the
      -- opener-indent pairing below must still run.
      local formatted = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
      vim.api.nvim_buf_delete(scratch, { force = true })

      local keys = vim.tbl_keys(map)
      table.sort(keys, function(a, b)
        return #a > #b
      end)

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
          -- Directive-interior indent, only for column-0 `{{-` directives
          -- (data-munging header blocks): encode template nesting depth as
          -- padding INSIDE the action (1 space + 2 per level). Directives that
          -- participate in code layout (non-empty leading indent) keep their
          -- single space — the code indent already shows structure.
          if indent_directives and indent == "" and tmpl:match("^{{%-%s") then
            tmpl = tmpl:gsub("^{{%-%s+", "{{-" .. string.rep(" ", 1 + 2 * depth), 1)
          end
          final[#final + 1] = indent .. tmpl
        else
          for _, k in ipairs(keys) do
            line = line:gsub(k, function()
              return map[k]
            end)
          end
          final[#final + 1] = line
        end
      end

      callback(nil, final)
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
