-- blink.cmp completion source for chezmoi templates.
--
-- Inside {{ … }}: template data keys (from `chezmoi data`, icon reflects the
-- value's type), template/sprig/chezmoi functions, and Go template keywords.
-- Outside actions: block snippets ({{- if }} … {{- end }} and friends).
--
-- Register in your blink.cmp opts:
--   sources = {
--     default = { "chezmoi", ... },
--     providers = {
--       chezmoi = { name = "chezmoi", module = "chezmoi-template.blink" },
--     },
--   }
local M = {}

local KIND = { Function = 3, Variable = 6, Keyword = 14, Snippet = 15 }
local SNIPPET_FORMAT = 2 -- InsertTextFormat.Snippet

-- kind_icon by the completed thing, not just its LSP kind: data keys show
-- their value's type
local ICON = {
  string = "󰉿",
  number = "󰎠",
  boolean = "󰨙",
  table = "󰅩",
  func = "󰊕",
  keyword = "󰌋",
  snippet = "󱄽",
}

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

-- {{- if }} … {{- end }} and friends, as LSP snippets
local BLOCKS = {
  { label = "if",      body = "{{- if ${1:condition} }}\n$0\n{{- end }}" },
  { label = "ifelse",  body = "{{- if ${1:condition} }}\n$2\n{{- else }}\n$0\n{{- end }}" },
  { label = "range",   body = "{{- range ${1:.items} }}\n$0\n{{- end }}" },
  { label = "rangekv", body = "{{- range ${1:\\$k}, ${2:\\$v} := ${3:.items} }}\n$0\n{{- end }}" },
  { label = "with",    body = "{{- with ${1:.value} }}\n$0\n{{- end }}" },
  { label = "define",  body = "{{- define \"${1:name}\" }}\n$0\n{{- end }}" },
  { label = "block",   body = "{{- block \"${1:name}\" ${2:.} }}\n$0\n{{- end }}" },
  { label = "comment", body = "{{- /* $0 */}}" },
  { label = "tmpl",    body = "{{ template \"${1:name}\" ${2:.} }}" },
  { label = "inc",     body = "{{ includeTemplate \"${1:name}\" ${2:.} }}" },
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

local action_cache, block_cache

local function action_items()
  if action_cache then
    return action_cache
  end
  action_cache = {}
  local data = require("chezmoi-template.resolve").data()
  if data then
    for _, e in ipairs(M.flatten(data)) do
      local value = vim.inspect(e.value)
      if #value > 200 then
        value = value:sub(1, 200) .. "…"
      end
      action_cache[#action_cache + 1] = {
        label = e.path,
        kind = KIND.Variable,
        kind_icon = ICON[type(e.value)] or ICON.table,
        insertText = e.path,
        documentation = { kind = "markdown", value = "```lua\n" .. value .. "\n```" },
      }
    end
  end
  for _, f in ipairs(FUNCTIONS) do
    action_cache[#action_cache + 1] = { label = f, kind = KIND.Function, kind_icon = ICON.func, insertText = f }
  end
  for _, k in ipairs(KEYWORDS) do
    action_cache[#action_cache + 1] = { label = k, kind = KIND.Keyword, kind_icon = ICON.keyword, insertText = k }
  end
  return action_cache
end

local function block_items()
  if block_cache then
    return block_cache
  end
  block_cache = {}
  for _, b in ipairs(BLOCKS) do
    block_cache[#block_cache + 1] = {
      label = b.label,
      kind = KIND.Snippet,
      kind_icon = ICON.snippet,
      insertText = b.body,
      insertTextFormat = SNIPPET_FORMAT,
      documentation = {
        kind = "markdown",
        value = "```gotmpl\n" .. b.body:gsub("%${%d+:?([^}]*)}", "%1"):gsub("%$%d", "") .. "\n```",
      },
    }
  end
  return block_cache
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  return vim.bo.filetype == "gotmpl"
end

function M:get_trigger_characters()
  return { "." }
end

-- Inside an unclosed {{ … on this line?
local function in_action()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, col)
  local open = before:match(".*(){{")
  local close = before:match(".*()}}")
  return open ~= nil and (close == nil or open > close)
end

function M:get_completions(_, callback)
  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = in_action() and action_items() or block_items(),
  })
end

return M
