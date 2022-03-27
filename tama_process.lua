local socket = require "socket"
-- local lpack = require("pack")
local ffi = require("ffi")
local lib = require("lib.tamaMatrix.tamalib")

-- local json = require("lib.json")

-- local data = {
-- 	matrix = {},
-- 	icons = {},
-- 	id = id
-- }

-- for x=0,31 do
-- 	data.matrix[x+1] = {}
-- 	for y=0,15 do
-- 		data.matrix[x+1][y+1] = 0
-- 	end
-- end

-- for y=0,7 do
-- 	data.icons[y+1] = 0
-- end



-- local data_channel = ...
-- local data_channel = love.thread.getChannel("data")

lib.lua_tamalib_init(tonumber(arg[1]))

local udp = assert(socket.udp())
assert(udp:setsockname("0.0.0.0", 0))
udp:settimeout(0)
udp:setpeername("127.0.0.1", 12345)

while(1) do
	lib.lua_tamalib_bigstep()
	-- for x=0,31 do
	-- 	for y=0,15 do
	-- 		-- if  then
	-- 			-- love.graphics.rectangle("fill", x*10, y*10, 10, 10)
	-- 		-- end
	-- 		-- data.matrix[x+1][y+1] = lib.lua_tamalib_get_matrix_data(x,y)
	-- 	end
	-- end
	-- local buf = ffi.new("tama_data_bin_t[1]")
	local buf = ffi.new("uint8_t[?]", 72)
	lib.lua_tamalib_get_matrix_data_bin(buf)	
	-- print(buff)
	-- local buff = ""
	-- for x=0, 3 do
	-- 	buff = buff..string.pack("b",)
	-- end
	udp:send(ffi.string(buf, 72));
	-- data_channel:push(data)
end


