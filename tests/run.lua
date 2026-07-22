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

-- context-aware completions. No gotmpl parser in this env, so ts_where() returns
-- nil and the in_action() line regex drives in/out; after_dot() drives
-- field-vs-command. Probe positional narrowing with the static `includeTemplate`
-- function (data_items is empty here — fake `chezmoi data` isn't wired up yet).
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "gotmpl"
  local src = blink.new()

  local function scan(line, col)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.api.nvim_win_set_cursor(0, { 1, col })
    local items
    src:get_completions(nil, function(res)
      items = res.items
    end)
    local has_if_snippet, has_fn, has_snippet = false, false, false
    for _, it in ipairs(items) do
      if it.insertTextFormat == 2 then
        has_snippet = true
      end
      if it.label == "if" and it.insertTextFormat == 2 and it.insertText:find("{{- end }}", 1, true) then
        has_if_snippet = true
      end
      if it.label == "includeTemplate" then
        has_fn = true
      end
    end
    return { snippet = has_if_snippet, fn = has_fn, any_snippet = has_snippet }
  end

  -- outside any action: block snippets, no functions
  eq("blink outside {{ }} offers block snippets", scan("", 0).snippet, true)

  -- command position (no leading dot): functions offered, no snippets
  local cmd = scan("{{ inclu }}", 8)
  eq("blink command position offers functions, no snippets", { cmd.fn, cmd.any_snippet }, { true, false })

  -- field position (after a dot): data keys only — functions absent, no snippets
  local field = scan("{{ .che }}", 7)
  eq("blink field position offers no functions/snippets", { field.fn, field.any_snippet }, { false, false })

  -- treesitter-only cases (skipped in CI where the gotmpl parser is absent):
  -- multiline actions the line regex can't see, and string-literal suppression.
  local ok_parser, parser = pcall(vim.treesitter.get_parser, buf, "gotmpl")
  if ok_parser and parser then
    -- action spans two lines; cursor is on line 2 after `.che`. The single-line
    -- regex would read this as outside an action (block snippets); treesitter
    -- correctly sees field position.
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "{{", ".che", "}}" })
    vim.api.nvim_win_set_cursor(0, { 2, 4 })
    local ml
    src:get_completions(nil, function(res)
      ml = res.items
    end)
    local ml_fn, ml_snip = false, false
    for _, it in ipairs(ml) do
      if it.label == "includeTemplate" then
        ml_fn = true
      end
      if it.insertTextFormat == 2 then
        ml_snip = true
      end
    end
    eq("blink multiline action is field position", { ml_fn, ml_snip }, { false, false })

    -- cursor inside a string literal: no completions dumped
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{{ template "na" }}' })
    vim.api.nvim_win_set_cursor(0, { 1, 14 })
    local instr
    src:get_completions(nil, function(res)
      instr = res.items
    end)
    eq("blink suppresses completion inside string literals", #instr, 0)
  end
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
-- A drive-letter root is preserved as a prefix, not attribute-stripped. This
-- runs on every OS: "C:/" survives vim.fs.normalize unchanged, and `^%a:/`
-- can't match a normal Unix path, so the branch needs no has("win32") gate.
eq("resolve_path drive-letter root", resolve.resolve_path("C:/src/private_dot_zshrc.tmpl"), "C:/src/.zshrc")
-- Backslash normalization and UNC-root preservation depend on vim.fs.normalize's
-- Windows behavior (converts `\`→`/`, keeps `//server/share`); off-Windows it
-- neither converts backslashes nor keeps `//`. Verified on the Windows CI leg.
if vim.fn.has("win32") == 1 then
  eq("resolve_path backslashes normalize", resolve.resolve_path("C:\\src\\dot_zshrc.tmpl"), "C:/src/.zshrc")
  eq(
    "resolve_path UNC root preserved",
    resolve.resolve_path("\\\\server\\share\\dot_config\\foo.toml.tmpl"),
    "//server/share/.config/foo.toml"
  )
end
eq("resolve_path symlink_", resolve.resolve_path("symlink_dot_foo"), ".foo")
eq("resolve_path create_", resolve.resolve_path("create_dot_bar"), ".bar")
eq("resolve_path modify_", resolve.resolve_path("modify_dot_baz.tmpl"), ".baz")
eq("resolve_path remove_", resolve.resolve_path("remove_dot_qux"), ".qux")
-- literal_ ends attribute parsing: dot_ stays literal (matches real chezmoi)
eq("resolve_path literal_ keeps rest verbatim", resolve.resolve_path("literal_dot_quux"), "dot_quux")
eq("resolve_path prefix before literal_ still strips", resolve.resolve_path("private_literal_dot_q"), "dot_q")
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

-- ==== CLI-stubbed integration tests ===================================
-- Fake `chezmoi` at the vim.system boundary: canned replies per subcommand.
-- Everything below exercises real plugin behavior (autocmds, user commands,
-- buffers) without the chezmoi binary.

local SRC = vim.fs.normalize(vim.fn.getcwd()) .. "/tests" -- source_dir configured in minimal_init

-- buffer name normalized to forward slashes: nvim_buf_get_name may return
-- backslashes on Windows, but SRC and every resolve.lua path use "/"
local function bufname(buf)
  return vim.fs.normalize(vim.api.nvim_buf_get_name(buf or 0))
end

local fake = {} -- subcommand -> canned vim.system result
local spawns = {} -- subcommand -> call count
local sent = {} -- subcommand -> full cmd array of the last spawn (for flag asserts)
local real_system = vim.system
---@diagnostic disable-next-line: duplicate-set-field
vim.system = function(cmd, _, cb)
  if cmd[1] ~= "chezmoi" then
    return real_system(cmd, _, cb)
  end
  local key = cmd[2]
  spawns[key] = (spawns[key] or 0) + 1
  sent[key] = cmd
  local ret = vim.deepcopy(fake[key] or { code = 1, stdout = "", stderr = "no fake for " .. key })
  if cb then
    cb(ret)
  end
  return {
    wait = function()
      return ret
    end,
  }
end
resolve.has_chezmoi = function()
  return true
end

local notes = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = msg, level = level }
end
local function has_note(pat)
  for _, n in ipairs(notes) do
    if n.msg:find(pat, 1, true) then
      return true
    end
  end
  return false
end
local function clear_notes()
  for i = #notes, 1, -1 do
    notes[i] = nil
  end
end

-- resolve: target-path spawn is trimmed and cached
fake["target-path"] = { code = 0, stdout = SRC .. "/.zshrc\n" }
eq("target_path trims stdout", resolve.target_path(SRC .. "/dot_zshrc.tmpl"), SRC .. "/.zshrc")
local tp_spawns = spawns["target-path"]
resolve.target_path(SRC .. "/dot_zshrc.tmpl")
eq("target_path cached (no respawn)", spawns["target-path"], tp_spawns)

-- resolve: data caching + invalidation + broken json
fake["data"] = { code = 0, stdout = '{"chezmoi":{"os":"darwin"},"email":"e@x"}' }
resolve.invalidate()
eq("data decodes chezmoi data json", resolve.data().chezmoi.os, "darwin")
fake["data"] = { code = 0, stdout = "not json" }
eq("data cached across calls", resolve.data().email, "e@x")
resolve.invalidate()
eq("data invalid json -> nil", resolve.data(), nil)

-- resolve: managed set + source-dir membership
fake["managed"] = { code = 0, stdout = "/home/u/.zshrc\n/home/u/.config/foo.toml\n" }
resolve.invalidate()
eq("managed_set O(1) lookup", resolve.managed_set()["/home/u/.zshrc"], true)
eq("is_managed inside source dir", resolve.is_managed(SRC .. "/dot_zshrc.tmpl"), true)
eq("is_managed outside source dir", resolve.is_managed("/etc/passwd"), false)

-- resolve: seed + target_ft (filetype.match path and scratch fallback path)
do
  local b = vim.api.nvim_create_buf(false, true)
  resolve.seed(b, "sh")
  eq("seed records target ft", vim.b[b].chezmoi_target_ft, "sh")
  resolve.seed(b, "lua") -- bundled parser: lang gets recorded too
  eq("seed records lang when parser exists", vim.b[b].chezmoi_target_lang, "lua")
  eq("target_ft via filetype.match", resolve.target_ft("/x/.zshrc"), "zsh")
  eq("target_ft unknown -> nil", resolve.target_ft("/x/no-ft-here-xyz"), nil)
end

-- icons: wrapped mini.icons resolves chezmoi source names
package.preload["mini.icons"] = function()
  return {
    get = function(_, name)
      return name, "TestHl", false
    end,
  }
end
require("mini.icons")
local icons = require("chezmoi-template.icons")
eq("icons.attach wraps mini.icons", icons.attach(), true)
eq("wrapped mi.get resolves source names", require("mini.icons").get("file", "private_dot_zshrc.tmpl"), ".zshrc")
eq("wrapped mi.get passes plain names through", require("mini.icons").get("file", "plain.txt"), "plain.txt")
eq("icons.get resolves chezmoi paths", icons.get("dot_gitconfig.tmpl"), ".gitconfig")
eq("icons.get non-chezmoi -> nil", icons.get("/x/plain.txt"), nil)

-- inject.seed_buffer: fallback via attribute stripping, .chezmoiignore special-case
do
  local inject = require("chezmoi-template.inject")
  fake["managed"] = { code = 0, stdout = "" } -- empty source set -> fallback
  resolve.invalidate()
  local b = vim.api.nvim_create_buf(false, true)
  inject.seed_buffer(b, SRC .. "/dot_profile.tmpl")
  eq("seed_buffer fallback ft from stripped name", vim.b[b].chezmoi_target_ft, "sh")
  local b2 = vim.api.nvim_create_buf(false, true)
  inject.seed_buffer(b2, SRC .. "/.chezmoiignore.tmpl")
  eq("seed_buffer .chezmoiignore -> gitignore", vim.b[b2].chezmoi_target_ft, "gitignore")
  local b3 = vim.api.nvim_create_buf(false, true)
  inject.seed_buffer(b3, "/outside/dot_x.tmpl")
  eq("seed_buffer ignores unmanaged files", vim.b[b3].chezmoi_target_ft, nil)
end

-- activate the full plugin (commands, autocmds, encryption, diagnostics)
local ct = require("chezmoi-template")
ct.config.encryption.enabled = true
ct.config.encryption.exclude = { "skipme" }
ct.config.notify_on_open = true
ct.config.redirect = true
ct._activate()
eq("activate is idempotent", ct._activate(), nil)
-- _activate may already have run (FileType gotmpl above) with default config;
-- re-run the config-gated setups so the flags above take effect. Both are
-- idempotent (their augroups clear on setup).
require("chezmoi-template.commands").setup()
require("chezmoi-template.encryption").setup()

-- FocusGained drops stale caches
vim.api.nvim_exec_autocmds("FocusGained", {})

-- :Chezmoi target notifies the deploy target
local tb = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(tb, SRC .. "/dot_zshrc.tmpl")
vim.api.nvim_set_current_buf(tb)
clear_notes()
vim.cmd("Chezmoi target")
eq("Chezmoi target notifies target path", has_note(".zshrc"), true)

-- :Chezmoi apply applies the buffer target and notifies
fake["apply"] = { code = 0, stdout = "" }
clear_notes()
vim.cmd("Chezmoi apply")
vim.wait(1000, function()
  return has_note("applied")
end)
eq("Chezmoi apply notifies applied target", has_note("applied"), true)

-- apply-on-save + diagnostics on BufWritePost (template error -> diagnostic)
vim.bo[tb].filetype = "gotmpl"
fake["execute-template"] = { code = 1, stderr = "chezmoi: template: default:2:5: boom" }
clear_notes()
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = tb })
vim.wait(1000, function()
  return #vim.diagnostic.get(tb) > 0 and has_note("applied")
end)
eq("apply-on-save fires for managed buffers", has_note("applied"), true)
eq("write surfaces template error as diagnostic", vim.diagnostic.get(tb)[1].lnum, 1)
fake["execute-template"] = { code = 0, stdout = "" }
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = tb })
vim.wait(1000, function()
  return #vim.diagnostic.get(tb) == 0
end)
eq("clean render clears diagnostics", #vim.diagnostic.get(tb), 0)

-- notify_on_open fires once per buffer
clear_notes()
vim.api.nvim_exec_autocmds("BufReadPost", { buffer = tb })
eq("notify_on_open announces managed file", has_note("applies on save"), true)
clear_notes()
vim.api.nvim_exec_autocmds("BufReadPost", { buffer = tb })
eq("notify_on_open fires only once", has_note("applies on save"), false)

-- :Chezmoi preview renders into a split, re-renders live as you type, keeps the
-- last valid render on error, toggles closed
do
  resolve.seed(tb, "zsh")
  fake["execute-template"] = { code = 0, stdout = "rendered ok\n" }
  vim.api.nvim_set_current_buf(tb)
  vim.cmd("Chezmoi preview")
  local dest
  vim.wait(1000, function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b):match("^chezmoi%-preview://") then
        dest = b
        return vim.api.nvim_buf_get_lines(b, 0, -1, false)[1] == "rendered ok"
      end
    end
    return false
  end)
  eq("preview renders template output", vim.api.nvim_buf_get_lines(dest, 0, -1, false), { "rendered ok" })
  eq("preview buffer typed as target ft", vim.bo[dest].filetype, "zsh")

  -- editing the source (bumps changedtick) drives a debounced live re-render
  fake["execute-template"] = { code = 0, stdout = "re-rendered\n" }
  vim.api.nvim_buf_set_lines(tb, 0, -1, false, { "{{ .edit }}" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = tb })
  vim.wait(1000, function()
    return vim.api.nvim_buf_get_lines(dest, 0, -1, false)[1] == "re-rendered"
  end)
  eq("preview re-renders live on text change", vim.api.nvim_buf_get_lines(dest, 0, -1, false), { "re-rendered" })

  -- identical render output: the render runs (src changed) but the preview buffer
  -- is left untouched — no rewrite, hence no redraw/treesitter reparse. dest is a
  -- nofile buffer, so only nvim_buf_set_lines would bump its changedtick.
  local dtick = vim.api.nvim_buf_get_changedtick(dest)
  vim.api.nvim_buf_set_lines(tb, 0, -1, false, { "{{ .edit }} -- same output" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = tb })
  vim.wait(500, function()
    return false
  end)
  eq("preview skips rewrite when output unchanged", vim.api.nvim_buf_get_changedtick(dest), dtick)

  -- invalid template: keep the last valid render, don't clobber it with the error
  fake["execute-template"] = { code = 1, stderr = "chezmoi: template: bad" }
  vim.api.nvim_buf_set_lines(tb, 0, -1, false, { "{{ if }}" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = tb })
  vim.wait(500, function()
    return false
  end)
  eq("preview keeps last valid render on error", vim.api.nvim_buf_get_lines(dest, 0, -1, false), { "re-rendered" })

  vim.api.nvim_set_current_buf(tb)
  vim.cmd("Chezmoi preview")
  eq("preview toggles closed", vim.api.nvim_buf_is_valid(dest), false)

  clear_notes()
  local plain = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(plain)
  vim.cmd("Chezmoi preview")
  eq("preview refuses non-template buffers", has_note("not a chezmoi template buffer"), true)
end

-- :Chezmoi diff opens a diff split; `q` closes it; empty diff only notifies
do
  fake["diff"] = { code = 0, stdout = "diff --git a/x b/x\n+new\n" }
  vim.cmd("Chezmoi diff")
  local dbuf = vim.api.nvim_get_current_buf()
  eq("diff split content", vim.api.nvim_buf_get_lines(dbuf, 0, 1, false)[1], "diff --git a/x b/x")
  eq("diff split filetype", vim.bo[dbuf].filetype, "diff")
  vim.api.nvim_feedkeys("q", "x", false)
  eq("q closes the diff split", vim.api.nvim_buf_is_valid(dbuf), false)

  clear_notes()
  fake["diff"] = { code = 0, stdout = "  \n" }
  vim.cmd("Chezmoi diff")
  eq("empty diff notifies instead of splitting", has_note("no differences"), true)
end

-- redirect: opening a deployed managed file jumps to its source
do
  -- deployed path outside the source dir; under cwd so no symlink resolution
  -- (nvim_buf_set_name resolves /tmp -> /private/tmp on macOS)
  local deployed = vim.fs.normalize(vim.fn.getcwd()) .. "/chezmoi-test-deployed"
  fake["managed"] = { code = 0, stdout = deployed .. "\n" }
  resolve.invalidate()
  fake["source-path"] = { code = 0, stdout = SRC .. "/dot_chezmoi-test-deployed\n" }
  local rb = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(rb, deployed)
  vim.api.nvim_set_current_buf(rb)
  clear_notes()
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = rb })
  vim.wait(1000, function()
    return has_note("redirected to source")
  end)
  eq("redirect jumps to the chezmoi source", has_note("redirected to source"), true)
  eq("redirect edits the source path", vim.api.nvim_buf_get_name(0):find("dot_chezmoi%-test%-deployed$") ~= nil, true)
end

-- :Chezmoi source from a deployed file / from inside the source dir
do
  clear_notes()
  vim.api.nvim_set_current_buf(tb)
  vim.cmd("Chezmoi source")
  eq("Chezmoi source inside source dir just notifies", has_note("already in the chezmoi source directory"), true)
end

-- :Chezmoi pick with the vim.ui.select fallback backend
do
  ct.config.picker = "select"
  fake["managed"] = { code = 0, stdout = "dot_pick_me.tmpl\n" }
  local real_select = vim.ui.select
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, _, cb)
    cb(items[1])
  end
  vim.cmd("Chezmoi pick")
  eq("select backend edits the picked source file", bufname(), SRC .. "/dot_pick_me.tmpl")
  vim.ui.select = real_select

  clear_notes()
  ct.config.picker = "nope"
  vim.cmd("Chezmoi pick")
  eq("unknown picker backend errors", has_note("unknown picker"), true)
  ct.config.picker = nil
end

-- encryption: decrypt on read, re-encrypt on write, exclude patterns
do
  local age = SRC .. "/enc_roundtrip.age"
  local f = assert(io.open(age, "wb"))
  f:write("BINARYGARBAGE")
  f:close()
  fake["decrypt"] = { code = 0, stdout = "s3cret line\n" }
  vim.cmd.edit(vim.fn.fnameescape(age))
  local eb = vim.api.nvim_get_current_buf()
  eq("encrypted file decrypts into the buffer", vim.api.nvim_buf_get_lines(eb, 0, -1, false), { "s3cret line" })
  eq("decrypted buffer has no swapfile", vim.bo[eb].swapfile, false)
  eq("decrypted buffer not marked modified", vim.bo[eb].modified, false)

  fake["encrypt"] = { code = 0, stdout = "ENCRYPTED-BLOB" }
  vim.api.nvim_buf_set_lines(eb, 0, -1, false, { "changed" })
  vim.cmd.write()
  local rf = assert(io.open(age, "rb"))
  local on_disk = rf:read("*a")
  rf:close()
  eq("write goes through chezmoi encrypt", on_disk, "ENCRYPTED-BLOB")
  eq("buffer unmodified after encrypted write", vim.bo[eb].modified, false)
  vim.api.nvim_buf_delete(eb, { force = true })
  os.remove(age)

  local skip = SRC .. "/skipme.age"
  local sf = assert(io.open(skip, "wb"))
  sf:write("PLAIN")
  sf:close()
  vim.cmd.edit(vim.fn.fnameescape(skip))
  local sb = vim.api.nvim_get_current_buf()
  eq("excluded *.age opens raw", vim.api.nvim_buf_get_lines(sb, 0, -1, false), { "PLAIN" })
  vim.api.nvim_buf_delete(sb, { force = true })
  os.remove(skip)
end

-- inject autocmds: BufReadPre seeds real *.tmpl reads; .chezmoitemplates/
-- partials get forced to gotmpl on BufReadPost
do
  fake["managed"] = { code = 0, stdout = "" } -- empty source set -> name fallback
  resolve.invalidate()
  -- .json target: filetype detectable from the name alone (deterministic)
  local tmpl = SRC .. "/dot_seed_check.json.tmpl"
  local f = assert(io.open(tmpl, "w"))
  f:write('{ "os": "{{ .chezmoi.os }}" }\n')
  f:close()
  vim.cmd.edit(vim.fn.fnameescape(tmpl))
  local b = vim.api.nvim_get_current_buf()
  eq("BufReadPre seeds target ft for *.tmpl", vim.b[b].chezmoi_target_ft, "json")
  eq("*.tmpl gets gotmpl filetype", vim.bo[b].filetype, "gotmpl")
  vim.api.nvim_buf_delete(b, { force = true })
  os.remove(tmpl)

  vim.fn.mkdir(SRC .. "/.chezmoitemplates", "p")
  -- .json: detectable from the filename alone (.sh needs buffer contents)
  local partial = SRC .. "/.chezmoitemplates/greeting.json"
  local pf = assert(io.open(partial, "w"))
  pf:write("{}\n")
  pf:close()
  vim.cmd.edit(vim.fn.fnameescape(partial))
  local pb = vim.api.nvim_get_current_buf()
  eq("partials seed ft from basename", vim.b[pb].chezmoi_target_ft, "json")
  eq("partials forced to gotmpl", vim.bo[pb].filetype, "gotmpl")
  vim.api.nvim_buf_delete(pb, { force = true })
  os.remove(partial)
  vim.fn.delete(SRC .. "/.chezmoitemplates", "d")
end

-- picker: each plugin backend receives the source dir
do
  local picked = {}
  package.preload["snacks"] = function()
    return {
      picker = {
        files = function(o)
          picked.snacks = o.cwd
        end,
      },
    }
  end
  package.preload["telescope.builtin"] = function()
    return {
      find_files = function(o)
        picked.telescope = o.cwd
      end,
    }
  end
  package.preload["fzf-lua"] = function()
    return {
      files = function(o)
        picked["fzf-lua"] = o.cwd
      end,
    }
  end
  for _, name in ipairs({ "snacks", "telescope", "fzf-lua" }) do
    ct.config.picker = name
    vim.cmd("Chezmoi pick")
    eq("picker backend " .. name .. " gets source dir", picked[name], SRC .. "/")
  end
  ct.config.picker = nil
end

-- inject directive: only runs where the gotmpl parser exists (skipped in CI)
do
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "export A=1", '{{ if eq .chezmoi.os "darwin" }}', "brew", "{{ end }}" })
  vim.b[b].chezmoi_target_lang = "lua" -- any bundled parser
  local ok_parser, parser = pcall(vim.treesitter.get_parser, b, "gotmpl")
  if ok_parser and parser then
    parser:parse(true)
    local langs = vim.tbl_keys(parser:children())
    eq("directive injects the seeded language", vim.tbl_contains(langs, "lua"), true)
  end
end

-- health: reports routed through a recorder
do
  local reports = {}
  local real_health = vim.health
  vim.health = setmetatable({}, {
    __index = function(_, k)
      return function(msg)
        reports[#reports + 1] = k .. ": " .. tostring(msg)
      end
    end,
  })
  require("chezmoi-template.health").check()
  vim.health = real_health
  eq("health reports run", #reports >= 4, true)
  eq("health mentions chezmoi binary", reports[2]:find("chezmoi executable", 1, true) ~= nil, true)
end

-- apply.force appends --force to the apply command
do
  local fb = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(fb, SRC .. "/dot_force.tmpl")
  vim.api.nvim_set_current_buf(fb)
  fake["apply"] = { code = 0, stdout = "" }
  fake["target-path"] = { code = 0, stdout = SRC .. "/.force\n" }
  ct.config.apply.force = true
  clear_notes()
  vim.cmd("Chezmoi apply")
  vim.wait(1000, function()
    return has_note("applied")
  end)
  eq("apply.force passes --force", vim.tbl_contains(sent["apply"], "--force"), true)
  ct.config.apply.force = false
  vim.api.nvim_buf_delete(fb, { force = true })
end

-- list() pairs each target (from `managed --path-style absolute`) with its
-- source (from a single `source-path <t1> <t2> …` spawn, emitted in arg order).
do
  fake["managed"] = { code = 0, stdout = "/home/u/.zshrc\n/home/u/.gitconfig\n" }
  fake["source-path"] = { code = 0, stdout = SRC .. "/dot_zshrc.tmpl\n" .. SRC .. "/dot_gitconfig\n" }
  resolve.invalidate()
  local files = ct.list()
  eq("list returns one entry per managed file", #files, 2)
  eq("list pairs source with its target", files[1].source, SRC .. "/dot_zshrc.tmpl")
  eq("list carries target", files[1].target, "/home/u/.zshrc")
  eq("list keeps arg order for the second entry", files[2].source, SRC .. "/dot_gitconfig")
end

-- edit(target) opens the resolved source file
do
  fake["source-path"] = { code = 0, stdout = SRC .. "/dot_gitconfig.tmpl\n" }
  ct.edit("~/.gitconfig")
  eq("edit opens the resolved source", bufname(), SRC .. "/dot_gitconfig.tmpl")
end

-- inject.exclude leaves matching source paths as plain gotmpl (no target lang).
-- The match runs on the normalized (forward-slash) path, so a "/"-separator
-- pattern is portable — on Windows seed_buffer normalizes the backslash path
-- before matching (that OS-specific leg is verified by the Windows CI run).
do
  fake["managed"] = { code = 0, stdout = "" } -- empty set -> name-based ft fallback
  resolve.invalidate()
  ct.config.inject.exclude = { "dot_config/excluded" } -- pattern spans a "/"
  local xb = vim.api.nvim_create_buf(false, true)
  require("chezmoi-template.inject").seed_buffer(xb, SRC .. "/private_dot_config/excluded.json.tmpl")
  eq("inject.exclude '/'-pattern skips injection", vim.b[xb].chezmoi_target_lang, nil)
  eq("inject.exclude '/'-pattern skips ft", vim.b[xb].chezmoi_target_ft, nil)
  ct.config.inject.exclude = { "excluded%.json%.tmpl" } -- basename pattern still works
  local yb = vim.api.nvim_create_buf(false, true)
  require("chezmoi-template.inject").seed_buffer(yb, SRC .. "/dot_included.json.tmpl")
  eq("non-excluded still seeds target ft", vim.b[yb].chezmoi_target_ft, "json")
  ct.config.inject.exclude = {}
end

-- flush coverage stats before exit (`nvim -l` may skip luacov's exit hook)
if os.getenv("COVERAGE") then
  require("luacov.runner").shutdown()
end

if failures > 0 then
  error(failures .. " test case(s) failed")
end
print("all tests passed")
