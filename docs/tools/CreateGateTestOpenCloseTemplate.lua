-- Run this script from Roblox Studio Command Bar.
-- Creates a temporary test furniture template:
-- ReplicatedStorage.FurnitureTemplates.Gate_Test_OpenClose
--
-- This is development-only furniture for testing room-specific OpenClose
-- permissions. The static catalog entry lives in FurnitureCatalogConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TEMPLATE_NAME = "Gate_Test_OpenClose"
local TOOL_PREFIX = "[CreateGateTestOpenCloseTemplate]"

local function getOrCreateFolder(parent, folderName)
	local folder = parent:FindFirstChild(folderName)

	if folder then
		if not folder:IsA("Folder") then
			error(TOOL_PREFIX .. " " .. folderName .. " exists but is not a Folder.")
		end

		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent

	return folder
end

local function createPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

local furnitureTemplates = getOrCreateFolder(ReplicatedStorage, "FurnitureTemplates")
local existingTemplate = furnitureTemplates:FindFirstChild(TEMPLATE_NAME)

if existingTemplate then
	existingTemplate:Destroy()
end

local model = Instance.new("Model")
model.Name = TEMPLATE_NAME
model:SetAttribute("DisplayName", "Test Gate")
model:SetAttribute("Description", "Temporary Open/Close test gate.")
model:SetAttribute("Category", "Gate")
model:SetAttribute("FootprintWidth", 1)
model:SetAttribute("FootprintDepth", 1)
model:SetAttribute("Price", 1)
model:SetAttribute("SellPrice", 0)
model:SetAttribute("CurrencyKey", "Dollars")
model:SetAttribute("TradableOnPurchase", false)
model:SetAttribute("SellableOnPurchase", false)
model:SetAttribute("SupportsOpenClose", true)
model:SetAttribute("PermissionActions", "OpenClose")
model:SetAttribute("DefaultAction", "OpenClose")
model:SetAttribute("OpenCloseTargetName", "GatePanel")
model:SetAttribute("OpenAngleDegrees", 90)
model:SetAttribute("OpenCloseAxis", "Y")
model.Parent = furnitureTemplates

local bounds = Instance.new("Part")
bounds.Name = "PlacementBounds"
bounds.Size = Vector3.new(3.6, 3.8, 3.6)
bounds.CFrame = CFrame.new(0, 1.9, 0)
bounds.Transparency = 1
bounds.Anchored = true
bounds.CanCollide = false
bounds.CanQuery = true
bounds.CanTouch = false
bounds.TopSurface = Enum.SurfaceType.Smooth
bounds.BottomSurface = Enum.SurfaceType.Smooth
bounds.Parent = model
model.PrimaryPart = bounds

local darkWood = Color3.fromRGB(94, 58, 36)
local midWood = Color3.fromRGB(147, 92, 52)
local gold = Color3.fromRGB(221, 178, 84)

createPart(
	model,
	"GatePostLeft",
	Vector3.new(0.28, 3.4, 0.28),
	CFrame.new(-1.55, 1.7, 0),
	darkWood,
	Enum.Material.Wood
)

createPart(
	model,
	"GatePostRight",
	Vector3.new(0.28, 3.4, 0.28),
	CFrame.new(1.55, 1.7, 0),
	darkWood,
	Enum.Material.Wood
)

createPart(
	model,
	"GateTopRail",
	Vector3.new(3.35, 0.22, 0.22),
	CFrame.new(0, 3.25, 0),
	darkWood,
	Enum.Material.Wood
)

local gatePanel = Instance.new("Model")
gatePanel.Name = "GatePanel"
gatePanel:SetAttribute("OpenClosePart", true)
gatePanel.Parent = model

local gatePanelSlab = createPart(
	gatePanel,
	"PanelSlab",
	Vector3.new(2.45, 2.45, 0.2),
	CFrame.new(0, 1.75, 0),
	midWood,
	Enum.Material.Wood
)
gatePanel.PrimaryPart = gatePanelSlab

createPart(
	gatePanel,
	"GateCrossBar",
	Vector3.new(2.55, 0.2, 0.24),
	CFrame.new(0, 1.75, -0.14),
	darkWood,
	Enum.Material.Wood
)

local handle = createPart(
	gatePanel,
	"GateHandle",
	Vector3.new(0.16, 0.22, 0.16),
	CFrame.new(0.9, 1.75, -0.25),
	gold,
	Enum.Material.Metal
)
handle.CanCollide = false

model:PivotTo(CFrame.new(0, 0, 0))

print(TOOL_PREFIX .. " Created ReplicatedStorage.FurnitureTemplates." .. TEMPLATE_NAME)
print(TOOL_PREFIX .. " This is temporary test furniture for room-specific OpenClose permissions.")
