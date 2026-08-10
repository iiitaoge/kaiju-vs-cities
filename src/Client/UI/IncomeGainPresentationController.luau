--[[
	职责：协调本地房屋接触反馈，以及服务器已确认收入的金额飘字。
	输入：Start；PlayTouchContact 接收自有运行时房屋；RemoteEvent 接收 Automatic 或 Touch Command。
	输出：本地接触立即同时播放房屋弹跳和五枚飞钱；服务器正数收入在对应房屋播放准确金额飘字。
	内部算法：解析 HUD.UpData.Money.Icon → 本地接触路由两种表现；网络命令验证后按 HouseId 路由飘字。
	不负责：计算、结算或修改余额，不监听余额变化，也不处理其他收入来源。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IncomeGainPresentationProtocol = require(
	ReplicatedStorage.Shared.Economy.IncomeGainPresentationProtocol
)
local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)
local RuntimeBuildingIdentity = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity
)
local LocalPlayerCityRuntimeAccess = require(
	script.Parent.Parent.Building.LocalPlayerCityRuntimeAccess
)
local HouseContactPresentationConfigs = require(
	script.Parent.Parent.Building.HouseContactPresentationConfigs
)
local LocalBuildingEffectPlayer = require(
	script.Parent.Parent.Building.LocalBuildingEffectPlayer
)
local IncomeGainEffectConfigs = require(script.Parent.IncomeGainEffectConfigs)
local LocalIncomeGainEffectPlayer = require(script.Parent.LocalIncomeGainEffectPlayer)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)

local IncomeGainPresentationController = {}

type ImageGui = LocalIncomeGainEffectPlayer.ImageGui

type References = {
	MoneyIcon: ImageGui,
	Overlay: ScreenGui,
	OverlayVisibility: LocalUIVisibilityGate.Handle,
}

local localPlayer = Players.LocalPlayer
local activeReferences: References? = nil
local started = false

local function resolveReferences(playerGui: PlayerGui): (References?, string?)
	local hud = playerGui:FindFirstChild("HUD")
	local upData = hud and hud:FindFirstChild("UpData")
	local money = upData and upData:FindFirstChild("Money")
	local icon = money and money:FindFirstChild("Icon")
	if not hud or not hud:IsA("ScreenGui") then
		return nil, "HUDUnavailable"
	end
	if not upData or not upData:IsA("GuiObject") then
		return nil, "UpDataUnavailable"
	end
	if not money or not money:IsA("GuiObject") then
		return nil, "MoneyUnavailable"
	end
	if not icon or not icon:IsA("ImageLabel") then
		return nil, "MoneyIconUnavailable"
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "LocalIncomeGainEffects"
	overlay.DisplayOrder = hud.DisplayOrder + 1
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.Parent = playerGui
	local overlayVisibility = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(visible)
			overlay.Enabled = visible
			if not visible then
				for _, child in overlay:GetChildren() do
					if child:IsA("GuiObject") then
						child.Visible = false
					end
				end
			end
		end,
		true
	)

	return {
		MoneyIcon = icon,
		Overlay = overlay,
		OverlayVisibility = overlayVisibility,
	}, nil
end

local function resolveBuilding(houseId: string): Model?
	local plot = LocalPlayerCityRuntimeAccess.FindPlot(localPlayer.UserId)
	if not plot then
		return nil
	end
	local model = LocalPlayerCityRuntimeAccess.FindBuilding(plot, houseId)
	if not model then
		return nil
	end
	local identity = RuntimeBuildingIdentity.Read(model)
	if not identity
		or identity.OwnerUserId ~= localPlayer.UserId
		or identity.HouseId ~= houseId
	then
		return nil
	end
	return model
end

local function present(command, references: References)
	for _, entry in command.Entries do
		local model = resolveBuilding(entry.HouseId)
		if model then
			LocalIncomeGainEffectPlayer.PlayPopup(
				model,
				references.MoneyIcon,
				"+" .. CompactNumberFormatter.Format(entry.Amount),
				IncomeGainEffectConfigs
			)
		end
	end
end

-- 输入：本地触碰控制器已经确认接触的自有运行时房屋。
-- 输出：房屋弹跳一定开始调度；HUD 已就绪时同时开始五枚固定像素飞钱。
function IncomeGainPresentationController.PlayTouchContact(model: Model): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	SoundController.Play("CollcetMoney")
	task.spawn(
		LocalBuildingEffectPlayer.PlayContact,
		model,
		HouseContactPresentationConfigs
	)

	local references = activeReferences
	if not references then
		return false
	end
	return LocalIncomeGainEffectPlayer.PlayTouchFlight(
		model,
		references.MoneyIcon,
		references.MoneyIcon,
		references.Overlay,
		IncomeGainEffectConfigs
	)
end

function IncomeGainPresentationController.Start()
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	if not playerGui:WaitForChild("HUD", 10) then
		warn("房屋收入表现等待 HUD 超时")
		return
	end
	local references, reason = resolveReferences(playerGui)
	if not references then
		warn("房屋收入表现 HUD 路径无效：" .. tostring(reason))
		return
	end
	activeReferences = references

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild(IncomeGainPresentationProtocol.RemoteName)
	assert(
		remote:IsA("RemoteEvent"),
		IncomeGainPresentationProtocol.RemoteName .. " 必须是 RemoteEvent"
	)
	remote.OnClientEvent:Connect(function(command)
		local valid, validationReason = IncomeGainPresentationProtocol.Validate(command)
		if not valid then
			warn("拒绝房屋收入表现命令：" .. (validationReason or "Unknown"))
			return
		end
		task.spawn(present, command, references)
	end)
end

return IncomeGainPresentationController
