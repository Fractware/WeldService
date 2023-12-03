--!strict

local CollectionService = game:GetService("CollectionService")
local WorkspaceService = game:GetService("Workspace")

local Module = {
	CanWeldAnchored = false, -- Can anchored objects weld to other anchored objects.
	
	-- Welding padding variables.
	InnerPadding = 0.05, -- Ignore this far into the object. (Allow slight merging)
	OuterPadding = 0.1, -- Ignore everything past this point outside the object. (Weld slightly around the object)
}

local ConnectionCache: {[WeldConstraint]: {[any]: RBXScriptConnection}} = {}
local LinkCache: {[BasePart]: {[BasePart]: WeldConstraint}} = {}
local WeldableCache: {[BasePart]: boolean} = {}

for _, Weldable in CollectionService:GetTagged("Weldable") do
	if not Weldable:IsDescendantOf(WorkspaceService) then continue end
	WeldableCache[Weldable] = true
end

CollectionService:GetInstanceAddedSignal("Weldable"):Connect(function(Weldable: BasePart)
	if not Weldable:IsDescendantOf(WorkspaceService) then return end
	WeldableCache[Weldable] = true
end)

CollectionService:GetInstanceRemovedSignal("Weldable"):Connect(function(Weldable: BasePart)
	WeldableCache[Weldable] = nil
end)

local function AddConnectionCache(Weld: WeldConstraint)
	ConnectionCache[Weld] = { -- Append to the WeldConnections dictionary.
		Part0 = Weld:GetPropertyChangedSignal("Part0"):Connect(function() -- Check for Part0 changes.
			if Weld.Part0 ~= nil then return end -- Check if Part0 is nil.
			Weld:Destroy() -- Remove weld.
		end),
		Part1 = Weld:GetPropertyChangedSignal("Part1"):Connect(function() -- Check for Part1 changes.
			if Weld.Part1 ~= nil then return end -- Check if Part1 is nil.
			Weld:Destroy() -- Remove weld.
		end),
	}
end

local function RemoveConnectionCache(Weld: WeldConstraint)
	ConnectionCache[Weld].Part0:Disconnect() -- Disconnect Part0 changed connection.
	ConnectionCache[Weld].Part1:Disconnect() -- Disconnect Part1 changed connection.
	ConnectionCache[Weld] = nil -- Remove from WeldConnections dictionary.
end

local function AddLinkCache(Weld: WeldConstraint) -- Add to WeldCache.
	local Part0: BasePart? = Weld.Part0
	local Part1: BasePart? = Weld.Part1
	
	if Part0 and Part1 then
		LinkCache[Part0] = LinkCache[Part0] or {} -- Get or create map for Part0 welds.
		LinkCache[Part0][Part1] = Weld -- Add the weld to the Part0 map.
		
		LinkCache[Part1] = LinkCache[Part1] or {} -- Get or create map for Part1 welds.
		LinkCache[Part1][Part0] = Weld -- Add the weld to the Part1 map.
	end
end

local function RemoveLinkCache(Weld: WeldConstraint)
	local Part0: BasePart? = Weld.Part0
	local Part1: BasePart? = Weld.Part1
	
	if Part0 and Part1 then
		LinkCache[Part0][Part1] = nil -- Remove Part1 from Part0 map.
		LinkCache[Part1][Part0] = nil -- Remove Part0 from Part1 map.
		
		-- Cleanup any excessive space the objects are using in the WeldCache.
		if LinkCache[Part0] then -- Check Part0 is in the WeldCache.
			if not next(LinkCache[Part0]) then -- Is the WeldCache for Part0 not empty.
				LinkCache[Part0] = nil -- Set Part0 WeldCache to nil.
			end
		end
		
		if LinkCache[Part1] then -- Check Part1 is in the WeldCache.
			if not next(LinkCache[Part1]) then -- Is the WeldCache for Part1 not empty.
				LinkCache[Part1] = nil -- Set Part1 WeldCache to nil.
			end
		end
	end
end

local function AddWeld(Weld: WeldConstraint) -- Setup the weld.
	AddConnectionCache(Weld) -- Add weld to WeldConnections.
	AddLinkCache(Weld) -- Add weld to WeldCache.
end

local function RemoveWeld(Weld: WeldConstraint) -- Remove the weld.
	RemoveConnectionCache(Weld) -- Remove from ConnectionCache.
	RemoveLinkCache(Weld) -- Remove from WeldCache.
end

for _, Weld in CollectionService:GetTagged("PartWelds") do
	AddWeld(Weld)
end

CollectionService:GetInstanceAddedSignal("PartWelds"):Connect(AddWeld) -- Detect when weld is added.
CollectionService:GetInstanceRemovedSignal("PartWelds"):Connect(RemoveWeld) -- Detect when weld is removed.

local function Unweld(Object: BasePart) -- Remove welds from specified Object.
	if not LinkCache[Object] then return end -- Check Object is in WeldCache.
	
	for OtherObject, Weld in LinkCache[Object] do -- Loop through welds in the Object.
		Weld:Destroy() -- Remove the weld.
	end
end

function Module:Unweld(Object: BasePart | Model): boolean -- Remove welds from specified Object. (Usable API)
	if not Object then return true end -- Check object was passed.
	
	if Object:IsA("BasePart") then -- Check if Object is a BasePart.
		Unweld(Object) -- Break the joints of the Object.
	elseif Object.ClassName == "Model" then -- Check if Object is a Model.
		-- Remove welds from descendants in the model.
		for _, SubObject in Object:GetDescendants() do -- Loop through descendants in the model.
			if not SubObject:IsA("BasePart") then continue end -- Check the SubObject is a BasePart.
			Unweld(SubObject) -- Break the joints of the descendant.
		end
	end
	
	return true
end

function Module:GetWelded(Object: BasePart): {[BasePart]: boolean} -- Get Objects welded to the specified Object.
	local WeldedObjects: {[BasePart]: boolean} = {} -- Store welded objects.
	
	if Object:IsA("BasePart") then -- Check if Object is a BasePart.
		if LinkCache[Object] then -- Check Object is in the WeldCache.
			for OtherObject, Weld in LinkCache[Object] do -- Loop through welds for the Object.
				WeldedObjects[OtherObject] = true -- Add to the WeldedParts.
			end
		end
	elseif Object.ClassName == "Model" then -- Check if Object is a Model.
		for _, SubObject in Object:GetDescendants() do -- Loop through descendants in the model.
			if not SubObject:IsA("BasePart") then continue end -- Check the SubObject is a BasePart.
			for SubWeldedObject, _ in Module:GetWelded(SubObject) do -- Loop through the objects welded to SubObject.
				WeldedObjects[SubWeldedObject] = true -- Add to the WeldedParts.
			end
		end
	end
	
	return WeldedObjects -- Return the welded objects.
end

-- Setup the OverlapParameters for welding.
local OverlapParameters: OverlapParams = OverlapParams.new()
OverlapParameters.FilterType = Enum.RaycastFilterType.Include

local function Weld(Object: BasePart, Exclude: {BasePart}) -- Weld the object to other objects around it. Can specify a table of objects not to weld to with Exclude.	
	local IncludeTable: {BasePart} = {}
	
	for Include, _ in WeldableCache do
		if table.find(Exclude, Include) then continue end -- Skip if marked as excluded.
		table.insert(IncludeTable, Include)
	end
	
	-- Check for existing welds & ignore those objects.
	if LinkCache[Object] then
		for OtherObject, ExistingWeld in LinkCache[Object] do
			-- Remove ExistingWelds from the Include.
			IncludeTable[ExistingWeld.Part0] = nil
			IncludeTable[ExistingWeld.Part1] = nil
		end
	end
	
	OverlapParameters.FilterDescendantsInstances = IncludeTable -- Set the OverlapParameters to only check the Include.
	
	-- Welding.
	local InnerPadding: number = Module.InnerPadding -- Cache InnerPadding as a variable.
	local OuterPadding: number = Module.OuterPadding -- Cache OuterPadding as a variable.
	
	local ObjectSize: Vector3 = Object.Size
	local Sizes: {Vector3} = {
		ObjectSize + Vector3.new(OuterPadding, -InnerPadding, -InnerPadding),
		ObjectSize + Vector3.new(-InnerPadding, OuterPadding, -InnerPadding),
		ObjectSize + Vector3.new(-InnerPadding, -InnerPadding, OuterPadding),
	}
	
	local FoundObjects: {BasePart} = {}
	
	for _, Size in Sizes do -- Loop through each axis.
		local TouchingObjects: {BasePart} = WorkspaceService:GetPartBoundsInBox(Object.CFrame, Size, OverlapParameters)
		
		for _, Touching in TouchingObjects do -- Loop through each object within welding distance.
			local AnchoredWeldCheckPass: boolean = true
			
			if not Module.CanWeldAnchored then
				local ObjectAnchored: boolean = Object.Anchored
				local TouchingAnchored: boolean = Touching.Anchored
				AnchoredWeldCheckPass = not (ObjectAnchored and TouchingAnchored)
			end
			
			if AnchoredWeldCheckPass and not table.find(FoundObjects, Touching) then
				table.insert(FoundObjects, Touching) -- Do not allow checks to create multiple welds to this object.
				
				-- Create the weld.
				local NewWeld: WeldConstraint = Instance.new("WeldConstraint")
				NewWeld.Part0 = Object
				NewWeld.Part1 = Touching
				NewWeld:AddTag("PartWelds")
				NewWeld.Parent = Object
				
				NewWeld.Part1.Destroying:Connect(function()
					NewWeld:Destroy()
				end)
			end
		end
	end
end

function Module:Weld(Object: BasePart | Model, Exclude: {BasePart}): boolean -- Weld the object to other objects around it. Can specify a table of parts not to weld to with Exclude.
	local Exclude: {BasePart} = Exclude or {}
	
	-- Do not weld to objects in its own model.
	if Object.ClassName == "Model" then
		for _, Descendant in Object:GetDescendants() do
			if not Descendant:IsA("BasePart") then continue end
			table.insert(Exclude, Descendant)
		end
	elseif Object:IsA("BasePart") then
		table.insert(Exclude, Object) -- Skip checking itself.
	end
	
	if Object:IsA("BasePart") then -- Check if Object is a BasePart.
		Weld(Object, Exclude) -- Weld the Object.
	elseif Object.ClassName == "Model" then -- Check if Object is a Model.
		for _, SubObject in Object:GetDescendants() do -- Loop through descendants in the model.
			if not SubObject:IsA("BasePart") then continue end -- Check the SubObject is a BasePart & is not the PrimaryPart.
			Weld(SubObject, Exclude) -- Weld the Object.
		end
	end
	
	return true
end

return Module
