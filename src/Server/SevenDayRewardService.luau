--[[
	职责：提供七日奖励的服务器领取入口。
	输入：RemoteFunction 接收 GetState / Claim；Claim 只使用服务器 os.time，不接受客户端时间、类型或数值。
	输出：奖励状态快照；成功领取时返回已发放的 Day、Type、Amount、余额和下一状态。
	内部算法：存档 Ready → 读取当前顺序档位 → 共享规则校验 24 小时冷却 → 服务端发放 Money/Diamond
	→ 更新奖励状态 → 排入立即存档。
	不负责：奖励数值配置、货币计算、具体 UI、图标或客户端倒计时。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local SevenDayRewardStateService = require(script.Parent.SevenDayRewardStateService)
local MoneyService = require(script.Parent.MoneyService)
local CurrencyProtocol = require(ReplicatedStorage.Shared.Economy.CurrencyProtocol)
local SevenDayRewardConfigs = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardConfigs
)
local SevenDayRewardProtocol = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardProtocol
)
local SevenDayRewardRules = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardRules
)

local SevenDayRewardService = {}

local activeClaims: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local function currentTime(now: number?): number
	return now or os.time()
end

local function isReady(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		-- 允许隔离测试直接调用纯服务；正式 Player 会在加载完成后进入 Ready。
		return true, nil
	end
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return false, SevenDayRewardProtocol.Reasons.PlayerDataNotReady
	end
	return true, nil
end

local function snapshot(player: Player, now: number?)
	return SevenDayRewardRules.GetState(
		SevenDayRewardStateService.Get(player),
		currentTime(now),
		SevenDayRewardConfigs
	)
end

local function failure(player: Player, reason: string, now: number?)
	return {
		Succeeded = false,
		Reason = reason,
		State = snapshot(player, now),
	}
end

local function grant(player: Player, reward)
	if reward.Type == CurrencyProtocol.Types.Money then
		return MoneyService.Add(player, reward.Amount)
	end
	if reward.Type == CurrencyProtocol.Types.Diamond then
		return DiamondService.Add(player, reward.Amount)
	end
	return nil, SevenDayRewardProtocol.Reasons.UnsupportedRewardType
end

function SevenDayRewardService.GetState(player: Player, now: number?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	return snapshot(player, now)
end

function SevenDayRewardService.Claim(player: Player, now: number?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")

	local ready, readyReason = isReady(player)
	if not ready then
		return failure(player, readyReason or "PlayerDataNotReady", now)
	end
	if activeClaims[player] then
		return failure(player, SevenDayRewardProtocol.Reasons.ActionBusy, now)
	end
	activeClaims[player] = true

	local claimTime = currentTime(now)
	local succeeded, responseOrError = xpcall(function()
		local current = SevenDayRewardStateService.Get(player)
		local claim, claimReason = SevenDayRewardRules.Claim(
			current,
			claimTime,
			SevenDayRewardConfigs
		)
		if not claim then
			return failure(player, claimReason or "RewardClaimRejected", claimTime)
		end

		local balance, grantReason = grant(player, claim.Reward)
		if balance == nil then
			return failure(
				player,
				grantReason or SevenDayRewardProtocol.Reasons.UnsupportedRewardType,
				claimTime
			)
		end

		local nextState = SevenDayRewardStateService.Set(
			player,
			claim.State.Day,
			claim.State.NextClaimAt
		)
		-- 奖励发放后立刻排入存档；普通自动保存和离服保存仍会再次捕获最新状态。
		PlayerPersistenceCoordinator.SavePlayer(player)

		return {
			Succeeded = true,
			Reason = nil,
			ClaimedDay = claim.ClaimedDay,
			Reward = claim.Reward,
			Balance = balance,
			State = SevenDayRewardRules.GetState(
				nextState,
				claimTime,
				SevenDayRewardConfigs
			),
		}
	end, debug.traceback)

	activeClaims[player] = nil
	if not succeeded then
		warn(string.format("七日奖励领取异常：%s (%s)", player.Name, tostring(responseOrError)))
		return failure(player, "RewardClaimFailed", claimTime)
	end
	return responseOrError
end

local function onRequest(player: Player, requestKind)
	local ready, readyReason = isReady(player)
	if not ready then
		return failure(player, readyReason or "PlayerDataNotReady")
	end
	if requestKind == SevenDayRewardProtocol.RequestKinds.GetState then
		return {
			Succeeded = true,
			Reason = nil,
			State = SevenDayRewardService.GetState(player),
		}
	end
	if requestKind == SevenDayRewardProtocol.RequestKinds.Claim then
		return SevenDayRewardService.Claim(player)
	end
	return failure(player, SevenDayRewardProtocol.Reasons.InvalidRequestKind)
end

function SevenDayRewardService.Start()
	if started then
		return
	end
	local valid, reason = SevenDayRewardRules.ValidateConfig(SevenDayRewardConfigs)
	assert(valid, reason or SevenDayRewardProtocol.Reasons.InvalidRewardConfig)
	started = true

	local remote = ServerRemoteAccess.EnsureFunction(SevenDayRewardProtocol.RemoteName)
	remote.OnServerInvoke = onRequest
	Players.PlayerRemoving:Connect(function(player)
		activeClaims[player] = nil
	end)
end

return SevenDayRewardService
