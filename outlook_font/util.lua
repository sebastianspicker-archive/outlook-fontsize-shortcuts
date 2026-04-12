local M = {}

-- True only for contiguous integer keys 1..n; tables with holes are not arrays.
local function is_array(t)
    if type(t) ~= "table" then
        return false
    end
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then
            return false
        end
        count = count + 1
    end
    return count == #t
end

local function deep_copy_impl(value, visited)
    if type(value) ~= "table" then
        return value
    end
    if visited[value] then
        return visited[value]
    end
    local out = {}
    visited[value] = out
    for k, v in pairs(value) do
        out[deep_copy_impl(k, visited)] = deep_copy_impl(v, visited)
    end
    return out
end

function M.deep_copy(value)
    return deep_copy_impl(value, {})
end

function M.deep_merge(dst, src)
    if type(dst) ~= "table" then
        dst = {}
    end
    if type(src) ~= "table" then
        return dst
    end

    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" and (not is_array(v)) and (not is_array(dst[k])) then
            dst[k] = M.deep_merge(dst[k], v)
        else
            dst[k] = M.deep_copy(v)
        end
    end
    return dst
end

function M.strip_jsonc(raw)
    if type(raw) ~= "string" then
        return raw
    end

    local out = {}
    local i = 1
    local len = #raw

    local in_string = false
    local string_quote = nil -- Track which quote character started the string
    local escape = false

    local in_line_comment = false
    local in_block_comment = false

    while i <= len do
        local ch = raw:sub(i, i)
        local next_ch = (i < len) and raw:sub(i + 1, i + 1) or ""

        if in_line_comment then
            -- Line comment ends at newline (handle both \n and \r\n)
            if ch == "\n" then
                in_line_comment = false
                table.insert(out, ch)
            elseif ch == "\r" and next_ch == "\n" then
                in_line_comment = false
                table.insert(out, ch)
                -- \n will be handled in next iteration
            end
            i = i + 1
        elseif in_block_comment then
            if ch == "*" and next_ch == "/" then
                in_block_comment = false
                i = i + 2
            else
                i = i + 1
            end
        elseif in_string then
            table.insert(out, ch)
            if escape then
                -- After an escape, the next character is literal
                -- This handles \", \\, \/, \b, \f, \n, \r, \t, \uXXXX
                escape = false
            elseif ch == "\\" then
                escape = true
            elseif ch == string_quote then
                -- String ends with the same quote that started it
                in_string = false
                string_quote = nil
            end
            i = i + 1
        else
            -- Not in string or comment
            if ch == '"' or ch == "'" then
                -- Start of a string; only double-quoted strings are valid in JSON
                in_string = true
                string_quote = ch
                table.insert(out, ch)
                i = i + 1
            elseif ch == "/" and next_ch == "/" then
                in_line_comment = true
                i = i + 2
            elseif ch == "/" and next_ch == "*" then
                in_block_comment = true
                i = i + 2
            else
                table.insert(out, ch)
                i = i + 1
            end
        end
    end

    -- Note: We don't warn about unterminated strings/comments here
    -- The JSON decoder will report parse errors if the result is invalid
    return table.concat(out)
end

return M
