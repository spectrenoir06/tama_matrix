local ffi = require("ffi")

ffi.cdef(
[[
	void lua_tamalib_init(uint32_t id);
	void lua_tamalib_step();
	void lua_tamalib_bigstep();

	void lua_tamalib_set_press_A();
	void lua_tamalib_set_release_A(); 

	void lua_tamalib_set_press_B();
	void lua_tamalib_set_release_B(); 

	void lua_tamalib_set_press_C();
	void lua_tamalib_set_release_C();

	void lua_tamalib_get_matrix_data_bin(unsigned char *ptr);

	void lua_tamalib_set_speed(uint32_t speed);

	void lua_tamalib_state_save(uint8_t *buf);
	void lua_tamalib_state_load(uint8_t* buf);
]]
)

local osString = love.system.getOS()

if osString == "Linux" then
	local content = love.filesystem.read("lib/libtama.so")
	love.filesystem.write("libtama.so", content)
	return ffi.load(love.filesystem.getSaveDirectory().."/libtama.so")
else
	local content = love.filesystem.read("lib/libtama.dll")
	love.filesystem.write("libtama.dll", content)
	return ffi.load(love.filesystem.getSaveDirectory().."/libtama.dll")
end



return nil