--[[
	职责：提供群组奖励的服务器领取入口。
	输入：RemoteFunction 接收 GetState / Claim；Claim 不接受客户端的玩家 ID、群组 ID、
	奖励类型或奖励数值。
	输出：群组成员状态、领取状态；成功领取时返回本次奖励和当前状态。
	内部算法：存档 Ready → 服务端 IsInGroupAsync 校验 → RewardId 幂等校验 → 先完成全部
	奖励项发放 → 写入领取标记 → 排入立即存档。当前类型分别复用 MoneyService/DiamondService。
	不负责：群组页面、加入提示、面板 UI、奖励配置内容或未来资产的具体实现。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local GroupRewardStateService = require(script.Parent.GroupRewardStateService)
local MoneyService = require(script.Parent.MoneyService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local GroupRewardConfigs = require(ReplicatedStorage.Shared.Reward.GroupRewardConfigs)
local GroupRewardProtocol = require(ReplicatedStorage.Shared.Reward.GroupRewardProtocol)
local GroupRewardRules = require(ReplicatedStorage.Shared.Reward.GroupRewardRules)

local GroupRewardService = {}

local activeClaims: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local function isReady(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		-- 允许隔离测试直接调用纯服务；正式 Player 会在加载完成后进入 Ready。
		return true, nil
	end
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return false, GroupRewardProtocol.Reasons.PlayerDataNotReady
	end
	return true, nil
end

local function checkMembership(player: Player): (boolean?, string?)
	local succeeded, result = pcall(function()
		return player:IsInGroupAsync(GroupRewardConfigs.GroupId)
	end)
	if not succeeded then
		return nil, GroupRewardProtocol.Reasons.GroupCheckFailed
	end
	return result == true, nil
end

local function stateFor(player: Player): (any?, string?)
	local isMember, membershipReason = checkMembership(player)
	if isMember == nil then
		return nil, membershipReason
	end

	return GroupRewardRules.GetState(
		isMember,
		GroupRewardStateService.IsClaimed(player, GroupRewardConfigs.RewardId),
		GroupRewardConfigs
	), nil
end

local function failure(player: Player, reason: string)
	local state, stateReason = stateFor(player)
	return {
		Succeeded = false,
		Reason = reason or stateReason,
		State = state,
	}
end

local function grantRewards(player: Player): ({ [string]: number }?, string?)
	for _, reward in GroupRewardConfigs.Rewards do
		if reward.Type ~= GroupRewardProtocol.Types.Money
			and reward.Type ~= GroupRewardProtocol.Types.Diamond
		then
			return nil, GroupRewardProtocol.Reasons.UnsupportedRewardType
		end
	end

	for _, reward in GroupRewardConfigs.Rewards do
		if reward.Type == GroupRewardProtocol.Types.Money then
			MoneyService.Add(player, reward.Amount)
		elseif reward.Type == GroupRewardProtocol.Types.Diamond then
			DiamondService.Add(player, reward.Amount)
		end
	end

	return {
		Money = MoneyService.Get(player),
		Diamond = DiamondService.Get(player),
	}, nil
end

function GroupRewardService.GetState(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	return stateFor(player)
end

function GroupRewardService.Claim(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")

	local ready, readyReason = isReady(player)
	if not ready then
		return failure(player, readyReason or GroupRewardProtocol.Reasons.PlayerDataNotReady)
	end
	if activeClaims[player] then
		return failure(player, GroupRewardProtocol.Reasons.ActionBusy)
	end
	activeClaims[player] = true

	local succeeded, responseOrError = xpcall(function()
		local isMember, membershipReason = checkMembership(player)
		if isMember == nil then
			return failure(player, membershipReason or GroupRewardProtocol.Reasons.GroupCheckFailed)
		end

		local claimed = GroupRewardStateService.IsClaimed(
			player,
			GroupRewardConfigs.RewardId
		)
		local canClaim, claimReason = GroupRewardRules.CanClaim(isMember, claimed)
		if not canClaim then
			return {
				Succeeded = false,
				Reason = claimReason,
				State = GroupRewardRules.GetState(isMember, claimed, GroupRewardConfigs),
			}
		end

		local balances, grantReason = grantRewards(player)
		if not balances then
			return failure(player, grantReason or GroupRewardProtocol.Reasons.RewardGrantFailed)
		end

		GroupRewardStateService.SetClaimed(
			player,
			GroupRewardConfigs.RewardId,
			true
		)
		local queued, saveReason = PlayerPersistenceCoordinator.SavePlayer(player)
		if not queued then
			warn(string.format(
				"群组奖励已发放但立即存档未入队：%s (%s)",
				player.Name,
				tostring(saveReason)
			))
		end

		return {
			Succeeded = true,
			Reason = nil,
			RewardId = GroupRewardConfigs.RewardId,
			Rewards = GroupRewardConfigs.Rewards,
			Balances = balances,
			State = GroupRewardRules.GetState(true, true, GroupRewardConfigs),
		}
	end, debug.traceback)

	activeClaims[player] = nil
	if not succeeded then
		warn(string.format("群组奖励领取异常：%s (%s)", player.Name, tostring(responseOrError)))
		return failure(player, GroupRewardProtocol.Reasons.RewardGrantFailed)
	end
	return responseOrError
end

local function onRequest(player: Player, requestKind)
	local ready, readyReason = isReady(player)
	if not ready then
		return failure(player, readyReason or GroupRewardProtocol.Reasons.PlayerDataNotReady)
	end

	if requestKind == GroupRewardProtocol.RequestKinds.GetState then
		local state, stateReason = GroupRewardService.GetState(player)
		return {
			Succeeded = state ~= nil,
			Reason = stateReason,
			State = state,
		}
	end
	if requestKind == GroupRewardProtocol.RequestKinds.Claim then
		return GroupRewardService.Claim(player)
	end
	return failure(player, GroupRewardProtocol.Reasons.InvalidRequestKind)
end

function GroupRewardService.Start()
	if started then
		return
	end

	local valid, reason = GroupRewardRules.ValidateConfig(GroupRewardConfigs)
	assert(valid, reason or GroupRewardProtocol.Reasons.InvalidRewardConfig)
	started = true

	local remote = ServerRemoteAccess.EnsureFunction(GroupRewardProtocol.RemoteName)
	remote.OnServerInvoke = onRequest
	Players.PlayerRemoving:Connect(function(player)
		activeClaims[player] = nil
	end)
end

return GroupRewardService
