local ffi = require("ffi")
-- local lib = require("lib.tamaMatrix.tamalib")
local socket = require "socket"
local json = require("lib.json")

local bit = require("bit")

ffi.cdef[[
	typedef struct { uint32_t matrix[16]; uint8_t icones; } tama_data_bin_t;
]]


-- lib.lua_tamalib_init()

local size = 2

local imageData = love.image.newImageData( 320, 320)


local matrix = {}


local intro = {}

local tama_nb = 1

function intro:init() -- Called once, and only once, before entering the state the first time

	self.udp = socket.udp()
	self.udp:settimeout(0)
	self.udp:setsockname('*', 12345)

	function pixelFunction(x, y, r, g, b, a)
		return 1, 1, 1, 1
	end
	imageData:mapPixel( pixelFunction)


	for i=1, 10 do
		-- local thread = love.thread.newThread("tama_thread.lua")
		-- local chan = love.thread.newChannel()
		-- thread:start(chan)
		local handle = io.popen("luajit tama_process.lua "..i-1)
		-- local result = handle:read("*a")
		-- handle:close()
		matrix[i] = {
			handle = handle,
			port = -1,
			id = i-1
		}
		tama_nb = i
	end
end

function intro:enter(previous) -- Called every time when entering the state
end

function intro:leave() -- Called when leaving a state.
end

function intro:resume() -- Called when re-entering a state by Gamestate.pop()
end

function intro:update(dt)
	-- self.angle = (self.angle + dt * math.pi/2) % (2*math.pi)
	-- lib.lua_tamalib_bigstep()
	-- print(dt)
	local data, msg_or_ip, port_or_nil = self.udp:receivefrom()
	if data then
		local id = love.data.unpack("I", data, 1)
		-- print(id)
		local off_x = (id*32)%320
		local off_y = math.floor(id/10)*16
		-- print(id, off_x, off_y)
		-- print(data, msg_or_ip, port_or_nil)
		for y=0, 15 do
			local d = love.data.unpack("I", data, y*4+1+4)
			for x=0, 31 do
				local pix = bit.band(d, 1)
				d = bit.rshift(d, 1)
				if pix == 0 then
					imageData:setPixel(off_x+x, off_y+y, 1, 1, 1)
				else
					imageData:setPixel(off_x+x, off_y+y, 0, 0, 0)
				end
			end
		end
	end
end

function intro:draw()
	image = love.graphics.newImage(imageData)
	image:setFilter("nearest")
	if image then
		love.graphics.draw(image,0,0,0,size,size)
	end
	love.graphics.print(love.timer.getFPS(), 10, 10)
end

function intro:focus(focus)
end

function intro:quit()
end



function intro:keypressed(key, scancode)
end

function intro:mousepressed(x,y, mouse_btn)
end

function intro:joystickpressed(joystick, button )
end

function love.keypressed(key)
	print(key)
	-- if key == "z" then
	-- 	lib.lua_tamalib_set_press_A()
	-- elseif key == "x" then
	-- 	lib.lua_tamalib_set_press_B()
	-- elseif key == "c" then
	-- 	lib.lua_tamalib_set_press_C()
	-- end
	-- local result = handle:read("*a")
	-- handle:close()
	
	tama_nb = tama_nb + 1
	local handle = io.popen("luajit tama_process.lua "..tama_nb-1)
end

function love.keyreleased( key )
	-- if key == "z" then
	-- 	lib.lua_tamalib_set_release_A()
	-- elseif key == "x" then
	-- 	lib.lua_tamalib_set_release_B()
	-- elseif key == "c" then
	-- 	lib.lua_tamalib_set_release_C()
	-- end
end
return intro
