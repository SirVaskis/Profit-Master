"""Run offline addon checks with an existing Lua 5.1 DLL (no game interaction)."""
import ctypes
import pathlib
import sys

if len(sys.argv) != 3:
    raise SystemExit("Usage: Run-LuaChecks.py <Lua-5.1-DLL> <test.lua>")

lua = ctypes.CDLL(str(pathlib.Path(sys.argv[1]).resolve()))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.luaL_loadfile.restype = ctypes.c_int
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_pcall.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
if not state:
    raise SystemExit("Unable to allocate Lua state")
try:
    lua.luaL_openlibs(state)
    result = lua.luaL_loadfile(state, str(pathlib.Path(sys.argv[2]).resolve()).encode())
    if result == 0:
        result = lua.lua_pcall(state, 0, 0, 0)
    if result:
        error = lua.lua_tolstring(state, -1, None)
        raise SystemExit(error.decode(errors="replace") if error else "Lua check failed")
finally:
    lua.lua_close(state)
