# lua-maptable

A Lua mapping-table implementation: a table that runs every key through a
transformation function on both storage and retrieval. Its primary use is
case-insensitive tables, but the mapper is arbitrary, so it works for any kind
of normalized-key lookup.

## How it works

You give `maptable.new` a *mapper* function. Whenever a key is stored or looked
up, it's first passed through the mapper, and the resulting *mapped key* is what
the table actually keys on. Any two raw keys that map to the same value are
therefore the same key.

```lua
local maptable = require 'maptable'

-- Case-insensitive table: keys are compared after lowercasing.
local headers = maptable.new(string.lower)

headers['Content-Type'] = 'text/plain'

print(headers['content-type'])  --> text/plain
print(headers['CONTENT-TYPE'])  --> text/plain
print(headers['Content-Type'])  --> text/plain
```

Values are stored keyed by their *mapped* form, so lookups stay consistent even
when several distinct raw keys collapse onto one mapped key. The most recent
write wins:

```lua
local t = maptable.new(string.lower)
t.Foo = 1
t.foo = 2
print(t.FOO)  --> 2   (a single logical entry)
```

Assigning `nil` deletes the entry, as with a normal table.

## Installation

With [Lux](https://github.com/lumen-oss/lux):

```
lx add maptable
```

Or drop `src/maptable.lua` into your project and `require` it.

## API

### `maptable.new(mapper, options?)`

Create a new maptable.

- `mapper` — `fun(key): mapped` — called on every key before storage/lookup.
  Must be deterministic (the same key always maps to the same value). If it
  returns `nil` for a key you try to store, Lua will raise a "table index is
  nil" error, same as any table.

Returns the maptable, which you index like an ordinary table.

```lua
local t = maptable.new(string.lower)
t.Hello = 'world'
print(t.hello)  --> world
```

### `maptable.fill(maptable, iter, ...)`

Populate a maptable from an iterator. Slightly more efficient than assigning
keys one at a time, and accepts anything you'd pass to a generic `for`.

```lua
local t = maptable.new(string.lower)
maptable.fill(t, pairs{ One = 1, Two = 2, Three = 3 })
print(t.TWO)  --> 2
```

This is useful for turning tables you get from elsewhere into mapped ones:

```lua
local response = http_client:get('https://example.com/')
local headers = maptable.new(function(key)
  return (string.lower(key):gsub('-', '_'))
end)
maptable.fill(headers, response.headers)
print(headers.content_type)
```

### `maptable.pairs(maptable)`

Iterate the maptable. Returns an iterator triple suitable for a generic `for`.

```lua
for key, value in maptable.pairs(t) do
  print(key, value)
end
```

On Lua 5.2+ you can also just use the built-in `pairs(t)` — the `__pairs`
metamethod is wired up to the same behavior. `maptable.pairs` exists mainly for
Lua 5.1, where `__pairs` isn't consulted by the standard library.

### `maptable.pairs_mapped(maptable)`

Iterate the maptable using the mapped keys as pairs instead of the original. Returns an iterator suitable for a generic `for`.

```lua
for key, value in maptable.pairs_mapped(t) do
  print(key, value)
end
```

## Iteration modes

```lua
local t = maptable.new(string.lower)
t.Alpha = 1
t.Beta  = 2

-- Default: original keys
for k, v in maptable.pairs(t) do print(k, v) end
--> Alpha 1
--> Beta  2

-- Mapped keys, same table
for k, v in maptable.pairs_mapped(t) do print(k, v) end
--> alpha 1
--> beta  2
```

Both iteration functions work on the same instance — the iteration style is
chosen at the call site, not baked into the table.

### Length

`#t` respects `__len` and returns the length of the underlying storage's
sequence part, exactly as it would for a plain table. It counts a contiguous
run of integer mapped-keys starting at 1, not the total number of entries:

```lua
local t = maptable.new(function(k) return k end)
t[1], t[2], t[3] = 'a', 'b', 'c'
print(#t)  --> 3

local h = maptable.new(string.lower)
h.Foo = 1
print(#h)  --> 0   (no integer sequence, same as any string-keyed table)

local f = maptable.new(math.floor)
f[1.5] = 1
print(#f)  --> 1   (this is the sequence of the mapped table, so this still counts)

local n = maptable.new(tonumber)
n[1] = 'a'
n['2'] = 'b'
n['3'] = 'c'
print(#n)  --> 3
```

## Notes

- The mapper is arbitrary — it doesn't have to be `string.lower`. Any
  deterministic transform works, including over non-string keys:

  ```lua
  local buckets = maptable.new(math.floor)
  buckets[1.9] = 'a'
  print(buckets[1.1])  --> a   (both floor to 1)
  ```

- Because the backing data lives off to the side, `rawget`, `rawset`, and
  `next` on the maptable directly won't behave like a normal table. Use the
  provided API for iteration. (`#t` works normally, via `__len`.)

## Compatibility

Lua 5.1+

## License

[MPL-2.0](LICENSE)
