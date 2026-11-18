-- A small JSON reader and writer for Forge's state files (theme.json,
-- tiling.json). Hyprland's Lua has no JSON library. Objects, arrays,
-- strings, numbers, booleans and null; enough for files Forge writes.
local json = {}

local function skip(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local escapes = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local parse

local function parse_string(s, i)
    local out, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then error("unterminated string") end
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            if e == "u" then
                local code = tonumber(s:sub(j + 2, j + 5), 16) or 63
                out[#out + 1] = utf8.char(code)
                j = j + 6
            else
                out[#out + 1] = escapes[e] or e
                j = j + 2
            end
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
end

function parse(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local obj = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            local key
            key, i = parse_string(s, skip(s, i))
            i = skip(s, i)
            if s:sub(i, i) ~= ":" then error("expected ':' at " .. i) end
            obj[key], i = parse(s, i + 1)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "}" then return obj, i + 1 end
            if d ~= "," then error("expected ',' or '}' at " .. i) end
            i = i + 1
        end
    elseif c == "[" then
        local arr = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            arr[#arr + 1], i = parse(s, i)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "]" then return arr, i + 1 end
            if d ~= "," then error("expected ',' or ']' at " .. i) end
            i = i + 1
        end
    elseif c == '"' then
        return parse_string(s, i)
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or num == "" then error("unexpected '" .. c .. "' at " .. i) end
        return tonumber(num), i + #num
    end
end

function json.decode(s)
    local ok, value = pcall(parse, s, 1)
    if ok then return value end
    return nil, value
end

-- Reads a JSON file; nil (and why) if it's missing or broken.
function json.read(path)
    local f = io.open(path, "r")
    if not f then return nil, "missing" end
    local s = f:read("a")
    f:close()
    return json.decode(s)
end

local function encode(v, indent)
    local t = type(v)
    if t == "table" then
        local pad = string.rep("  ", indent + 1)
        if #v > 0 or next(v) == nil then
            local parts = {}
            for _, x in ipairs(v) do parts[#parts + 1] = pad .. encode(x, indent + 1) end
            if #parts == 0 then return "[]" end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", indent) .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = pad .. encode(k, indent + 1) .. ": " .. encode(v[k], indent + 1)
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", indent) .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(ch)
            for k, e in pairs(escapes) do if e == ch and k ~= "/" then return "\\" .. k end end
            return string.format("\\u%04x", ch:byte())
        end) .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "null"
end

function json.encode(v) return encode(v, 0) end

-- Writes atomically (a temporary file, then a rename).
function json.write(path, value)
    os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
    local tmp = path .. ".tmp"
    local f = assert(io.open(tmp, "w"))
    f:write(json.encode(value), "\n")
    f:close()
    return os.rename(tmp, path)
end

return json
