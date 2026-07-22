-- blink.cmp completion source for chezmoi templates.
--
-- Context-aware via the gotmpl treesitter tree (falls back to a line regex when
-- the parser is absent):
--   • after a dot (.foo): data keys only (from `chezmoi data`, icon by value type)
--   • command position inside {{ }}: data keys + template/sprig/chezmoi functions
--     + Go template keywords
--   • inside a string literal: nothing (stays out of the way)
--   • outside actions: block snippets ({{- if }} … {{- end }} and friends)
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
-- their value's type. kind_hl must accompany a custom kind_icon or blink
-- renders the glyph unhighlighted (flat foreground).
local ICON = {
  string = { "󰉿", "@string" },
  number = { "󰎠", "@number" },
  boolean = { "󰨙", "@boolean" },
  table = { "󰅩", "@property" },
  func = { "󰊕", "@function" },
  keyword = { "󰌋", "@keyword" },
  snippet = { "󱄽", "@constructor" },
}

-- stylua: ignore
local KEYWORDS = {
  "if", "else", "end", "range", "with", "template", "define", "block",
  "and", "or", "not", "eq", "ne", "lt", "le", "gt", "ge", "index", "len",
  "print", "printf", "println",
}

-- Curated: Go template + sprig + chezmoi-specific functions
local FUNCTIONS = {
  -- strings
  "quote",
  "squote",
  "upper",
  "lower",
  "title",
  "trim",
  "trimAll",
  "trimPrefix",
  "trimSuffix",
  "replace",
  "contains",
  "hasPrefix",
  "hasSuffix",
  "indent",
  "nindent",
  "repeat",
  "substr",
  "trunc",
  "cat",
  -- flow / defaults
  "default",
  "empty",
  "coalesce",
  "ternary",
  "required",
  "fail",
  -- collections
  "list",
  "dict",
  "get",
  "set",
  "hasKey",
  "keys",
  "values",
  "append",
  "prepend",
  "concat",
  "uniq",
  "has",
  "first",
  "rest",
  "last",
  "initial",
  "join",
  "split",
  "splitList",
  "sortAlpha",
  -- types / conversion
  "kindIs",
  "kindOf",
  "typeOf",
  "typeIs",
  "deepEqual",
  "toString",
  "atoi",
  "int",
  "int64",
  "float64",
  "toJson",
  "fromJson",
  "toYaml",
  "fromYaml",
  "toToml",
  "fromToml",
  "fromIni",
  "toIni",
  -- math
  "add",
  "sub",
  "mul",
  "div",
  "mod",
  "max",
  "min",
  -- regex
  "regexMatch",
  "regexFind",
  "regexFindAll",
  "regexReplaceAll",
  "regexSplit",
  -- encoding / hashing
  "b64enc",
  "b64dec",
  "sha256sum",
  -- environment / time
  "env",
  "expandenv",
  "now",
  "date",
  -- chezmoi
  "include",
  "includeTemplate",
  "joinPath",
  "lookPath",
  "stat",
  "glob",
  "output",
  "outputList",
  "eqFold",
  "quoteList",
  "replaceAllRegex",
  "decrypt",
  "encrypt",
  "promptString",
  "promptBool",
  "promptInt",
  "promptStringOnce",
  "promptBoolOnce",
  "promptIntOnce",
  "stdinIsATTY",
  "gitHubKeys",
  "gitHubLatestRelease",
  "ioreg",
  "mozillaInstallHash",
  "onepassword",
  "onepasswordRead",
  "bitwarden",
  "pass",
  "keepassxc",
  "keyring",
  "lastpass",
  "vault",
  "secret",
  "exit",
}

-- {{- if }} … {{- end }} and friends, as LSP snippets
local BLOCKS = {
  { label = "if", body = "{{- if ${1:condition} }}\n$0\n{{- end }}" },
  { label = "ifelse", body = "{{- if ${1:condition} }}\n$2\n{{- else }}\n$0\n{{- end }}" },
  { label = "range", body = "{{- range ${1:.items} }}\n$0\n{{- end }}" },
  { label = "rangekv", body = "{{- range ${1:\\$k}, ${2:\\$v} := ${3:.items} }}\n$0\n{{- end }}" },
  { label = "with", body = "{{- with ${1:.value} }}\n$0\n{{- end }}" },
  { label = "define", body = '{{- define "${1:name}" }}\n$0\n{{- end }}' },
  { label = "block", body = '{{- block "${1:name}" ${2:.} }}\n$0\n{{- end }}' },
  { label = "comment", body = "{{- /* $0 */}}" },
  { label = "tmpl", body = '{{ template "${1:name}" ${2:.} }}' },
  { label = "inc", body = '{{ includeTemplate "${1:name}" ${2:.} }}' },
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

-- Should this data key's value be hidden in completion docs?
-- Matches config.completion.mask lua patterns against the lowercased path.
function M.masked(path)
  local patterns = require("chezmoi-template").config.completion.mask
  local lower = path:lower()
  for _, pat in ipairs(patterns) do
    if lower:match(pat) then
      return true
    end
  end
  return false
end

local data_cache, action_cache, block_cache

-- Data-key items go stale with `chezmoi data`; called on FocusGained (init.lua).
-- action_cache embeds the data items, so both drop together.
function M.invalidate()
  data_cache = nil
  action_cache = nil
end

local function item(label, icon_spec, extra)
  local it = { label = label, insertText = label, kind_icon = icon_spec[1], kind_hl = icon_spec[2] }
  for k, v in pairs(extra) do
    it[k] = v
  end
  return it
end

-- Just the `chezmoi data` keys (dotted paths). Offered alone after a `.`, where
-- functions/keywords can't appear.
local function data_items()
  if data_cache then
    return data_cache
  end
  data_cache = {}
  local data = require("chezmoi-template.resolve").data()
  if data then
    for _, e in ipairs(M.flatten(data)) do
      local value
      if M.masked(e.path) then
        value = "•••••"
      else
        value = vim.inspect(e.value)
        if #value > 200 then
          value = value:sub(1, 200) .. "…"
        end
      end
      -- lua fence so blink's treesitter docs highlight the value by type
      -- (true=boolean, 1=number, "x"=string) — needs the markdown_inline parser
      data_cache[#data_cache + 1] = item(e.path, ICON[type(e.value)] or ICON.table, {
        kind = KIND.Variable,
        documentation = { kind = "markdown", value = "```lua\n" .. value .. "\n```" },
      })
    end
  end
  return data_cache
end

-- Everything valid at command position: data keys + functions + keywords.
local function action_items()
  if action_cache then
    return action_cache
  end
  action_cache = vim.list_extend({}, data_items())
  for _, f in ipairs(FUNCTIONS) do
    action_cache[#action_cache + 1] = item(f, ICON.func, { kind = KIND.Function })
  end
  for _, k in ipairs(KEYWORDS) do
    action_cache[#action_cache + 1] = item(k, ICON.keyword, { kind = KIND.Keyword })
  end
  return action_cache
end

local function block_items()
  if block_cache then
    return block_cache
  end
  block_cache = {}
  for _, b in ipairs(BLOCKS) do
    block_cache[#block_cache + 1] = item(b.label, ICON.snippet, {
      kind = KIND.Snippet,
      insertText = b.body,
      insertTextFormat = SNIPPET_FORMAT,
      documentation = {
        kind = "markdown",
        value = "```gotmpl\n" .. b.body:gsub("%${%d+:?([^}]*)}", "%1"):gsub("%$%d", "") .. "\n```",
      },
    })
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

-- Fallback context probe when the gotmpl parser is absent: inside an unclosed
-- {{ … on the current line? Single-line only — the treesitter path handles the
-- multiline and in-string cases this misses.
local function in_action()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, col)
  local open = before:match(".*(){{")
  local close = before:match(".*()}}")
  return open ~= nil and (close == nil or open > close)
end

-- Cursor token preceded by a dot (`.foo|`, `.a.b|`) — field access, where only
-- data keys are valid (not functions/keywords). Works with or without the
-- parser, so positional narrowing degrades gracefully.
local function after_dot()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  return vim.api.nvim_get_current_line():sub(1, col):match("%.[%w_]*$") ~= nil
end

local STRING_NODES = { interpreted_string_literal = true, raw_string_literal = true }

-- Classify the cursor via the gotmpl tree: "action" (inside {{ }}), "string"
-- (inside a string literal — suppress), or "text" (target-language body).
-- Returns nil when no gotmpl parser is available, so the caller falls back to
-- in_action(). The stable invariant: gotmpl parses the target body as opaque
-- `text` nodes (that's what injection consumes), so anything else is an action.
local function ts_where()
  local ok, res = pcall(function()
    local parser = vim.treesitter.get_parser(0, "gotmpl")
    if not parser then
      return nil
    end
    parser:parse(true)
    local node = vim.treesitter.get_node()
    if not node then
      return "text"
    end
    local n = node
    while n do
      if STRING_NODES[n:type()] then
        return "string"
      end
      n = n:parent()
    end
    return node:type() == "text" and "text" or "action"
  end)
  return ok and res or nil
end

-- "block" | "field" | "command" | "suppress"
local function context()
  local where = ts_where() or (in_action() and "action" or "text")
  if where == "string" then
    return "suppress"
  end
  if where ~= "action" then
    return "block"
  end
  return after_dot() and "field" or "command"
end

function M:get_completions(_, callback)
  local ctx = context()
  local items
  if ctx == "field" then
    items = data_items()
  elseif ctx == "command" then
    items = action_items()
  elseif ctx == "suppress" then
    items = {}
  else
    items = block_items()
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
