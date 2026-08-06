--[[
	职责：维护每只进攻怪兽当前锁定的房屋，并把集火数量镜像到运行时房屋 Model。
	输入：Begin/End/EndHouse；身份来自服务器权威怪兽、Player 和 HouseId。
	输出：GetActiveCount；房屋 Attribute BuildingActiveAttackCount。
	内部算法：一只怪兽至多拥有一个目标，会话跨越同一房屋的连续多次命中，切换或结束时原子迁移计数。
	不负责：房屋选择、攻击凭证、伤害、动画或客户端 UI。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerBuildingRuntimeRegistry = require(script.Parent.PlayerBuildingRuntimeRegistry)
local CombatHealthBarProtocol = require(
	ReplicatedStorage.Shared.UI.CombatHealthBarProtocol
)

local HouseAttackActivityService = {}

type Activity = {
	Defender: Player,
	HouseId: string,
}

local activitiesByMonster: { [Model]: Activity } = setmetatable({}, { __mode = "k" })
local destroyingConnections: { [Model]: RBXScriptConnection } = setmetatable({}, { __mode = "k" })
local countsByDefender: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })

local function writeCount(defender: Player, houseId: string, count: number)
	local model = PlayerBuildingRuntimeRegistry.Get(defender, houseId)
	if model then
		model:SetAttribute(
			CombatHealthBarProtocol.HouseActiveAttackCountAttributeName,
			count
		)
	end
end

local function setCount(defender: Player, houseId: string, count: number)
	assert(count >= 0 and count % 1 == 0, "活动攻击数量必须是非负整数")
	local counts = countsByDefender[defender]
	if count == 0 then
		if counts then
			counts[houseId] = nil
			if next(counts) == nil then
				countsByDefender[defender] = nil
			end
		end
	else
		if not counts then
			counts = {}
			countsByDefender[defender] = counts
		end
		counts[houseId] = count
	end
	writeCount(defender, houseId, count)
end

function HouseAttackActivityService.GetActiveCount(defender: Player, houseId: string): number
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	local counts = countsByDefender[defender]
	return if counts then counts[houseId] or 0 else 0
end

function HouseAttackActivityService.End(monster: Model): boolean
	assert(monster:IsA("Model"), "monster 必须是 Model")
	local activity = activitiesByMonster[monster]
	if not activity then
		return false
	end
	activitiesByMonster[monster] = nil

	local connection = destroyingConnections[monster]
	destroyingConnections[monster] = nil
	if connection then
		connection:Disconnect()
	end

	local count = HouseAttackActivityService.GetActiveCount(
		activity.Defender,
		activity.HouseId
	)
	setCount(activity.Defender, activity.HouseId, math.max(0, count - 1))
	return true
end

function HouseAttackActivityService.Begin(
	monster: Model,
	defender: Player,
	houseId: string
): boolean
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")

	local current = activitiesByMonster[monster]
	if current and current.Defender == defender and current.HouseId == houseId then
		return false
	end
	if current then
		HouseAttackActivityService.End(monster)
	end

	activitiesByMonster[monster] = {
		Defender = defender,
		HouseId = houseId,
	}
	setCount(
		defender,
		houseId,
		HouseAttackActivityService.GetActiveCount(defender, houseId) + 1
	)
	destroyingConnections[monster] = monster.Destroying:Connect(function()
		HouseAttackActivityService.End(monster)
	end)
	return true
end

function HouseAttackActivityService.EndHouse(defender: Player, houseId: string): number
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	local ended = 0
	for monster, activity in activitiesByMonster do
		if activity.Defender == defender and activity.HouseId == houseId then
			if HouseAttackActivityService.End(monster) then
				ended += 1
			end
		end
	end
	setCount(defender, houseId, 0)
	return ended
end

return HouseAttackActivityService
