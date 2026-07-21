-- blink.cmp completion source for chezmoi templates: template data keys
-- (from `chezmoi data`), template/sprig/chezmoi functions, and Go template
-- keywords. Active only inside {{ … }} in gotmpl buffers.
--
-- Register in your blink.cmp opts:
--   sources = {
--     default = { "chezmoi", ... },
--     providers = {
--       chezmoi = { name = "chezmoi", module = "chezmoi-template.blink" },
--     },
--   }
local M = {}

local KIND = { Function = 3, Variable = 6, Keyword = 14 }

local KEYWORDS = {
  "if", "else", "end", "range", "with", "template", "define", "block",
  "and", "or", "not", "eq", "ne", "lt", "le", "gt", "ge", "index", "len",
  "print", "printf", "println",
}

-- Curated: Go template + sprig + chezmoi-specific functions
local FUNCTIONS = {
  -- strings
  "quote", "squote", "upper", "lower", "title", "trim", "trimAll",
  "trimPrefix", "trimSuffix", "replace", "contains", "hasPrefix", "hasSuffix",
  "indent", "nindent", "repeat", "substr", "trunc", "cat",
  -- flow / defaults
  "default", "empty", "coalesce", "ternary", "required", "fail",
  -- collections
  "list", "dict", "get", "set", "hasKey", "keys", "values", "append",
  "prepend", "concat", "uniq", "has", "first", "rest", "last", "initial",
  "join", "split", "splitList", "sortAlpha",
  -- types / conversion
  "kindIs", "kindOf", "typeOf", "typeIs", "deepEqual", "toString", "atoi",
  "int", "int64", "float64", "toJson", "fromJson", "toYaml", "fromYaml",
  "toToml", "fromToml", "fromIni", "toIni",
  -- math
  "add", "sub", "mul", "div", "mod", "max", "min",
  -- regex
  "regexMatch", "regexFind", "regexFindAll", "regexReplaceAll", "regexSplit",
  -- encoding / hashing
  "b64enc", "b64dec", "sha256sum",
  -- environment / time
  "env", "expandenv", "now", "date",
  -- chezmoi
  "include", "includeTemplate", "joinPath", "lookPath", "stat", "glob",
  "output", "outputList", "eqFold", "quoteList", "replaceAllRegex",
  "decrypt", "encrypt", "promptString", "promptBool", "promptInt",
  "promptStringOnce", "promptBoolOnce", "promptIntOnce", "stdinIsATTY",
  "gitHubKeys", "gitHubLatestRelease", "ioreg", "mozillaInstallHash",
  "onepassword", "onepasswordRead", "bitwarden", "pass", "keepassxc",
  "keyring", "lastpass", "vault", "secret", "exit",
}

-- Flatten nested template data into dotted paths; tables recurse, arrays and
-- scalars are leaves. Exposed for tests.
function M.flatten(tbl, prefix, out)
  prefix = prefix or ""
  out = out or {}
  for k, v in pairs(tbl) do
    if type(k) == "string" then
      local path = prefix .. "." .. k
      if type(v) == "table" and not vim.islist(v) then
        M.flatten(v, path, out)
      else
        out[#out + 1] = { path = path, value = v }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  return out
end

local items_cache

local function items()
  if items_cache then
    return items_cache
  end
  items_cache = {}
  local data = require("chezmoi-template.resolve").data()
  if data then
    for _, e in ipairs(M.flatten(data)) do
      local value = vim.inspect(e.value)
      if #value > 200 then
        value = value:sub(1, 200) .. "…"
      end
      items_cache[#items_cache + 1] = {
        label = e.path,
        kind = KIND.Variable,
        insertText = e.path,
        documentation = { kind = "markdown", value = "```lua\n" .. value .. "\n```" },
      }
    end
  end
  for _, f in ipairs(FUNCTIONS) do
    items_cache[#items_cache + 1] = { label = f, kind = KIND.Function, insertText = f }
  end
  for _, k in ipairs(KEYWORDS) do
    items_cache[#items_cache + 1] = { label = k, kind = KIND.Keyword, insertText = k }
  end
  return items_cache
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  if vim.bo.filetype ~= "gotmpl" then
    return false
  end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, col)
  local open = before:match(".*(){{")
  local close = before:match(".*()}}")
  return open ~= nil and (close == nil or open > close)
end

function M:get_trigger_characters()
  return { "." }
end

function M:get_completions(_, callback)
  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items(),
  })
end

return M
