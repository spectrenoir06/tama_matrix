local ffi       = require("ffi")
local lib       = require("lib.tamalib")
local socket    = require("socket")
local bit       = require("bit")
local moonshine = require("lib.moonshine")

local timer = 0
local SAVE_SIZE = 816
local DATA_SIZE = 76

local intro = {}

function intro:init() -- Called once, and only once, before entering the state the first time
	lib.lua_tamalib_init(0)

	local save = love.filesystem.read( "save.state")
	if save then
		local c_str = ffi.new("char[?]", #save + 1)
		ffi.copy(c_str, save)

		lib.lua_tamalib_state_load(c_str)
	else
		local save = love.filesystem.read( "res/start.state")
		if save then
			local c_str = ffi.new("char[?]", #save + 1)
			ffi.copy(c_str, save)
			lib.lua_tamalib_state_load(c_str)
		end
	end

	self.icones = {}
	for i=0,7 do
		self.icones[i] = love.graphics.newImage( "res/icone"..i..".png")
		-- self.icones[i]:setFilter("nearest")
	end

	self.icone_bin = 0

	self.udp = socket.udp()
	self.udp:settimeout(0)
	self.udp:setsockname('*', 12345)


	self.imageData = love.image.newImageData( 32, 16)
	function pixelFunction(x, y, r, g, b, a) return 1, 1, 1, 1 end
	self.imageData:mapPixel( pixelFunction) -- clear imgData

	self.effect = moonshine(moonshine.effects.glow)
		.chain(moonshine.effects.filmgrain).chain(moonshine.effects.scanlines).chain(moonshine.effects.crt).chain(moonshine.effects.chromasep)

	self.effect.parameters = {
		glow = {strength = 15},
		crt = {distortionFactor = {1.06, 1.065}},
		chromasep = { radius=4, angle=1},
		scanlines = { opacity = 0.4, width=4},
		filmgrain = {opacity = 0.3, size =1}
	}

	self.is_playing = false
end

function intro:enter(previous) -- Called every time when entering the state
end

function intro:leave() -- Called when leaving a state.
end

function intro:resume() -- Called when re-entering a state by Gamestate.pop()
end

function intro:update(dt)
	local data, msg_or_ip, port_or_nil = self.udp:receivefrom()
	if data then
		print(data)
		if data == "A1" then
			lib.lua_tamalib_set_press_A()
		elseif data == "B1" then
			lib.lua_tamalib_set_press_B()
		elseif data == "C1" then
			lib.lua_tamalib_set_press_C()
		elseif data == "A0" then
			lib.lua_tamalib_set_release_A()
		elseif data == "B0" then
			lib.lua_tamalib_set_release_B()
		elseif data == "C0" then
			lib.lua_tamalib_set_release_C()
		end
	end


	lib.lua_tamalib_bigstep() -- calculate tamagotchi
	local buf = ffi.new("uint8_t[?]", DATA_SIZE)
	lib.lua_tamalib_get_matrix_data_bin(buf)

	local data = ffi.string(buf, DATA_SIZE)
	if data then
		local id = love.data.unpack("I", data, 1)
		local off_x = (id*32)%320
		local off_y = math.floor(id/10)*16
		for y=0, 15 do
			local d = love.data.unpack("I", data, y*4+1+4)
			for x=0, 31 do
				local pix = bit.band(d, 1)
				d = bit.rshift(d, 1)
				if pix == 0 then
					self.imageData:setPixel(off_x+x, off_y+y, 1, 1, 1)
				else
					self.imageData:setPixel(off_x+x, off_y+y, 0, 0, 0)
				end
			end
		end
		self.icone_bin = love.data.unpack("B", data, 16*4+1+4)
		self.playsound = love.data.unpack("B", data, 16*4+1+5)
		self.freq = love.data.unpack("I", data, 16*4+1+8)
		
		if self.playsound == 1 then
			if not self.is_playing or self.freq ~= self.last_freq then
				-- print(playsound, freq)
				local rate      = 44100 -- samples per second
				local length    = 2  --1/32 =  0.03125 seconds
				local tone      = self.freq/10 -- Hz
				local p         = math.floor(rate/tone) -- 100 (wave length in samples)
				local soundData = love.sound.newSoundData(math.floor(length*rate), rate, 16, 1)
				for i=0, soundData:getSampleCount() - 1 do
					-- soundData:setSample(i, math.sin(2*math.pi*i/p)) -- sine wave.
					soundData:setSample(i, i%p<p/2 and 1 or -1)     -- square wave; the first half of the wave is 1, the second half is -1.
				end
				self.source = love.audio.newSource(soundData)
				-- source:setLooping(true)
				love.audio.play(self.source)
				self.is_playing = true
				self.last_freq = self.freq
			else
			end
		else
			if (self.is_playing) then
				self.source:stop()
				self.is_playing = false
			end
		end
	end
	timer = timer + dt
	if timer > 5 then
		local save = ffi.new("uint8_t[?]", SAVE_SIZE)
		lib.lua_tamalib_state_save(save)
		love.filesystem.write("save.state", ffi.string(save, SAVE_SIZE))
		timer = 0
	end
end

function intro:draw()
	self.image = love.graphics.newImage(self.imageData)
	self.image:setFilter("nearest")
	if self.image then
		local lx = love.graphics.getWidth() / 32
		self.effect(function()
			love.graphics.draw(self.image,0,8*20,0,lx,lx)
			for i=0, 7 do
				if bit.band((bit.rshift(self.icone_bin, i)), 1) == 1 then
					local y = 0
					if (i> 3) then
						y = 496
					end
					
					love.graphics.draw(
						self.icones[i],
						(i%4)*160,
						y,
						0,
						3,
						3
					)
				end
			end
		end)
	end
	-- love.graphics.print(love.timer.getFPS(), 10, 10)
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
	if key == "left" then
		lib.lua_tamalib_set_press_A()
	elseif key == "down" then
		lib.lua_tamalib_set_press_B()
	elseif key == "right" then
		lib.lua_tamalib_set_press_C()
	elseif key == "space" then
		lib.lua_tamalib_set_speed(0)
	-- elseif key== "q" then
	-- 	save = ffi.new("uint8_t[?]", SAVE_SIZE)
	-- 	lib.lua_tamalib_state_save(save)
	-- elseif key== "w" then
	-- 	lib.lua_tamalib_state_load(save)
	end
end

function love.keyreleased( key )
	if key == "left" then
		lib.lua_tamalib_set_release_A()
	elseif key == "down" then
		lib.lua_tamalib_set_release_B()
	elseif key == "right" then
		lib.lua_tamalib_set_release_C()
	elseif key == "space" then
		lib.lua_tamalib_set_speed(1)
	end
end

function love.resize(x,y) 

	effect = moonshine(moonshine.effects.glow)
		.chain(moonshine.effects.filmgrain).chain(moonshine.effects.scanlines).chain(moonshine.effects.crt).chain(moonshine.effects.chromasep)

	effect.parameters = {
		glow = {strength = 15},
		crt = {distortionFactor = {1.06, 1.065}},
		chromasep = { radius=4, angle=1},
		scanlines = { opacity = 0.4, width=4},
		filmgrain = {opacity = 0.3, size =1}
	}
end

return intro
