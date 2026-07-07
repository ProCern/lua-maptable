-- Key to access private data. Easily probed via manual `next`, but that's on the user if they mess that up.
local private_key = {}

--- @alias maptable.PairsMode 'mapped'|'original'

--- @class maptable.Private<K, M, V>
--- @field mapper (fun(key: K): M) The function for mapping from the raw key to the mapped key
--- @field mapped_table {[M]: V} The table that actually stores the values
--- @field key_table {[M]: K} the table that stores the insertion key for each mapped key.
--- @field pairs_mode maptable.PairsMode

--- Validate and return a pairs mode, erroring on anything unexpected.
--- @param mode maptable.PairsMode
--- @return maptable.PairsMode
local function validate_pairs_mode(mode)
  assert(mode == 'mapped' or mode == 'original',
    "pairs mode must be 'mapped' or 'original'")
  return mode
end

--- A generic table allowing applying a mapping function to storage and
--- retrieval. This primarily allows things like case-insensitive tables, but
--- can also be used for any arbitrary key transformation.
--- @class maptable.Maptable<K, M, V>: { [K]: V }
--- @operator len: integer
local metatable = {}

--- @param key K
--- @param value V
function metatable:__newindex(key, value)
  --- @type maptable.Private
  local private_self = self[private_key]
  local mapped = private_self.mapper(key)
  private_self.mapped_table[mapped] = value
  if value == nil then
    private_self.key_table[mapped] = nil
  else
    private_self.key_table[mapped] = key
  end
end

--- @param key K
--- @returns V
function metatable:__index(key)
  --- @type maptable.Private
  local private_self = self[private_key]
  return private_self.mapped_table[private_self.mapper(key)]
end

--- @returns integer
function metatable:__len()
  local private_self = self[private_key]
  return #private_self.mapped_table
end

--- @generic K
--- @generic M
--- @generic V
--- @param state maptable.Private<K, M, V>
local function key_iter(state, key)
  if key ~= nil then
    key = state.mapper(key)
  end
  local next_mapped_key, next_value = next(state.mapped_table, key)
  if next_mapped_key == nil then
    return nil
  end
  return state.key_table[next_mapped_key], next_value
end

--- Iterate the table yielding the original (last-written) keys. Equivalent to
--- iterating with the built-in `pairs`, and usable on Lua 5.1 where the
--- `__pairs` metamethod is not consulted.
--- @generic K
--- @generic M
--- @generic V
--- @param maptable maptable.Maptable<K, M, V>
local function maptable_pairs(maptable)
  return key_iter, maptable[private_key], nil
end

--- Iterate the table yielding the mapped keys instead of the original keys.
--- @generic K
--- @generic M
--- @generic V
--- @param maptable maptable.Maptable<K, M, V>
local function maptable_pairs_mapped(maptable)
  --- @type maptable.Private
  local private = maptable[private_key]
  return pairs(private.mapped_table)
end

--- @returns (fun(state: any, cv: K|M): K|M, V), any, nil, any
function metatable:__pairs()
  --- @type maptable.Private
  local private_self = self[private_key]
  if private_self.pairs_mode == 'mapped' then
    return maptable_pairs_mapped(self)
  else
    return maptable_pairs(self)
  end
end

--- @class maptable.NewOptions
--- @field pairs? maptable.PairsMode Which key style default iteration yields. Defaults to 'original'.

--- @generic K
--- @generic M
--- @generic V
--- @param mapper fun(key: K): any
--- @param options? maptable.NewOptions
--- @return maptable.Maptable<K, M, V>
local function new(mapper, options)
  local self = setmetatable({
    [private_key] = {
      mapper = assert(mapper, 'Need mapper argument'),
      key_table = {},
      mapped_table = {},
      pairs_mode = validate_pairs_mode(options and options.pairs or 'original'),
    },
  }, metatable)
  return self
end

--- Change which key style the maptable's default iteration (built-in `pairs`
--- and the `__pairs` metamethod) yields, on an already-created maptable. The
--- standalone `maptable.pairs` and `maptable.pairs_mapped` functions are
--- unaffected and always yield their respective key style.
--- @generic K
--- @generic M
--- @generic V
--- @param maptable maptable.Maptable<K, M, V>
--- @param mode maptable.PairsMode
local function set_pairs(maptable, mode)
  --- @type maptable.Private
  local private_self = maptable[private_key]
  private_self.pairs_mode = validate_pairs_mode(mode)
end

--- Fill the given maptable from the iterator. This is a little more efficient
--- than doing it externally.
--- @generic K
--- @generic M
--- @generic V
--- @param maptable maptable.Maptable<K, M, V>
--- @param iter (fun(): K, V) The iteration function
--- @param ... any The rest of the iteration initial values
local function fill(maptable, iter, ...)
  --- @type maptable.Private
  local private_maptable = maptable[private_key]
  local mapper = private_maptable.mapper
  local key_table = private_maptable.key_table
  local mapped_table = private_maptable.mapped_table
  for key, value in iter, ... do
    local mapped = mapper(key)
    mapped_table[mapped] = value
    if value == nil then
      key_table[mapped] = nil
    else
      key_table[mapped] = key
    end
  end
end

return {
  new = new,
  fill = fill,
  pairs = maptable_pairs,
  pairs_mapped = maptable_pairs_mapped,
  set_pairs = set_pairs,
}
