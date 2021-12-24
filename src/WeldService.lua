--!strict

local Module = {}

local Utilities = require(script.Parent.Utilities)

local WeldCache = {}

local function AddToCache(Weld)
	local Success: boolean, Error: string? = pcall(function()
		WeldCache[Weld.Part0] = WeldCache[Weld.Part0] or {}
		WeldCache[Weld.Part0][Weld.Part1] = Weld
		
		WeldCache[Weld.Part1] = WeldCache[Weld.Part1] or {}
		WeldCache[Weld.Part1][Weld.Part0] = Weld
	end)
end

local function RemoveWeldCache(Weld)
	local Success: boolean, Error: string? = pcall(function()
		WeldCache[Weld.Part0][Weld.Part1] = nil
		WeldCache[Weld.Part1][Weld.Part0] = nil
	end)
end

local function RemoveEmptyCache(Weld)
	if WeldCache[Weld.Part0] then
		if not next(WeldCache[Weld.Part0]) then
			WeldCache[Weld.Part0] = nil
		end
	end
	
	if WeldCache[Weld.Part1] then
		if not next(WeldCache[Weld.Part1]) then
			WeldCache[Weld.Part1] = nil
		end
	end
end

for _, Weld in pairs(game:GetService("CollectionService"):GetTagged("PartWelds")) do
	AddToCache(Weld)
end

game:GetService("CollectionService"):GetInstanceAddedSignal("PartWelds"):Connect(function(Weld: WeldConstraint)
	AddToCache(Weld)
end)

game:GetService("CollectionService"):GetInstanceRemovedSignal("PartWelds"):Connect(function(Weld: WeldConstraint)
	RemoveWeldCache(Weld)
	
	RemoveEmptyCache(Weld)
end)

local function BreakJoints(Object: BasePart)
	if WeldCache[Object] then
		for OtherObject, Weld in pairs(WeldCache[Object]) do
			RemoveWeldCache(Weld)
			
			Weld:Destroy()
			
			RemoveEmptyCache(Weld)
		end
	end
end

function Module:BreakJoints(Object: BasePart | Model)
	if Object then
		if Object:IsA("Model") then
			local Count = 0
			local CountTarget = #Object:GetChildren()
			
			for _, SubObject in pairs(Object:GetChildren()) do
				task.spawn(function()
					BreakJoints(SubObject)
					Count += 1
				end)
			end
			
			repeat task.wait() until Count == CountTarget
		elseif Object:IsA("BasePart") then
			BreakJoints(Object)
		end
	end
	
	return true
end

function Module:GetJoinedParts(Object: BasePart | Model)
	if not Object:IsA("Model") then
		local WeldedParts = {}
		
		if WeldCache[Object] then
			for OtherObject, Weld in pairs(WeldCache[Object]) do
				WeldedParts[OtherObject] = true
			end
		end
		
		return WeldedParts
	end
end

local OverlapParameters = OverlapParams.new()
OverlapParameters.FilterType = Enum.RaycastFilterType.Whitelist

local function Weld(Object: BasePart, DoNotWeld)
	if Utilities:IsInSafeZone(Object.Position, Object.Size.X / 2) then
		return
	end
	
	local ExistingWelds = {}
	if WeldCache[Object] then
		for OtherObject, Weld in pairs(WeldCache[Object]) do
			table.insert(ExistingWelds, Weld)
		end
	end
	
	local Whitelist = game:GetService("CollectionService"):GetTagged("Weldable")
	
	if DoNotWeld then
		for Index, FilterDescendant in pairs(Whitelist) do
			for _, DoNotWeldPart in pairs(DoNotWeld) do
				if DoNotWeldPart == FilterDescendant then
					table.remove(Whitelist, Index)
				end
			end
		end
	end
	
	OverlapParameters.FilterDescendantsInstances = Whitelist
	
	local SizeCount: number = 0
	local Sizes = {
		Object.Size + Vector3.new(0.1, -0.05, -0.05),
		Object.Size + Vector3.new(-0.05, 0.1, -0.05),
		Object.Size + Vector3.new(-0.05, -0.05, 0.1),
	}
	local SizeCountTarget: number = #Sizes
	
	for _, Size in pairs(Sizes) do
		task.spawn(function()
			local TouchingObjects = game:GetService("Workspace"):GetPartBoundsInBox(Object.CFrame, Size, OverlapParameters)
			
			local TouchingCount: number = 0
			local TouchingCountTarget: number = #TouchingObjects
			
			for _, Touching in pairs(TouchingObjects) do
				task.spawn(function()
					if Object ~= Touching then
						local CanWeld: boolean = true
						
						for _, ExistingWeld in pairs(ExistingWelds) do
							if ExistingWeld.Part0 == Touching or ExistingWeld.Part1 == Touching then
								CanWeld = false
								break
							end
						end
						
						if CanWeld then
							local NewWeld: WeldConstraint = Instance.new("WeldConstraint")
							NewWeld.Part0 = Object
							NewWeld.Part1 = Touching
							game:GetService("CollectionService"):AddTag(NewWeld, "PartWelds")
							NewWeld.Parent = Object
							table.insert(ExistingWelds, NewWeld)
						end
					end
					
					TouchingCount += 1
				end)
			end
			
			repeat task.wait() until TouchingCount == TouchingCountTarget
			
			SizeCount += 1
		end)
	end
	
	repeat task.wait() until SizeCount == SizeCountTarget
end

function Module:MakeJoints(Object: BasePart | Model, DoNotWeld)
	if Object:IsA("BasePart") then
		Weld(Object, DoNotWeld)
	elseif Object:IsA("Model") then
		local SubObjectCount: number = 0
		local SubObjectCountTarget: number = #Object:GetChildren()
		for _, SubObject in pairs(Object:GetChildren()) do
			task.spawn(function()
				if SubObject:IsA("BasePart") and SubObject ~= Object.PrimaryPart then
					Weld(SubObject, DoNotWeld)
				end
				SubObjectCount += 1
			end)
		end
		repeat task.wait() until SubObjectCount == SubObjectCountTarget
	end
	
	return true
end

return Module