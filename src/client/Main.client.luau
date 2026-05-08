--!strict
--[[
	Client Boot
	Starts Knit and auto-loads all Controllers from PlayerScripts.Controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- WaitForChild (not FindFirstChild) because the Controllers folder may not be
-- replicated to PlayerScripts yet when this LocalScript first runs.
local controllersFolder = script.Parent:WaitForChild("Controllers", 5)
if controllersFolder then
    Knit.AddControllersDeep(controllersFolder)
else
    warn("[Boot] Controllers folder NOT found after 5s at " .. script.Parent:GetFullName())
end

Knit.Start()
    :andThen(function()
        print("[Knit] Client started")
    end)
    :catch(function(err)
        warn("[Knit] Client start failed:", err)
    end)
