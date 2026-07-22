local format = require("chezmoi-template.format")

local failures = 0

local function run_case(name, target_ft, input, expected, check_masked)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].chezmoi_target_ft = target_ft
  local result, done
  format.formatter.format(nil, { buf = buf }, input, function(err, out)
    assert(not err, ("%s: formatter error: %s"):format(name, tostring(err)))
    result = out
    done = true
  end)
  vim.wait(5000, function()
    return done
  end)
  assert(done, name .. ": formatter did not finish")

  local ok = #result == #expected
  if ok then
    for i = 1, #expected do
      if result[i] ~= expected[i] then
        ok = false
        break
      end
    end
  end
  if not ok then
    failures = failures + 1
    print("FAIL " .. name)
    for i = 1, math.max(#result, #expected) do
      if result[i] ~= expected[i] then
        print(("  line %d\n    want: [%s]\n    got:  [%s]"):format(i, tostring(expected[i]), tostring(result[i])))
      end
    end
  elseif check_masked then
    local merr = check_masked(_G.captured_masked)
    if merr then
      failures = failures + 1
      print("FAIL " .. name .. " (masked check): " .. merr)
    else
      print("ok   " .. name)
    end
  else
    print("ok   " .. name)
  end
end

-- 1. zsh: nested directives round-trip; interior indent normalized
run_case("zsh nested if/range", "zsh", {
  '{{- if eq .chezmoi.os "darwin" }}',
  "{{- range .paths }}",
  'export PATH="{{ . }}:$PATH"',
  "{{- end }}",
  "{{- else }}",
  "echo other",
  "{{- end }}",
}, {
  '{{- if eq .chezmoi.os "darwin" }}',
  "{{-   range .paths }}",
  'export PATH="{{ . }}:$PATH"',
  "{{-   end }}",
  "{{- else }}",
  "echo other",
  "{{- end }}",
})

-- 2. toml: inline template after `=` masked as a quoted token, restored intact
run_case("toml inline value", "toml", {
  "[data]",
  "hostname = {{ .chezmoi.hostname | quote }}",
}, {
  "[data]",
  "hostname = {{ .chezmoi.hostname | quote }}",
}, function(masked)
  for _, l in ipairs(masked) do
    if l:match("^hostname") and not l:match('= "') then
      return "inline placeholder after = is not quoted: " .. l
    end
  end
end)

-- 3. json target: comment placeholders must be // (jsonc path)
run_case("json whole-line directive", "json", {
  "{",
  "{{- if .work }}",
  '  "email": {{ .work_email | quote }},',
  "{{- end }}",
  '  "name": "x"',
  "}",
}, {
  "{",
  "{{- if .work }}",
  '  "email": {{ .work_email | quote }},',
  "{{- end }}",
  '  "name": "x"',
  "}",
}, function(masked)
  for _, l in ipairs(masked) do
    if l:match("CHEZMOI_TMPL_%d+$") and not l:match("^%s*//") then
      return "whole-line placeholder is not a // comment: " .. l
    end
  end
end)

-- 4. html target: block commentstring — placeholder must be a CLOSED comment
run_case("html block comment placeholder", "html", {
  "<html>",
  "{{- if .fancy }}",
  "<body>hi</body>",
  "{{- end }}",
  "</html>",
}, {
  "<html>",
  "{{- if .fancy }}",
  "<body>hi</body>",
  "{{- end }}",
  "</html>",
}, function(masked)
  for _, l in ipairs(masked) do
    if l:find("<!--", 1, true) and not l:find("-->", 1, true) then
      return "unclosed comment placeholder: " .. l
    end
  end
end)

-- 5. collision: file already contains the sentinel literally
run_case("sentinel collision", "sh", {
  'echo "CHEZMOI_TMPL_1"',
  "{{- if .x }}",
  'echo "CHEZMOI_TMPL_2 stays"',
  "{{- end }}",
}, {
  'echo "CHEZMOI_TMPL_1"',
  "{{- if .x }}",
  'echo "CHEZMOI_TMPL_2 stays"',
  "{{- end }}",
})

-- 6. directive-interior indenter: installer-style block, mispadded input
run_case("directive indent depths", "sh", {
  "{{- $os := .chezmoi.os }}",
  "{{- range $name, $spec := .apps }}",
  '{{- $roles := get $spec "role" }}',
  '{{- if kindIs "string" $roles }}{{ $roles = list $roles }}{{ end }}',
  "{{- if .ok }}",
  '{{- $via := get $spec "via" }}',
  "{{- else if .other }}",
  '{{- $via := "apt" }}',
  "{{- end }}",
  "{{- end }}",
}, {
  "{{- $os := .chezmoi.os }}",
  "{{- range $name, $spec := .apps }}",
  '{{-   $roles := get $spec "role" }}',
  '{{-   if kindIs "string" $roles }}{{ $roles = list $roles }}{{ end }}',
  "{{-   if .ok }}",
  '{{-     $via := get $spec "via" }}',
  "{{-   else if .other }}",
  '{{-     $via := "apt" }}',
  "{{-   end }}",
  "{{- end }}",
})

-- 7. multi-line action span restored verbatim
run_case("multi-line span", "sh", {
  "{{- /* header comment",
  "       spanning lines */}}",
  "echo hi",
}, {
  "{{- /* header comment",
  "       spanning lines */}}",
  "echo hi",
})

-- Pure-function cases -------------------------------------------------------

local function eq(name, got, want)
  if not vim.deep_equal(got, want) then
    failures = failures + 1
    print(("FAIL %s\n  want: %s\n  got:  %s"):format(name, vim.inspect(want), vim.inspect(got)))
  else
    print("ok   " .. name)
  end
end

local diagnostics = require("chezmoi-template.diagnostics")
eq(
  "diagnostics parse line:col",
  diagnostics.parse('chezmoi: template: default:12:3: executing "default" at <.foo>: map has no entry for key "foo"'),
  {
    lnum = 11,
    col = 2,
    message = 'executing "default" at <.foo>: map has no entry for key "foo"',
    severity = vim.diagnostic.severity.ERROR,
    source = "chezmoi",
  }
)
eq(
  "diagnostics parse line only",
  diagnostics.parse("chezmoi: template: default:7: unexpected EOF"),
  { lnum = 6, col = 0, message = "unexpected EOF", severity = vim.diagnostic.severity.ERROR, source = "chezmoi" }
)
eq("diagnostics parse positionless", diagnostics.parse("chezmoi: some other failure").lnum, 0)

local blink = require("chezmoi-template.blink")

-- context-aware completions: snippets outside {{ }}, symbols inside
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "gotmpl"
  local src = blink.new()

  local function labels_at(line, col)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.api.nvim_win_set_cursor(0, { 1, col })
    local got
    src:get_completions(nil, function(res)
      got = res.items
    end)
    return got
  end

  local outside = labels_at("", 0)
  local has_if_snippet, has_fn = false, false
  for _, it in ipairs(outside) do
    if it.label == "if" and it.insertTextFormat == 2 and it.insertText:find("{{- end }}", 1, true) then
      has_if_snippet = true
    end
  end
  eq("blink outside {{ }} offers block snippets", has_if_snippet, true)

  local inside = labels_at("{{ .che }}", 7)
  local has_snippet = false
  for _, it in ipairs(inside) do
    if it.insertTextFormat == 2 then
      has_snippet = true
    end
    if it.label == "includeTemplate" then
      has_fn = true
    end
  end
  eq("blink inside {{ }} offers symbols, no snippets", { has_fn, has_snippet }, { true, false })
end

eq("blink mask secretish keys", {
  blink.masked(".github.token"),
  blink.masked(".age.recipients"),
  blink.masked(".chezmoi.hostname"),
  blink.masked(".work.api_url"),
}, { true, false, false, true })

eq("blink flatten", blink.flatten({ chezmoi = { hostname = "k", os = "darwin" }, roles = { "base" } }), {
  { path = ".chezmoi.hostname", value = "k" },
  { path = ".chezmoi.os", value = "darwin" },
  { path = ".roles", value = { "base" } },
})

local resolve = require("chezmoi-template.resolve")
eq("resolve_path attributes", resolve.resolve_path("private_dot_zshrc.tmpl"), ".zshrc")
eq(
  "resolve_path nested + encrypted",
  resolve.resolve_path("/src/exact_dot_config/encrypted_private_secrets.json.age"),
  "/src/.config/secrets.json"
)
eq("resolve_path relative stays relative", resolve.resolve_path("dot_config/foo.toml.tmpl"), ".config/foo.toml")
eq("invalidate clears without error", pcall(resolve.invalidate), true)

-- formatter resolves target ft from the buffer name when unseeded (BufNewFile)
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/chezmoi-src/dot_profile.tmpl") -- -> .profile -> sh
  local done
  format.formatter.format(nil, { buf = buf }, { "{{- if .x }}", "echo hi", "{{- end }}" }, function()
    done = true
  end)
  vim.wait(5000, function()
    return done
  end)
  local masked = false
  for _, l in ipairs(_G.captured_masked or {}) do
    if l:match("^#%s*CHEZMOI_TMPL_") then
      masked = true
    end
  end
  eq("format resolves ft from name when unseeded", masked, true)
end

if failures > 0 then
  error(failures .. " test case(s) failed")
end
print("all tests passed")
