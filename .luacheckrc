std = "lua54"

-- Hammerspoon embeds Lua 5.4 and exposes the `hs` global
globals = {
  "hs",
}

-- Keep this repo lintable outside Hammerspoon.
max_line_length = 120

exclude_files = {
  ".luarocks",
  "lua_modules",
}

-- init.lua keeps its menubar item in a global so it is not garbage-collected
files["init.lua"] = {
  globals = { "outlookFontMenu" },
}
