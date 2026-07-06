-- Self-contained test runner for maptable. No external deps (busted is broken
-- on Lux's statically-linked, symbol-stripped Lua). Run with: lua test.lua

package.path = "src/?.lua;" .. package.path
local maptable = require("maptable")

--- ANSI colors, unless NO_COLOR is set or output isn't wanted.
local use_color = os.getenv("NO_COLOR") == nil
local function paint(code, s)
  if not use_color then return s end
  return "\27[" .. code .. "m" .. s .. "\27[0m"
end
local green = function(s) return paint("32", s) end
local red = function(s) return paint("31", s) end
local dim = function(s) return paint("2", s) end

------------------------------------------------------------------------------
-- Assertion helpers. Each raises on failure with a descriptive message.
------------------------------------------------------------------------------

local function fail(msg)
  error(msg, 2)
end

--- Serialize a value for error messages.
local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local function assert_eq(actual, expected, ctx)
  if actual ~= expected then
    fail(string.format("%sexpected %s, got %s",
      ctx and (ctx .. ": ") or "", show(expected), show(actual)))
  end
end

local function assert_nil(actual, ctx)
  if actual ~= nil then
    fail(string.format("%sexpected nil, got %s",
      ctx and (ctx .. ": ") or "", show(actual)))
  end
end

--- Drain an iterator triple (as returned by pairs/maptable.pairs) into a plain
--- table plus a count, so results can be compared regardless of order.
local function collect(iter, state, ctrl)
  local out, n = {}, 0
  for k, v in iter, state, ctrl do
    out[k] = v
    n = n + 1
  end
  return out, n
end

------------------------------------------------------------------------------
-- Test registration.
------------------------------------------------------------------------------

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local lower = string.lower

------------------------------------------------------------------------------
-- Tests.
------------------------------------------------------------------------------

test("basic set and get", function()
  local t = maptable.new(lower)
  t.Hello = "world"
  assert_eq(t.Hello, "world")
end)

test("case-insensitive lookup via lowercasing mapper", function()
  local t = maptable.new(lower)
  t["Content-Type"] = "text/plain"
  assert_eq(t["content-type"], "text/plain")
  assert_eq(t["CONTENT-TYPE"], "text/plain")
  assert_eq(t["Content-Type"], "text/plain")
end)

test("missing key returns nil", function()
  local t = maptable.new(lower)
  assert_nil(t.nope)
end)

test("non-injective overwrite keeps a single logical entry", function()
  local t = maptable.new(lower)
  t.Foo = 1
  t.foo = 2
  assert_eq(t.Foo, 2, "read via original case")
  assert_eq(t.FOO, 2, "read via upper case")
  -- Default pairs yields original keys; must be exactly one entry.
  local out, n = collect(maptable.pairs(t))
  assert_eq(n, 1, "entry count after collision")
  assert_eq(out.foo, 2, "surviving key is the last-written original")
end)

test("delete via nil removes the value", function()
  local t = maptable.new(lower)
  t.Foo = 1
  t.FOO = nil
  assert_nil(t.foo, "value gone")
  local _, n = collect(maptable.pairs(t))
  assert_eq(n, 0, "no ghost entries left in iteration")
end)

test("delete only affects the mapped key", function()
  local t = maptable.new(lower)
  t.Foo = 1
  t.Bar = 2
  t.foo = nil
  assert_nil(t.Foo)
  assert_eq(t.Bar, 2)
  local out, n = collect(maptable.pairs(t))
  assert_eq(n, 1)
  assert_eq(out.Bar, 2)
end)

test("default pairs yields original (last-written) keys", function()
  local t = maptable.new(lower)
  t.Alpha = 1
  t.Beta = 2
  local out, n = collect(maptable.pairs(t))
  assert_eq(n, 2)
  assert_eq(out.Alpha, 1)
  assert_eq(out.Beta, 2)
end)

test("pairs_mapped yields mapped keys", function()
  local t = maptable.new(lower)
  t.Alpha = 1
  t.Beta = 2
  local out, n = collect(maptable.pairs_mapped(t))
  assert_eq(n, 2)
  assert_eq(out.alpha, 1, "mapped key present")
  assert_eq(out.beta, 2)
  assert_nil(out.Alpha, "original key absent in mapped mode")
end)

test("pairs and pairs_mapped both work on the same table", function()
  local t = maptable.new(lower)
  t.Alpha = 1
  local orig = collect(maptable.pairs(t))
  local mapped = collect(maptable.pairs_mapped(t))
  assert_eq(orig.Alpha, 1, "original-key iteration")
  assert_eq(mapped.alpha, 1, "mapped-key iteration")
end)

test("__pairs metamethod drives builtin pairs()", function()
  local t = maptable.new(lower)
  t.Alpha = 1
  t.Beta = 2
  local out, n = collect(pairs(t))
  assert_eq(n, 2)
  assert_eq(out.Alpha, 1)
  assert_eq(out.Beta, 2)
end)

test("arbitrary transform mapper (numeric floor)", function()
  local t = maptable.new(math.floor)
  t[1.9] = "a"
  assert_eq(t[1.1], "a", "1.1 and 1.9 both floor to 1")
  assert_eq(t[1], "a")
end)

test("__len operator returns sequence length", function()
  local t = maptable.new(math.floor)
  t[1.9] = "a"
  t[2.5] = "b"
  assert_eq(#t, 2, "After 2 inserts, #t should be 2")
  t[4.5] = "c"
  t[3.5] = "d"
  assert_eq(#t, 4, "After 4 inserts, #t should be 4")
  assert_eq(t[1], "a")
  assert_eq(t[2.1], "b")
  assert_eq(t[3.7], "d")
  assert_eq(t[4.9], "c")

  local ridiculous
  --- @type maptable.Maptable<string, integer, string>
  ridiculous = maptable.new(function() return #ridiculous + 1 end)
  assert_eq(#ridiculous, 0, 'Getting the length works')
  ridiculous.foo = 'bar'
  assert_eq(#ridiculous, 1, 'Getting the length works')
  ridiculous.foo = 'bar'
  assert_eq(#ridiculous, 2, 'Getting the length works')
  ridiculous.foo = 'bar'
  assert_eq(#ridiculous, 3, 'Getting the length works')

  --- @type maptable.Maptable<any, number, string>
  local tonum = maptable.new(tonumber)
  assert_eq(#tonum, 0, 'Getting the length works')
  tonum[1] = 'bar'
  assert_eq(#tonum, 1, 'Getting the length works')
  tonum['2'] = 'bar'
  assert_eq(#tonum, 2, 'Getting the length works')
  tonum['3'] = 'bar'
  assert_eq(#tonum, 3, 'Getting the length works')
end)

test("fill populates from an iterator", function()
  local t = maptable.new(lower)
  maptable.fill(t, pairs{ One = 1, Two = 2, Three = 3 })
  assert_eq(t.one, 1)
  assert_eq(t.TWO, 2)
  assert_eq(t.three, 3)
  local _, n = collect(maptable.pairs(t))
  assert_eq(n, 3)
end)

test("fill and __newindex agree", function()
  local t = maptable.new(lower)
  maptable.fill(t, pairs{ Foo = 1 })
  t.Bar = 2
  local out, n = collect(maptable.pairs(t))
  assert_eq(n, 2)
  assert_eq(out.Foo, 1)
  assert_eq(out.Bar, 2)
end)

test("instances are independent", function()
  local a = maptable.new(lower)
  local b = maptable.new(lower)
  a.Key = "a"
  b.Key = "b"
  assert_eq(a.key, "a")
  assert_eq(b.key, "b")
end)

test("empty table iterates zero times", function()
  local t = maptable.new(lower)
  local _, n = collect(maptable.pairs(t))
  assert_eq(n, 0)
end)

------------------------------------------------------------------------------
-- Run.
------------------------------------------------------------------------------

local passed, failed = 0, 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    passed = passed + 1
    print(green("  PASS ") .. t.name)
  else
    failed = failed + 1
    print(red("  FAIL ") .. t.name)
    print(dim("       " .. tostring(err)))
  end
end

print()
local summary = string.format("%d passed, %d failed", passed, failed)
if failed == 0 then
  print(green(summary))
  os.exit(0)
else
  print(red(summary))
  os.exit(1)
end
