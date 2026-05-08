--!strict
--[[
	Server Boot
	Starts Knit and auto-loads all Services from ServerScriptService.Services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local servicesFolder = ServerScriptService:FindFirstChild("Services")
if servicesFolder then
    Knit.AddServicesDeep(servicesFolder)
end

Knit.Start()
    :andThen(function()
        print("[Knit] Server started")
    end)
    :catch(warn)
