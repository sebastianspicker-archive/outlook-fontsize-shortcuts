std = "lua51"

-- Hammerspoon config globals
globals = {
  "hs",
}

-- Keep this repo lintable outside Hammerspoon.
max_line_length = 120

exclude_files = {
  ".luarocks",
  "lua_modules",
}

-- Busted test globals in spec/
files["spec"] = {
  std = "lua51+busted",
}
