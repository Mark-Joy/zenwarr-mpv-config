-- Copyright (c) 2018, Souche Inc.

local Constant = require "pretty.json.constant"

local NULL = Constant.NULL
local ESC_MAP = Constant.ESC_MAP

local function kind_of(obj, empty_table_as_array)
    if type(obj) ~= "table" then return type(obj) end
    if obj == NULL then return "nil" end

    local i = 1
    for _ in pairs(obj) do
        if obj[i] ~= nil then i = i + 1 else return "table" end
    end

    if i == 1 and not empty_table_as_array then
        return "table"
    else
        return "array"
    end
end

local function escape_str(s)
    return s:gsub('[\\"\a\b\f\n\r\t\v]', ESC_MAP)
end

local function sorted_pairs(obj)
    local sorted_keys = {}

    for key in pairs(obj) do
        table.insert(sorted_keys, key)
    end

    table.sort(sorted_keys)

    return coroutine.wrap(function()
        for _, key in ipairs(sorted_keys) do
            coroutine.yield(key, obj[key])
        end
    end)
end

local Serializer = {
    print_address = false,
    sort_table_keys = false,
    escape_string_values = true,
    empty_table_as_array = false,
    max_depth = 1000000
}

setmetatable(Serializer, {
    __call = function(self, opts)
        local serializer = {
            depth = 0,
            max_depth = opts.max_depth,
            print_address = opts.print_address,
            sort_table_keys = opts.sort_table_keys,
            escape_string_values = opts.escape_string_values,
            empty_table_as_array = opts.empty_table_as_array,
            stream = opts.stream
        }

        setmetatable(serializer, { __index = Serializer })

        return serializer
    end
})

function Serializer:space(n)
    local stream = self.stream
    for i = 1, n or 0 do
        stream:write(" ")
    end

    return self
end

function Serializer:key(key)
    local stream = self.stream
    local kind = kind_of(key)

    if kind == "array" then
        error("Can't encode array as key.")
    elseif kind == "table" then
        error("Can't encode table as key.")
    elseif kind == "string" then
        if self.escape_string_values then
            stream:write("\"", escape_str(key), "\"")
        else
            stream:write("\"", key, "\"")
        end
    elseif kind == "number" then
        stream:write("\"", tostring(key), "\"")
    elseif self.print_address then
        stream:write(tostring(key))
    else
        error("Unjsonifiable type: " .. kind .. ".")
    end

    return self
end

function Serializer:array(arr, replacer, indent, space)
    local stream = self.stream

    stream:write("[")
    for i, v in ipairs(arr) do
        if replacer then v = replacer(k, v) end

        stream:write(i == 1 and "" or ",")
        stream:write(space > 0 and "\n" or "")
        self:space(indent)
        self:json(v, replacer, indent + space, space)
    end
    if #arr > 0 then
        stream:write(space > 0 and "\n" or "")
        self:space(indent - space)
    end
    stream:write("]")

    return self
end

function Serializer:table(obj, replacer, indent, space)
    local stream = self.stream
    local iter = self.sort_table_keys and sorted_pairs or pairs

    stream:write("{")
    local len = 0
    for k, v in iter(obj) do
        if replacer then v = replacer(k, v) end

        if v ~= nil then
            stream:write(len == 0 and "" or ",")
            stream:write(space > 0 and "\n" or "")
            self:space(indent)
            self:key(k)
            stream:write(space > 0 and ": " or ":")
            self:json(v, replacer, indent + space, space)
            len = len + 1
        end
    end
    if len > 0 then
        stream:write(space > 0 and "\n" or "")
        self:space(indent - space)
    end
    stream:write("}")

    return self
end

function Serializer:json(obj, replacer, indent, space)
    local stream = self.stream
    local kind = kind_of(obj, self.empty_table_as_array)

    self.depth = self.depth + 1
    if self.depth > self.max_depth then error("Reach max depth: " .. tostring(self.max_depth)) end

    if kind == "array" then
        self:array(obj, replacer, indent, space)
    elseif kind == "table" then
        self:table(obj, replacer, indent, space)
    elseif kind == "string" then
        if self.escape_string_values then
            stream:write("\"", escape_str(obj), "\"")
        else
            stream:write("\"", obj, "\"")
        end
    elseif kind == "number" then
        stream:write(tostring(obj))
    elseif kind == "boolean" then
        stream:write(tostring(obj))
    elseif kind == "nil" then
        stream:write("null")
    elseif self.print_address then
        stream:write(tostring(obj))
    else
        error("Unjsonifiable type: " .. kind)
    end

    return self
end

function Serializer:toString()
    return self.stream:toString()
end

return Serializer