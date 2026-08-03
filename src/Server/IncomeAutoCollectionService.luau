--[[
	职责：为已开启 AutoIncome 的在线玩家周期领取区域收入。
	输入：Start 无参数。
	输出：无；收入通过 HouseIncomeService 进入 MoneyService。
	内部算法：等待数据 Ready → 固定周期遍历产钱区域 → 领取已建造且启用自动收入的区域。
	不负责：收入公式、按钮、Boost 购买、建筑或存档。
]]

local Players = game:GetService("Players")

local HouseIncomeService = require(script.Parent.HouseIncomeService)
local IncomeAutoCollectionConfigs = require(script.Parent.IncomeAutoCollectionConfigs)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerRegionTransactionLock = require(script.Parent.PlayerRegionTransactionLock)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionStateService = require(script.Parent.RegionStateService)

local IncomeAutoCollectionService = {}

local running: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local function run(player: Player)
	if running[player] then
		return
	end
	running[player] = true
	task.spawn(function()
		local ready = PlayerDataReadyService.Wait(player)
		while ready and player.Parent == Players do
			task.wait(IncomeAutoCollectionConfigs.IntervalSeconds)
			if player.Parent ~= Players then
				break
			end
			for regionId in RegionEconomyConfigs do
				local state = RegionStateService.Get(player, regionId)
				if state.Unlocked and state.Level >= 1 and state.AutoIncome then
					local release = PlayerRegionTransactionLock.TryAcquire(player, regionId)
					if release then
						local succeeded, outcome = xpcall(function()
							return HouseIncomeService.CollectRegion(player, regionId, os.time())
						end, debug.traceback)
						release()
						if not succeeded then
							warn(string.format(
								"自动收入异常：%s/%s (%s)",
								player.Name,
								regionId,
								tostring(outcome)
							))
						end
					end
				end
			end
		end
		running[player] = nil
	end)
end

function IncomeAutoCollectionService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(run)
	for _, player in Players:GetPlayers() do
		run(player)
	end
end

return IncomeAutoCollectionService
