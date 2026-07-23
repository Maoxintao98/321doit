-- 321Doit Bridge menu launcher for DaVinci Resolve on macOS.
--
-- Resolve always ships with Lua, while its in-process Python menu support on
-- macOS only detects python.org framework installs. Launch the Python bridge
-- out of process so Homebrew Python works as well. Resolve Studio must allow
-- local external scripting for the Python process to attach.

local home = os.getenv("HOME")
local support = home .. "/Library/Application Support/321Doit/ResolveBridge"
local launcher = support .. "/321Doit Bridge.py"
local log_path = support .. "/launcher.log"

local function file_exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local function shell_quote(value)
    return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local python_candidates = {
    "/opt/homebrew/bin/python3",
    "/usr/local/bin/python3",
    "/usr/bin/python3"
}

local python = nil
for _, candidate in ipairs(python_candidates) do
    if file_exists(candidate) then
        python = candidate
        break
    end
end

if not python or not file_exists(launcher) then
    os.execute("/usr/bin/osascript -e " .. shell_quote(
        "display alert \"321Doit Bridge 无法启动\" message \"安装文件不完整，请重新运行安装器。\" as warning"))
    return
end

local api = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
local lib = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
local modules = api .. "/Modules"

local command = table.concat({
    "RESOLVE_SCRIPT_API=" .. shell_quote(api),
    "RESOLVE_SCRIPT_LIB=" .. shell_quote(lib),
    "PYTHONPATH=" .. shell_quote(modules),
    shell_quote(python),
    shell_quote(launcher),
    ">>" .. shell_quote(log_path),
    "2>&1 &"
}, " ")

os.execute(command)
