local ffi       = require("ffi")
local lib       = require("lib.tamalib")
local socket    = require("socket")
local bit       = require("bit")
local moonshine = require("lib.moonshine")

local timer = 0
local SAVE_SIZE = 816
local DATA_SIZE = 76

local intro = {}

function dump(o)
	if type(o) == 'table' then
	   local s = '{ '
	   for k,v in pairs(o) do
		  if type(k) ~= 'number' then k = '"'..k..'"' end
		  s = s .. '['..k..'] = ' .. dump(v) .. ','
	   end
	   return s .. '} '
	else
	   return tostring(o)
	end
 end

--[[
RAM map
0x00 (M0): 	Lower PC for graphics draw
0x01 (M1): 	Upper PC for graphics draw
0x02 (M2): 	Value ANDed with 7 that indicates which graphics page is used


0x06 : minute ( Lower digit ) // only update in menu
0x07 : minute ( Upper digit ) // only update in menu

0x10 : second ( Lower digit )
0x11 : second ( Upper digit )

0x12 : minute ( Lower digit )
0x13 : minute ( Upper digit )

0x14 : hour ( less significant bit)
0x15 : hour ( most significant bit x16)

0x2F : couter ? ( less significant bit)
0x30 : counter 
0x31 : counter ( most significant bit)

0x32 : counter 2 ( less significant bit)
0x33 : counter 2 ( most significant bit)

0x40 : hunger / 8 = (food = 4)
0x41 : happiness / 4 = (snack = 4)
0x42 : care (start a 0 at 10 die ?)
0x43 : discipline

0x44 ?
0x45 ? 

0x46 : weight ( Lower digit )
0x47 : weight ( Upper digit )
0x48 : heath ( sick if > 8)
0x49 ??
ox4A: if >8 sleep
0x4B : if 0 light off else light one
0x4C ??
0x4D : shit


0x54 : age ( Lower digit )
0x55 : age ( Upper digit )
0x57 : timeout menu

0x5C make it sleep ?
0x5D : stage

0x75 : menu select
0x76 : 2 if submenu else 8

0x90 : if 7 then select menu 0 else if f then menu 1 


food select


]]

function intro:init() -- Called once, and only once, before entering the state the first time
	love.audio.setVolume(0.1)
	lib.lua_tamalib_init(0)
	local save = love.filesystem.read( "save.state")
	if save then -- if save file exist
		local c_str = ffi.new("char[?]", #save + 1)
		ffi.copy(c_str, save)

		lib.lua_tamalib_state_load(c_str) -- load save in tamagotchi
	else
		local save = love.filesystem.read( "res/start.state") -- load default save
		if save then
			local c_str = ffi.new("char[?]", #save + 1)
			ffi.copy(c_str, save)
			lib.lua_tamalib_state_load(c_str) -- load save in tamagotchi
		end
	end

	self.icones = {}
	for i=0,7 do
		self.icones[i] = love.graphics.newImage("res/icone"..i..".png")
		self.icones[i]:setFilter("nearest")
	end

	self.font = love.graphics.newImageFont("res/decimal_font.png", "0123456789:", 1)
	self.font:setFilter("nearest")

	self.weight_icon = love.graphics.newImage("res/weight.png")
	self.weight_icon:setFilter("nearest")

	self.age_icon = love.graphics.newImage("res/age.png")
	self.age_icon:setFilter("nearest")

	self.food_icon = love.graphics.newImage("res/food.png")
	self.food_icon:setFilter("nearest")

	self.snack_icon = love.graphics.newImage("res/snack.png")
	self.snack_icon:setFilter("nearest")

	self.shit_icon = love.graphics.newImage("res/shit.png")
	self.shit_icon:setFilter("nearest")


	self.icone_bin = 0

	self.udp = socket.udp()
	self.udp:settimeout(0)
	self.udp:setsockname('*', 12345)


	self.imageData = love.image.newImageData( 32, 16)
	function pixelFunction(x, y, r, g, b, a) return 1, 1, 1, 1 end
	self.imageData:mapPixel( pixelFunction) -- clear imgData

	self:reload_shader()
	self.is_playing = false

	self.icone_warning = false

	self.queue = {}
end

function intro:enter(previous) -- Called every time when entering the state
end

function intro:leave() -- Called when leaving a state.
end

function intro:resume() -- Called when re-entering a state by Gamestate.pop()
end

function intro:reload_shader()
	self.effect = moonshine(moonshine.effects.glow)
	.chain(moonshine.effects.filmgrain).chain(moonshine.effects.scanlines).chain(moonshine.effects.crt).chain(moonshine.effects.chromasep)

	self.effect.parameters = {
		glow = {strength = 15},
		crt = {distortionFactor = {1.06, 1.065}},
		chromasep = { radius=4, angle=1},
		scanlines = { opacity = 0.4, width=2},
		filmgrain = {opacity = 0.3, size =1}
	}
	self.need_reload_shader = false
end

function intro:update(dt)
	-- print(dt)
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

	if #self.queue > 0 then
		-- print(dump(self.queue))
		local event = self.queue[1]
		if event.exe then
			event.exe()
			event.exe = nil
		end
		if event.delay > 0 then
			event.delay = event.delay - dt
		end
		if event.delay <= 0 then
			-- print("remove")
			table.remove(self.queue, 1)
		end
	else
		info = self:getTamaInfo()
		if (self.icone_warning or info.shit > 0 or info.is_sick) and self.speed_up then
			self.speed_up = false
			lib.lua_tamalib_set_speed(1)
		end
		-- print(info.stage)
		if not self.speed_up then
			if info.stage > 0 then -- is alive
				if info.is_sleeping == false then -- is not sleeping
					if info.is_sick then
						self:tamaHeal()
					elseif info.shit > 0 then
						self:tamaClean()
					elseif self.icone_warning and info.hunger > 0 and info.happiness > 0 then -- is a bitch
						self:tamaDiscipline()
					elseif info.hunger < 13 then
						self:tamaFeed()
					elseif info.happiness < 13 then
						self:tamaSnack()
					else
						self.speed_up = true
						lib.lua_tamalib_set_speed(0)
					end
				else
					if info.is_light_on then
						self:tamaTurnLightOff()
					else
						self.speed_up = true
						lib.lua_tamalib_set_speed(0)
					end
				end
			end
		end
	end


	lib.lua_tamalib_bigstep() -- calculate tamagotchi
	local buf = ffi.new("uint8_t[?]", DATA_SIZE)
	lib.lua_tamalib_get_matrix_data_bin(buf)

	local data = ffi.string(buf, DATA_SIZE)
	if data then
		-- print("data")
		local id = love.data.unpack("I", data, 1)
		local off_x = (id*32)%320
		local off_y = math.floor(id/10)*16
		for y=0, 15 do
			local d = love.data.unpack("I", data, y*4+1+4)
			for x=0, 31 do
				local pix = bit.band(d, 1)
				d = bit.rshift(d, 1)
				if pix == 0 then
					self.imageData:setPixel(off_x+x, off_y+y, 0, 0, 0)
				else
					self.imageData:setPixel(off_x+x, off_y+y, 1, 1, 1)
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

		-- self.print_ram()

		if bit.band(self.icone_bin, 0x80) == 0x80 then
			if self.icone_warning == false then -- if the warning icone turn on
				-- print("warning")
				self.icone_warning = true
			else 
			end
		else
			if self.icone_warning == true then -- if the warning icone turn off
				-- print("no warning")
				self.icone_warning = false
				-- self.print_ram()
			else 
				
			end
		end



	end
	timer = timer + dt
	if timer > 5 then
		local save = ffi.new("uint8_t[?]", SAVE_SIZE)
		lib.lua_tamalib_state_save(save)
		love.filesystem.write("save.state", ffi.string(save, SAVE_SIZE))
		timer = 0
		if self.need_reload_shader then
			self:reload_shader()
		end

	end
end

function intro:render()
	-- local lx = love.graphics.getWidth() / 32
	-- local ly = love.graphics.getHeight() / 32
	-- local min = math.min(lx, ly)

	
	local real_min = math.min(love.graphics.getWidth(), love.graphics.getHeight())
	local origin_x = (love.graphics.getWidth()-real_min)/2
	local origin_y = (love.graphics.getHeight()-real_min)/2

	local screen_scale = real_min / 32 -- how much to scale the screen

	local icone_size = real_min / 4 
	local icone_scale = icone_size / self.icones[0]:getHeight() -- how much to scale the icones
	
	love.graphics.draw(self.image, origin_x, origin_y+real_min/2, 0, screen_scale, screen_scale, 0, self.image:getHeight()/2)
	
	-- love.graphics.rectangle("line", origin_x, origin_y, real_min, real_min)
	-- love.graphics.rectangle("line", love.graphics.getWidth() / 2 - (32*min)/2, 8*ly, 32*min, 16*min)
	-- love.graphics.rectangle("line", love.graphics.getWidth() / 2 - (32*min)/2, 8*ly - self.icones[1]:getHeight()*3, love.graphics.getWidth() , self.icones[1]:getHeight()*3)
	for i=0, 7 do
		if bit.band((bit.rshift(self.icone_bin, i)), 1) == 1 then
			local y = 0
			if (i> 3) then
				y = 3 * icone_size
			end
			love.graphics.draw(
				self.icones[i],
				origin_x+(i%4)*icone_size, -- x
				origin_y+y, -- y
				0, -- rotation
				icone_scale, -- scale x
				icone_scale -- scale y
			)
		end
	end
end

function intro:getTamaInfo()
	local save = ffi.new("uint8_t[?]", SAVE_SIZE)
	lib.lua_tamalib_state_save(save)

	local hour = (save[48+0x14] + save[48+0x015]*16) -- hour
	local minute = (save[48+0x12] + save[48+0x13]*10) -- minute
	local seconde = (save[48+0x10] + save[48+0x11]*10) -- seconde
	
	-- love.graphics.print(string.format("hour: %02d:%02d:%02d", hour, minute, seconde), 10, 30)

	local age = save[48+0x54] + save[48+0x55]*10 -- age
		-- love.graphics.print("age: "..age, 10, 50)

	local weight = save[48+0x46] + save[48+0x47]*10 -- weight
	-- love.graphics.print("weight: "..weight, 100, 50)

	local hunger = save[48+0x40] 
	-- love.graphics.print("hunger: "..hunger, 10, 70)

	local happiness = save[48+0x41] 
	-- love.graphics.print("happiness: "..happiness, 100, 70)

	local discipline = save[48+0x43]
	-- love.graphics.print("discipline: "..discipline, 10, 90)

	local health = save[48+0x48]
	-- love.graphics.print("health: "..health, 100, 90)


	local stage = save[48+0x5D] -- stage
	-- love.graphics.print("stage: "..stage, 10, 110)
	
	local shit = save[48+0x4D]
	-- love.graphics.print("shit: "..shit, 100, 110)

	local care = save[48+0x42]
	-- love.graphics.print("care: "..care, 100, 130)

	local ctn = save[48+0x2c]
	-- love.graphics.print("ctn: "..ctn, 100, 150)

	local ctn2 = save[48+0x2d]
	-- love.graphics.print("ctn2: "..ctn2, 100, 170)

	local sleep = save[48+0x4A]

	local light = save[48+0x4B]

	return {
		hour = hour,
		minute = minute,
		seconde = seconde,

		age = age,
		weight = weight,
		hunger = hunger,
		happiness = happiness,
		discipline = discipline,
		stage = stage,
		shit = shit,
		care = care,
		is_sleeping = sleep >= 8,
		is_light_on = light == 0xF,
		is_sick = health > 8
	}
end 

function intro:tamaFeed()
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x57, 0xA) -- timeout reset
			self:tamaSetRegister(0x75, 0x1) -- select food
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B()
			print("open food menu")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_B() -- press b to open submenu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x75, 0x0) -- select food
			print("select food")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B() -- press b to open submenu
			print("press b")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 6,
		exe = function()
			lib.lua_tamalib_set_release_B() -- press b to feed
			print("release b")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_C() -- press b to open submenu
			print("press c")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_C() -- press b to feed
			print("release c")
		end
	}
end

function intro:tamaSnack()
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x57, 0xA) -- timeout reset
			self:tamaSetRegister(0x75, 0x1) -- select food
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B()
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_B() -- press b to open submenu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x75, 0x1) -- select snack
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B() -- press b to open submenu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 6,
		exe = function()
			lib.lua_tamalib_set_release_B() -- press b to feed
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_C() -- close all menu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_C() -- close all menu
		end
	}
end

function intro:tamaClean()
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x57, 0xA) -- timeout reset
			self:tamaSetRegister(0x75, 0x5) -- select clean
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B() -- clean
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 6,
		exe = function()
			lib.lua_tamalib_set_release_B()
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_C() -- close all menu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 1,
		exe = function()
			lib.lua_tamalib_set_release_C() -- close all menu
		end
	}
end

function intro:tamaHeal()
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x57, 0xA) -- timeout reset
			self:tamaSetRegister(0x75, 0x4) -- select heal
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B() -- heal
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 6,
		exe = function()
			lib.lua_tamalib_set_release_B()
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_C() -- close all menu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_C() -- close all menu
		end
	}
end


function intro:tamaDiscipline()
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x57, 0xA) -- timeout reset
			self:tamaSetRegister(0x75, 0x7) -- select discipline
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B() -- discipline
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 6,
		exe = function()
			lib.lua_tamalib_set_release_B()
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_C() -- close all menu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_C() -- close all menu
		end
	}
end

function intro:tamaTurnLightOff()
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x57, 0xA) -- timeout reset
			self:tamaSetRegister(0x75, 0x2) -- select light
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B()
			print("open light menu")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_release_B() -- press b to open submenu
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			self:tamaSetRegister(0x75, 0x1) -- select food
			print("select off")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_B() -- press b to open submenu
			print("press b")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 6,
		exe = function()
			lib.lua_tamalib_set_release_B() -- press b to feed
			print("release b")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 0.5,
		exe = function()
			lib.lua_tamalib_set_press_C() -- press b to open submenu
			print("press c")
		end
	}
	self.queue[#self.queue + 1] = {
		delay = 1,
		exe = function()
			lib.lua_tamalib_set_release_C() -- press b to feed
			print("release c")
		end
	}
end

function intro:draw()
	self.image = love.graphics.newImage(self.imageData)
	self.image:setFilter("nearest")
	if self.image then
		if self.use_shader then
			self.effect(function()
				self:render()
			end)
		else 
			self:render()
		end


		love.graphics.scale(2, 2)

		info = self:getTamaInfo()
		
		-- love.graphics.setFont(8)


		love.graphics.reset()

		-- love.graphics.
		love.graphics.scale(10, 10)
		love.graphics.setFont(self.font)

		love.graphics.print(string.format("%02d:%02d:%02d", info.hour, info.minute, info.seconde), 2, 0)

		love.graphics.draw(self.weight_icon, 10, 10)
		love.graphics.print(info.weight, 22, 11)

		love.graphics.draw(self.age_icon, 11, 21)
		love.graphics.print(info.age, 22, 20)

		love.graphics.draw(self.food_icon, 10, 30)
		love.graphics.print(info.hunger, 22, 30)

		love.graphics.draw(self.snack_icon, 10, 40)
		love.graphics.print(info.happiness, 22, 40)

		love.graphics.draw(self.shit_icon, 10, 49)
		love.graphics.print(info.shit, 22, 50)

		love.graphics.print(info.discipline, 10, 60)
		love.graphics.print(info.care, 10 , 70) 



	end

	

	-- print(save)

	-- love.graphics.draw(self.image, 100, 0)
	-- love.graphics.print("fps: "..love.timer.getFPS(), 10, 10)
end

function intro:focus(focus)
end

function intro:quit()
end



-- function intro:keypressed(key, scancode)
-- end

function intro:mousepressed(x,y, mouse_btn)
end

function intro:joystickpressed(joystick, button )
end

local previous_ram = nil

function intro:print_ram()
	local save = ffi.new("uint8_t[?]", SAVE_SIZE)
	lib.lua_tamalib_state_save(save)

	-- for i=0, 0x280 do
	-- 	print(i, save[48+i])
	-- end
	-- print hex table
	local str = ""
	-- clear terminal
	os.execute("clear")
	-- print("\n\n\n")
	local header = "    | "
	for i = 0, 15 do
		header = header .. string.format("%01X ", i)
	end
	print(header)
	print(string.rep("-", #header))
	for i=0, 0x80 do
		local val = string.format("%01X ", save[48+i])
		str = str .. val
		if (i%16 == 15) then
			print(string.format("%03X | ", i - 0xF) .. str)
			-- print(str)
			str = ""
		end
	end

	-- local str = ""
	-- local header = "    | "
	-- for i = 0, 15 do
	-- 	header = header .. string.format("%01X ", i)
	-- end
	-- print(header)
	-- print(string.rep("-", #header).."\n")
	-- for i=0, 0x80 do
	-- 	local val = string.format("%01X ", save[48+i])
	-- 	if previous_ram and save[48+i] == previous_ram[48+i] then
	-- 		val = "  "
	-- 	end
	-- 	str = str .. val
	-- 	if (i%16 == 15) then
	-- 		print(string.format("%03X | ", i - 0xF) .. str)
	-- 		-- print(str)
	-- 		str = ""
	-- 	end
	-- end
	-- previous_ram = save
end

function intro:tamaSetRegister(register, value)
	local save = ffi.new("uint8_t[?]", SAVE_SIZE)
	lib.lua_tamalib_state_save(save)
	save[48+register] = value
	lib.lua_tamalib_state_load(save) -- load save in tamagotchi
end

function intro:keypressed(key)
	-- print(key)
	if key == "left" then
		lib.lua_tamalib_set_press_A()
	elseif key == "down" then
		lib.lua_tamalib_set_press_B()
	elseif key == "right" then
		lib.lua_tamalib_set_press_C()
	elseif key == "space" then
		self.speed_up = true
		lib.lua_tamalib_set_speed(0)
	-- elseif key== "q" then
	-- 	save = ffi.new("uint8_t[?]", SAVE_SIZE)
	-- 	lib.lua_tamalib_state_save(save)
	-- elseif key== "w" then
	-- 	lib.lua_tamalib_state_load(save)
	end
	if key == "f" then
		self.use_shader = false
	elseif key == 'g' then
		self.use_shader = true
	end

	if key == "2" then
		self:tamaClean()
	end

	if key == "4" then
		self:tamaSnack()
	end

	if key == "5" then
		self:tamaFeed()
	end

	if key == "6" then
		self:tamaDiscipline()
	end

	if key == "3" then
		-- local save = ffi.new("uint8_t[?]", SAVE_SIZE)
		-- lib.lua_tamalib_state_save(save)
		
		local hour   = tonumber(os.date("%H"))
		local minute = tonumber(os.date("%M"))
		local second = tonumber(os.date("%S"))
		
		-- save[48+0x14] = hour%16
		-- save[48+0x015] = math.floor(hour/16)
		self:tamaSetRegister(0x14, hour%16)
		self:tamaSetRegister(0x15, math.floor(hour/16))


		-- save[48+0x12] = minute%10
		-- save[48+0x13] = math.floor(minute/10)
		self:tamaSetRegister(0x12, minute%10)
		self:tamaSetRegister(0x13, math.floor(minute/10))

		-- save[48+0x10] = second%10
		-- save[48+0x11] = math.floor(second/10)
		self:tamaSetRegister(0x10, second%10)
		self:tamaSetRegister(0x11, math.floor(second/10))


		-- lib.lua_tamalib_state_load(save) -- load save in tamagotchi
	end
	

	if key == "1" then
		self.effect.disable("filmgrain")
	end
end

function intro:keyreleased( key )
	if key == "left" then
		lib.lua_tamalib_set_release_A()
	elseif key == "down" then
		lib.lua_tamalib_set_release_B()
	elseif key == "right" then
		lib.lua_tamalib_set_release_C()
	elseif key == "space" then
		self.speed_up = false
		lib.lua_tamalib_set_speed(1)
	end
	-- if key == "space" then
	-- 	self:reload_shader()
	-- end
end

function intro:resize(x,y) 
	self.effect.resize(x, y)
	self.need_reload_shader = true
end

return intro
