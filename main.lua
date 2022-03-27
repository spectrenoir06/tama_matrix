Gamestate = require "lib.gamestate"

states = {}

states.intro  = require "gamestates.intro"
-- states.start  = require "gamestates.start"
-- states.player = require "gamestates.player"
-- states.map    = require "gamestates.map"
-- states.game   = require "gamestates.game"
-- states.pause  = require "gamestates.pause"
-- states.finish = require "gamestates.finish"

function love.load()
	Gamestate.registerEvents()
	Gamestate.switch(states.intro)
end
