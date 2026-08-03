--[[
	职责：验收怪兽管理状态机与攻击选择状态机的无 UI 组装边界。

	输入：当前客户端玩家，以及同一测试服务器中的另一名目标玩家。
	输出：管理打开、取消、目标消失、落点拒绝、服务端拒绝和接受全部通过时返回 true。
	内部算法：以注入适配器连接两个真实协调器，只伪造查询结果和攻击请求结果。

	不负责：调用 Remote、修改玩家数据、切换相机、创建 GUI 或执行真实战斗。
]]

local AttackPanelCoordinator = require(script.Parent.Parent.Monster.AttackPanelCoordinator)
local MonsterManagementCoordinator = require(
	script.Parent.Parent.Monster.MonsterManagementCoordinator
)

local MonsterManagementAttackFlowSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterManagementAttackFlowSpec: " .. message)
end

local function waitFor(predicate: () -> boolean, message: string)
	local deadline = os.clock() + 3
	repeat
		if predicate() then
			return
		end
		task.wait()
	until os.clock() >= deadline
	error("MonsterManagementAttackFlowSpec: 等待超时：" .. message)
end

local function actionStatus(allowed: boolean, reason: string?)
	return {
		Allowed = allowed,
		Reason = reason,
		Cost = 0,
		Affordable = true,
		TargetLevel = nil,
	}
end

-- 输入：同服的本地玩家和另一名玩家。
-- 输出：完整无 UI 管理→选择→提交流程通过时返回 true。
-- 内部算法：管理 Effect 打开真实攻击面板协调器；面板回调再把结果送回管理状态机。
function MonsterManagementAttackFlowSpec.Run(localPlayer: Player, targetPlayer: Player): boolean
	expect(localPlayer ~= targetPlayer, "目标玩家不能是本地玩家")
	expect(localPlayer.Parent ~= nil and targetPlayer.Parent ~= nil, "两名玩家必须在线")

	local spawnPointId = "M1-S1"
	local snapshot = {
		SpawnPointId = spawnPointId,
		Built = true,
		Level = 1,
		MonsterKey = "Godzilla-L001",
		MonsterState = "IdleAtSpawn",
		Balance = 0,
		Upgrade = actionStatus(false, "MaxLevel"),
		Attack = actionStatus(true, nil),
	}
	local target = {
		Player = targetPlayer,
		UnlockedTerritories = {
			{
				ZoneId = "TestZone",
				BoundsId = "TestBounds",
				CFrame = CFrame.new(0, 0, 0),
				Size = Vector3.new(40, 10, 40),
			},
		},
		AttackView = {
			CFrame = CFrame.new(0, 0, 0),
			Size = Vector3.new(40, 10, 40),
		},
	}

	local modes = {}
	local targetsAvailable = true
	local requestMode = "Reject"
	local requestCount = 0
	local lastValidationReason = nil
	local activeAttackSession = nil

	local management = MonsterManagementCoordinator.Create({
		Render = function(state)
			table.insert(modes, state.Mode)
		end,
		Query = function(requestedSpawnPointId)
			expect(requestedSpawnPointId == spawnPointId, "管理查询出生点错误")
			return {
				Succeeded = true,
				Reason = nil,
				Snapshot = snapshot,
			}
		end,
		Upgrade = function()
			error("本验收不应请求升级")
		end,
		OpenAttackSelection = function(requestedSpawnPointId, callbacks)
			expect(requestedSpawnPointId == spawnPointId, "攻击选择出生点错误")
			local session
			session = AttackPanelCoordinator.Open(requestedSpawnPointId, {
				LocalPlayer = localPlayer,
				GetTargets = function()
					return if targetsAvailable then { target } else {}
				end,
				RequestAttack = function(_, requestedTargetPlayer, entryPoint)
					requestCount += 1
					expect(requestedTargetPlayer == targetPlayer, "提交了错误的目标玩家")
					expect(entryPoint == Vector3.zero, "提交了错误的进攻落点")
					if requestMode == "Accept" then
						return {
							Succeeded = true,
							Reason = nil,
							CommandId = 11,
							Monster = nil,
						}
					end
					return {
						Succeeded = false,
						Reason = "MonsterBusy",
						CommandId = nil,
						Monster = nil,
					}
				end,
				OnTargetChanged = function(changedTarget)
					expect(changedTarget == target, "目标切换回调错误")
				end,
				OnTargetUnavailable = function()
					callbacks.OnUnavailable("TargetUnavailable")
				end,
				OnValidationFailed = function(reason)
					lastValidationReason = reason
				end,
				OnAccepted = function()
					callbacks.OnAccepted()
				end,
				OnClosed = function(reason)
					if reason == "Cancelled" then
						callbacks.OnCancelled()
					end
				end,
			})
			activeAttackSession = session
			return session
		end,
	})

	local opened = management.Open(spawnPointId)
	expect(opened.Accepted and opened.State.Mode == "Loading", "管理面板没有进入 Loading")
	waitFor(function()
		return management.GetState().Mode == "Managing"
	end, "管理快照加载")

	local choosing = management.ChooseAttack()
	expect(choosing.Accepted, "无法进入攻击选择")
	expect(management.GetState().Mode == "SelectingAttack", "管理状态未进入 SelectingAttack")
	expect(activeAttackSession and activeAttackSession.IsOpen(), "攻击选择会话没有打开")
	expect(not management.ChooseAttack().Accepted, "同一管理会话重复打开了攻击选择")

	activeAttackSession.Cancel()
	expect(management.GetState().Mode == "Managing", "取消后管理状态没有恢复")
	expect(not activeAttackSession.IsOpen(), "取消后攻击选择仍打开")
	expect(requestCount == 0, "取消不应发送攻击请求")

	management.ChooseAttack()
	expect(activeAttackSession and activeAttackSession.IsOpen(), "第二次攻击选择没有打开")
	targetsAvailable = false
	activeAttackSession.RefreshTargets()
	expect(management.GetState().Mode == "Managing", "目标消失后管理状态没有恢复")
	expect(not activeAttackSession.IsOpen(), "目标消失后攻击选择会话没有关闭")
	expect(management.GetState().LastReason == "TargetUnavailable", "目标消失原因没有保留")

	targetsAvailable = true
	management.ChooseAttack()
	expect(activeAttackSession and activeAttackSession.IsOpen(), "第三次攻击选择没有打开")
	local outside = activeAttackSession.SubmitWorldPoint(Vector3.new(1000, 0, 1000))
	expect(not outside.Succeeded and outside.Reason == "EntryPointOutsideTerritory", "越界落点未被本地拒绝")
	expect(lastValidationReason == "EntryPointOutsideTerritory", "越界原因没有通知适配层")
	expect(management.GetState().Mode == "SelectingAttack", "越界后不应退出攻击选择")
	expect(activeAttackSession.IsOpen(), "越界后攻击选择不应关闭")
	expect(requestCount == 0, "越界落点不应发送攻击请求")

	requestMode = "Reject"
	local rejected = activeAttackSession.SubmitWorldPoint(Vector3.zero)
	expect(not rejected.Succeeded and rejected.Reason == "MonsterBusy", "服务端拒绝结果错误")
	expect(lastValidationReason == "MonsterBusy", "服务端拒绝原因没有通知适配层")
	expect(management.GetState().Mode == "SelectingAttack", "服务端拒绝后不应退出攻击选择")
	expect(activeAttackSession.IsOpen(), "服务端拒绝后攻击选择不应关闭")
	expect(requestCount == 1, "服务端拒绝请求次数错误")

	requestMode = "Accept"
	local accepted = activeAttackSession.SubmitWorldPoint(Vector3.zero)
	expect(accepted.Succeeded and accepted.CommandId == 11, "接受结果没有返回命令 ID")
	expect(management.GetState().Mode == "Closed", "接受攻击后管理面板没有关闭")
	expect(not activeAttackSession.IsOpen(), "接受攻击后攻击选择没有关闭")
	expect(requestCount == 2, "完整流程请求次数错误")

	expect(modes[1] == "Closed", "协调器初始状态不是 Closed")
	expect(table.find(modes, "Loading") ~= nil, "流程缺少 Loading")
	expect(table.find(modes, "Managing") ~= nil, "流程缺少 Managing")
	expect(table.find(modes, "SelectingAttack") ~= nil, "流程缺少 SelectingAttack")
	expect(modes[#modes] == "Closed", "流程没有以 Closed 结束")
	return true
end

return MonsterManagementAttackFlowSpec
