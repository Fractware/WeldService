--!strict

local Module = {}

Module.CanWeldAnchored = false -- Can anchored objects weld to other anchored objects.

-- Welding padding variables.
Module.InnerPadding = 0.05 -- Ignore this far into the object. (Allow slight merging)
Module.OuterPadding = 0.1 -- Ignore everything past this point outside the object. (Weld slightly around the object)

local WeldCache: {[BasePart]: {[BasePart]: WeldConstraint}} = {}
local WeldConnections: {[WeldConstraint]: any} = {}

local function AddToCache(Weld: WeldConstraint) -- Add to WeldCache.
	local Success: boolean, Error: string? = pcall(function()
		WeldCache[Weld.Part0] = WeldCache[Weld.Part0] or {} -- Get or create map for Part0 welds.
		WeldCache[Weld.Part0][Weld.Part1] = Weld -- Add the weld to the Part0 map.
		
		WeldCache[Weld.Part1] = WeldCache[Weld.Part1] or {} -- Get or create map for Part1 welds.
		WeldCache[Weld.Part1][Weld.Part0] = Weld -- Add the weld to the Part1 map.
	end)
end

local function RemoveWeldCache(Weld: WeldConstraint) -- Remove from WeldCache.
	local Success: boolean, Error: string? = pcall(function()
		WeldCache[Weld.Part0][Weld.Part1] = nil -- Remove Part1 from Part0 map.
		WeldCache[Weld.Part1][Weld.Part0] = nil -- Remove Part0 from Part1 map.
	end)
	
	-- Cleanup any excessive space the objects are using in the WeldCache.
	if WeldCache[Weld.Part0] then -- Check Part0 is in the WeldCache.
		if not next(WeldCache[Weld.Part0]) then -- Is the WeldCache for Part0 not empty.
			WeldCache[Weld.Part0] = nil -- Set Part0 WeldCache to nil.
		end
	end
	
	if WeldCache[Weld.Part1] then -- Check Part1 is in the WeldCache.
		if not next(WeldCache[Weld.Part1]) then -- Is the WeldCache for Part1 not empty.
			WeldCache[Weld.Part1] = nil -- Set Part1 WeldCache to nil.
		end
	end
end

local function AddWeld(Weld: WeldConstraint)
	local Connections: {[any]: RBXScriptConnection} = {} -- Store the welds Connetions.
	
	Connections.Part0 = Weld:GetPropertyChangedSignal("Part0"):Connect(function() -- Check for Part0 changes.
		if Weld.Part0 == nil then -- Check if Part0 is nil.
			Weld:Destroy() -- Remove weld.
		end
	end)
	
	Connections.Part1 = Weld:GetPropertyChangedSignal("Part1"):Connect(function() -- Check for Part1 changes.
		if Weld.Part1 == nil then -- Check if Part1 is nil.
			Weld:Destroy() -- Remove weld.
		end
	end)
	
	WeldConnections[Weld] = Connections -- Append to the WeldConnections dictionary.
	
	AddToCache(Weld) -- Add weld to the cache.
end

for _, Weld in pairs(game:GetService("CollectionService"):GetTagged("PartWelds")) do
	AddWeld(Weld) -- Setup the weld.
end

game:GetService("CollectionService"):GetInstanceAddedSignal("PartWelds"):Connect(function(Weld: WeldConstraint)  -- Detect when weld is added.
	AddWeld(Weld) -- Setup the weld.
end)

game:GetService("CollectionService"):GetInstanceRemovedSignal("PartWelds"):Connect(function(Weld: WeldConstraint) -- Detect when weld is removed.
	WeldConnections[Weld].Part0:Disconnect() -- Disconnect Part0 changed connection.
	WeldConnections[Weld].Part1:Disconnect() -- Disconnect Part1 changed connection.
	WeldConnections[Weld] = nil -- Remove from WeldConnections dictionary.
	
	RemoveWeldCache(Weld) -- Remove from WeldCache.
end)

local function BreakJoints(Object: BasePart) -- Remove welds from specified Object.
	if WeldCache[Object] then -- Check Object is in WeldCache.
		for OtherObject, Weld in pairs(WeldCache[Object]) do -- Loop through welds in the Object.
			Weld:Destroy() -- Remove the weld.
		end
	end
end

function Module:BreakJoints(Object: BasePart | Model) -- Remove welds from specified Object. (Usable API)
	if Object then -- Check object was passed.
		if Object:IsA("BasePart") then -- Check if Object is a BasePart.
			BreakJoints(Object) -- Break the joints of the Object.
		elseif Object:IsA("Model") then -- Check if Object is a Model.
			local Descendants: {Instance} = Object:GetDescendants()
			
			local CountTarget: number = #Descendants
			local Count: number = 0
			
			-- Remove welds from descendants in the model.
			for _, SubObject in pairs(Descendants) do -- Loop through descendants in the model.
				task.spawn(function()
					if SubObject:IsA("BasePart") then -- Check the SubObject is a BasePart.
						BreakJoints(SubObject) -- Break the joints of the descendant.
					end
					
				end)
			end
			
			repeat task.wait() until Count == CountTarget -- Wait for all threads to finish.
		end
	end
	
	return true
end

function Module:GetJoinedParts(Object: BasePart) -- Get Objects welded to the specified Object.
	local WeldedObjects: {[BasePart]: boolean} = {} -- Store welded objects.
	
	if Object:IsA("BasePart") then -- Check if Object is a BasePart.
		if WeldCache[Object] then -- Check Object is in the WeldCache.
			for OtherObject, Weld in pairs(WeldCache[Object]) do -- Loop through welds for the Object.
				WeldedObjects[OtherObject] = true -- Add to the WeldedParts.
			end
		end
	elseif Object:IsA("Model") then -- Check if Object is a Model.
		local Descendants: {Instance} = Object:GetDescendants()
		
		local CountTarget: number = #Descendants
		local Count: number = 0
		
		for _, SubObject in pairs(Descendants) do -- Loop through descendants in the model.
			task.spawn(function()
				if SubObject:IsA("BasePart") then -- Check the SubObject is a BasePart.
					for _, SubWeldedObject in pairs(Module:GetJoinedParts(SubObject)) do -- Loop through the objects welded to SubObject.
						WeldedObjects[SubWeldedObject] = true -- Add to the WeldedParts.
					end
				end
				
				Count += 1
			end)
		end
		
		repeat task.wait() until Count == CountTarget -- Wait for all threads to finish.
	end
	
	return WeldedObjects -- Return the welded objects.
end

-- Setup the OverlapParameters for welding.
local OverlapParameters: OverlapParams = OverlapParams.new()
OverlapParameters.FilterType = Enum.RaycastFilterType.Whitelist

local function Weld(Object: BasePart, DoNotWeld: {BasePart}) -- Weld the object to other objects around it. Can specify a table of objects not to weld to with DoNotWeld.
	local Whitelist: {BasePart} = game:GetService("CollectionService"):GetTagged("Weldable") -- Only check Weldable objects.
	
	-- Remove objects specified in the DoNotWeld list.
	if DoNotWeld then
		for _, DoNotWeldPart in pairs(DoNotWeld) do
			table.remove(Whitelist, table.find(Whitelist, DoNotWeldPart))
		end
	end
	
	-- Check for existing welds & ignore those objects.
	local ExistingWelds: {WeldConstraint} = {}
	if WeldCache[Object] then
		for OtherObject, Weld in pairs(WeldCache[Object]) do
			table.insert(ExistingWelds, Weld)
		end
	end
	
	-- Remove ExistingWelds from the Whitelist.
	local CountTarget: number = #ExistingWelds
	local Count: number = 0
	
	for _, ExistingWeld in pairs(ExistingWelds) do
		task.spawn(function()
			for Index, Weldable in pairs(Whitelist) do
				if ExistingWeld.Part0 == Weldable or ExistingWeld.Part1 == Weldable then
					table.remove(Whitelist, Index)
				end
			end
			
			Count += 1
		end)
	end
	
	repeat task.wait() until Count == CountTarget
	
	OverlapParameters.FilterDescendantsInstances = Whitelist -- Set the OverlapParameters to only check the Whitelist.
	
	-- Welding.
	local InnerPadding: number = Module.InnerPadding -- Cache InnerPadding as a variable.
	local OuterPadding: number = Module.OuterPadding -- Cache OuterPadding as a variable.
	local Sizes: {Vector3} = {
		Object.Size + Vector3.new(OuterPadding, -InnerPadding, -InnerPadding),
		Object.Size + Vector3.new(-InnerPadding, OuterPadding, -InnerPadding),
		Object.Size + Vector3.new(-InnerPadding, -InnerPadding, OuterPadding),
	}
	
	local SizeCount: number = 0
	
	for _, Size in pairs(Sizes) do -- Loop through each axis.
		task.spawn(function()
			local TouchingObjects: {BasePart} = game:GetService("Workspace"):GetPartBoundsInBox(Object.CFrame, Size, OverlapParameters)
			
			local TouchingCount: number = 0
			
			for _, Touching in pairs(TouchingObjects) do -- Loop through each object within welding distance.
				task.spawn(function()
					if Object ~= Touching and (CanWeldAnchored or not (Object.Anchored  and Touching.Anchored)) then
						-- Create the weld.
						local NewWeld: WeldConstraint = Instance.new("WeldConstraint")
						NewWeld.Part0 = Object
						NewWeld.Part1 = Touching
						game:GetService("CollectionService"):AddTag(NewWeld, "PartWelds")
						NewWeld.Parent = Object
					end
					
					TouchingCount += 1
				end)
			end
			
			local TouchingCountTarget: number = #TouchingObjects
			repeat task.wait() until TouchingCount == TouchingCountTarget -- Wait for all threads to finish.
			
			SizeCount += 1
		end)
	end
	
	local SizeCountTarget: number = #Sizes
	repeat task.wait() until SizeCount == SizeCountTarget -- Wait for all threads to finish.
end

function Module:MakeJoints(Object: BasePart | Model, DoNotWeld) -- Weld the object to other objects around it. Can specify a table of parts not to weld to with DoNotWeld.
	if Object:IsA("BasePart") then -- Check if Object is a BasePart.
		Weld(Object, DoNotWeld) -- Weld the Object.
	elseif Object:IsA("Model") then -- Check if Object is a Model.
		local Descendants: {Instance} = Object:GetDescendants()
		
		local Count: number = 0
		
		for _, SubObject in pairs(Descendants) do -- Loop through descendants in the model.
			task.spawn(function()
				if SubObject:IsA("BasePart") and SubObject ~= Object.PrimaryPart then -- Check the SubObject is a BasePart & is not the PrimaryPart.
					Weld(SubObject, DoNotWeld) -- Weld the Object.
				end
				
				Count += 1
			end)
		end
		
		local CountTarget: number = #Descendants
		repeat task.wait() until Count == CountTarget -- Wait for all threads to finish.
	end
	
	return true
end

return Module
