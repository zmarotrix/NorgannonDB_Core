-- Questie's binary serializer, the "1short" stream: bytes 0, 237 and 238 are escaped, and every
-- value starts with a tag byte. comms.lua sends and reads its packets through this; the harness
-- round-trips them through Questie's real serializer. Nothing here knows about quests.

local Core = NorgannonCore

local floor, byte, char, concat = math.floor, string.byte, string.char, table.concat
local pairs, type = pairs, type

local Serializer = {}
Core.QuestieSerializer = Serializer

local CONTROL, ZERO = 237, 238
local TWO_16, TWO_24, TWO_32 = 65536, 16777216, 4294967296

-- Every value starts with a tag byte. These and the size thresholds in the writers below are
-- Questie's wire format (Modules/Libs/QuestieSerializer.lua): don't tidy them. Where a number has
-- a negative form, its tag is the positive one plus 1.
local TAG = {
  NIL = 1, INT = 2, NEG_INT = 3, LONG = 4, NEG_LONG = 5, FLOAT = 6,
  STRING8 = 7, STRING16 = 8, HASHED_STRING = 9,
  TABLE8 = 10, TABLE16 = 11,
  BYTE = 12, NEG_BYTE = 13, SHORT = 14, NEG_SHORT = 15,
  FALSE = 16, TRUE = 17,
  ARRAY8 = 20, ARRAY16 = 21, ARRAY32 = 22,
  TINY_INT = 32,     -- 32 + n: the integer n, in the tag itself
}

local out   -- the bytes being written, one string per byte

local function wbyte(b)
  if b == 0 then
    out[#out + 1] = char(ZERO)
  elseif b == CONTROL then
    out[#out + 1] = char(CONTROL, 1)
  elseif b == ZERO then
    out[#out + 1] = char(CONTROL, 2)
  else
    out[#out + 1] = char(b)
  end
end

local function wshort(v)
  wbyte(floor(v / 256) % 256)
  wbyte(v % 256)
end

local function wint(v)
  v = v % TWO_32
  wbyte(floor(v / TWO_24) % 256)
  wbyte(floor(v / TWO_16) % 256)
  wbyte(floor(v / 256) % 256)
  wbyte(v % 256)
end

local function wlong(v)
  wint(floor(v / TWO_32))
  wint(v % TWO_32)
end

-- the IEEE 754 single-precision bits of a number, as an integer
local function floatbits(n)
  local sign = 0
  if n < 0 then sign, n = 0x80, -n end
  local mant, expo = math.frexp(n)
  if mant ~= mant then return 0xFF880000 end
  if mant == math.huge or expo > 0x80 then return sign == 0 and 0x7F800000 or 0xFF800000 end
  if (mant == 0 and expo == 0) or expo < -0x7E then return sign * TWO_24 end
  expo = expo + 0x7E
  mant = floor((mant * 2 - 1) * math.ldexp(0.5, 24))
  return (sign + floor(expo / 2)) * TWO_24 + ((expo % 2) * 0x80 + floor(mant / 0x10000)) * TWO_16
    + (floor(mant / 0x100) % 0x100) * 256 + mant % 0x100
end

local function writeNumber(v)
  if v % 1 ~= 0 then
    wbyte(TAG.FLOAT)
    wint(floatbits(v))
    return
  end
  local sign = 0
  if v < 0 then v, sign = -v, 1 end
  if v > 2147483646 then
    wbyte(TAG.LONG + sign)
    wlong(v)
  elseif v < 222 and sign == 0 then
    wbyte(TAG.TINY_INT + v)
  elseif v < 255 then
    wbyte(TAG.BYTE + sign)
    wbyte(v)
  elseif v < 65530 then
    wbyte(TAG.SHORT + sign)
    wshort(v)
  else
    wbyte(TAG.INT + sign)
    wint(v)
  end
end

local function writeString(v)
  local len = #v
  if len > 254 then
    wbyte(TAG.STRING16)
    wshort(len)
  else
    wbyte(TAG.STRING8)
    wbyte(len)
  end
  for i = 1, len do wbyte(byte(v, i)) end
end

local function isarray(t, count)
  for i = 1, count do
    if t[i] == nil then return false end
  end
  return true
end

local write

local function writeTable(v)
  local count = 0
  for _, inner in pairs(v) do
    if inner ~= nil then count = count + 1 end
  end
  if isarray(v, count) then
    if count > 65530 then
      wbyte(TAG.ARRAY32)
      wint(count)
    elseif count > 254 then
      wbyte(TAG.ARRAY16)
      wshort(count)
    else
      wbyte(TAG.ARRAY8)
      wbyte(count)
    end
    for i = 1, count do write(v[i]) end
  else
    if count > 254 then
      wbyte(TAG.TABLE16)
      wshort(count)
    else
      wbyte(TAG.TABLE8)
      wbyte(count)
    end
    for key, inner in pairs(v) do
      write(key)
      write(inner)
    end
  end
end

write = function(v)
  local t = type(v)
  if t == "number" then
    writeNumber(v)
  elseif t == "string" then
    writeString(v)
  elseif t == "boolean" then
    wbyte(v and TAG.TRUE or TAG.FALSE)
  elseif t == "table" then
    writeTable(v)
  else
    wbyte(TAG.NIL)
  end
end

function Serializer.Serialize(tab)
  out = {}
  write(1)   -- Questie wraps every payload as { [1] = payload }
  write(tab)
  local result = concat(out)
  out = nil
  return result
end

local data, pos, hashes   -- the message being read, where we are in it, the strings seen so far

local function rbyte()
  local v = byte(data, pos)
  pos = pos + 1
  if not v then error("truncated message", 0) end
  if v == ZERO then return 0 end
  if v == CONTROL then
    local c = byte(data, pos)
    pos = pos + 1
    return c == 1 and CONTROL or ZERO
  end
  return v
end
local function rshort() return rbyte() * 256 + rbyte() end
local function rint() return rbyte() * TWO_24 + rbyte() * TWO_16 + rbyte() * 256 + rbyte() end
local function rlong() return rint() * TWO_32 + rint() end

local function rstring(len)
  local chars = {}
  for i = 1, len do chars[i] = char(rbyte()) end
  return concat(chars)
end

-- the reverse of floatbits
local function bitsfloat(int)
  local b1, b2 = floor(int / TWO_24) % 256, floor(int / TWO_16) % 256
  local b3, b4 = floor(int / 256) % 256, int % 256
  local sign = b1 > 0x7F and -1 or 1
  local expo = (b1 % 0x80) * 2 + floor(b2 / 0x80)
  local mant = ((b2 % 0x80) * 0x100 + b3) * 0x100 + b4
  if mant == 0 and expo == 0 then return 0 end
  if expo == 0xFF then return mant == 0 and sign * math.huge or 0 / 0 end
  return sign * math.ldexp(1 + mant / 0x800000, expo - 0x7F)
end

-- Questie references repeated strings (over 4 characters) by a djb2 hash of an earlier one
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (31 * h + byte(s, i)) % TWO_32 end
  return h
end

local function remember(s)
  if type(s) == "string" then
    local h = hash(s)
    if hashes[h] == nil then hashes[h] = s end
  end
end

local read
local function rtable(count)
  local t = {}
  for _ = 1, count do
    local key = read()
    remember(key)
    local value = read()
    remember(value)
    if key ~= nil then t[key] = value end
  end
  return t
end

local function rarray(count)
  local t = {}
  for i = 1, count do
    local value = read()
    remember(value)
    t[i] = value
  end
  return t
end

local readers = {
  [TAG.NIL] = function() return nil end,
  [TAG.INT] = function() return rint() end,
  [TAG.NEG_INT] = function() return -rint() end,
  [TAG.LONG] = function() return rlong() end,
  [TAG.NEG_LONG] = function() return -rlong() end,
  [TAG.FLOAT] = function() return bitsfloat(rint()) end,
  [TAG.STRING8] = function() return rstring(rbyte()) end,
  [TAG.STRING16] = function() return rstring(rshort()) end,
  [TAG.HASHED_STRING] = function() return hashes[rint()] end,
  [TAG.TABLE8] = function() return rtable(rbyte()) end,
  [TAG.TABLE16] = function() return rtable(rshort()) end,
  [TAG.BYTE] = function() return rbyte() end,
  [TAG.NEG_BYTE] = function() return -rbyte() end,
  [TAG.SHORT] = function() return rshort() end,
  [TAG.NEG_SHORT] = function() return -rshort() end,
  [TAG.FALSE] = function() return false end,
  [TAG.TRUE] = function() return true end,
  [18] = function() return nil end,   -- Questie reads these two as nil as well
  [19] = function() return nil end,
  [TAG.ARRAY8] = function() return rarray(rbyte()) end,
  [TAG.ARRAY16] = function() return rarray(rshort()) end,
  [TAG.ARRAY32] = function() return rarray(rint()) end,
}

read = function()
  local typ = rbyte()
  if typ >= TAG.TINY_INT then return typ - TAG.TINY_INT end
  local reader = readers[typ]
  if not reader then error("unknown type " .. typ, 0) end
  return reader()
end

function Serializer.Deserialize(message)
  data, pos, hashes = message, 1, {}
  -- the payload is the value of a one-pair table (see Serialize); a bad message just reads as nil
  local ok, result = pcall(rtable, 1)
  data, hashes = nil, nil
  return ok and result[1] or nil
end
