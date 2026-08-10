--[[
	职责：同步 Plot 上方 PlayerInfo 世界 UI 的头像和玩家名字。

	场景合同：
	- Plot/PlayerInfo (BasePart)
		- Attachment/ BillboardGui/ Panel
			- Player/Icon (ImageLabel)
			- Name (TextLabel)

	输入：Refresh 接收一个 Plot Model，并读取其 OwnerUserId Attribute。
	输出：成功时把当前玩家头像和 Name 写入 PlayerInfo；未占用 Plot 隐藏 BillboardGui。
	内部算法：按 OwnerUserId 找到当前在线 Player；头像使用 Roblox rbxthumb 资源，
	名字使用 Player.Name；找不到玩家或场景控件时返回稳定失败原因。
	不负责：分配/释放 Plot、修改 OwnerUserId、创建 Plot 或处理玩家存档。
]]

local Players = game:GetService("Players")

local PlayerPlotInfoService = {}

local OWNER_ATTRIBUTE = "OwnerUserId"

export type References = {
	BillboardGui: BillboardGui,
	Icon: ImageLabel,
	NameLabel: TextLabel,
}

local function isValidOwnerUserId(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
		and value ~= 0
end

local function getReferences(plot: Model): (References?, string?)
	local playerInfo = plot:FindFirstChild("PlayerInfo")
	if not playerInfo or not playerInfo:IsA("BasePart") then
		return nil, "PlayerInfoUnavailable"
	end

	local attachment = playerInfo:FindFirstChild("Attachment")
	if not attachment or not attachment:IsA("Attachment") then
		return nil, "PlayerInfoAttachmentUnavailable"
	end

	local billboardGui = attachment:FindFirstChild("BillboardGui")
	if not billboardGui or not billboardGui:IsA("BillboardGui") then
		return nil, "PlayerInfoBillboardUnavailable"
	end

	local panel = billboardGui:FindFirstChild("Panel")
	if not panel or not panel:IsA("Frame") then
		return nil, "PlayerInfoPanelUnavailable"
	end

	local playerFrame = panel:FindFirstChild("Player")
	if not playerFrame or not playerFrame:IsA("Frame") then
		return nil, "PlayerInfoPlayerFrameUnavailable"
	end

	local icon = playerFrame:FindFirstChild("Icon")
	if not icon or not icon:IsA("ImageLabel") then
		return nil, "PlayerInfoIconUnavailable"
	end

	local nameLabel = panel:FindFirstChild("Name")
	if not nameLabel or not nameLabel:IsA("TextLabel") then
		return nil, "PlayerInfoNameUnavailable"
	end

	return {
		BillboardGui = billboardGui,
		Icon = icon,
		NameLabel = nameLabel,
	}, nil
end

local function clear(references: References)
	references.BillboardGui.Enabled = false
	references.Icon.Image = ""
	references.NameLabel.Text = ""
end

local function avatarImage(userId: number): string
	return string.format(
		"rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420",
		userId
	)
end

function PlayerPlotInfoService.Refresh(plot: Model): (boolean, string?)
	assert(typeof(plot) == "Instance" and plot:IsA("Model"), "plot 必须是 Model")

	local references, referenceReason = getReferences(plot)
	if not references then
		return false, referenceReason
	end

	local ownerUserId = plot:GetAttribute(OWNER_ATTRIBUTE)
	if not isValidOwnerUserId(ownerUserId) then
		clear(references :: References)
		return true, nil
	end

	local player = Players:GetPlayerByUserId(ownerUserId)
	if not player then
		clear(references :: References)
		return true, nil
	end

	local resolved = references :: References
	resolved.Icon.Image = avatarImage(player.UserId)
	resolved.NameLabel.Text = player.Name
	resolved.BillboardGui.Enabled = true
	return true, nil
end

return PlayerPlotInfoService
