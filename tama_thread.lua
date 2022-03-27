require "love.system"

local id = ...

local handle = io.popen("luajit tama_process.lua "..id)


