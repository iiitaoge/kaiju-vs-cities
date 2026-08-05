local SoloAttackPanelCoordinator = require(
	script.Parent.Parent.Monster.SoloAttackPanelCoordinator
)
local SoloAttackTargetSnapshotMapper = require(
	script.Parent.Parent.Monster.SoloAttackTargetSnapshotMapper
)

local SoloAttackPanelCoordinatorSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "SoloAttackPanelCoordinatorSpec: " .. message)
end

function SoloAttackPanelCoordinatorSpec.Run(): boolean
	local target = SoloAttackTargetSnapshotMapper.Map({
		AttackView = {
			CFrame = CFrame.new(10, 0, 20),
			Size = Vector3.new(100, 1, 80),
		},
		Bounds = {
			CFrame = CFrame.new(10, 0, 20),
			Size = Vector3.new(100, 1, 80),
		},
	})
	expect(target ~= nil and target.Kind == "Solo", "合法单人快照没有映射为目标")

	local requestMode = "Reject"
	local requestCount = 0
	local validationReason = nil
	local closeReason = nil
	local accepted = false
	local session = SoloAttackPanelCoordinator.Open("M1-S1", target, {
		RequestAttack = function(spawnPointId, entryPoint)
			requestCount += 1
			expect(spawnPointId == "M1-S1", "提交了错误的 SpawnPointId")
			expect(entryPoint == Vector3.new(10, 0, 20), "提交了错误的落点")
			if requestMode == "Accept" then
				return {
					Succeeded = true,
					Reason = nil,
					CommandId = 1,
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
		OnValidationFailed = function(reason)
			validationReason = reason
		end,
		OnAccepted = function()
			accepted = true
		end,
		OnClosed = function(reason)
			closeReason = reason
		end,
	})

	local outside = session.SubmitWorldPoint(Vector3.new(1_000, 0, 1_000))
	expect(not outside.Succeeded, "越界单人落点不应被接受")
	expect(outside.Reason == "EntryPointOutsideTerritory", "越界原因错误")
	expect(requestCount == 0 and session.IsOpen(), "越界不应发请求或关闭面板")

	local rejected = session.SubmitWorldPoint(Vector3.new(10, 0, 20))
	expect(not rejected.Succeeded and rejected.Reason == "MonsterBusy", "服务端拒绝结果错误")
	expect(validationReason == "MonsterBusy", "服务端拒绝没有通知 UI")
	expect(requestCount == 1 and session.IsOpen(), "服务端拒绝后应保持面板打开")

	requestMode = "Accept"
	local acceptedResult = session.SubmitWorldPoint(Vector3.new(10, 0, 20))
	expect(acceptedResult.Succeeded and accepted, "合法单人命令没有接受")
	expect(closeReason == "CommandAccepted", "接受后关闭原因错误")
	expect(requestCount == 2 and not session.IsOpen(), "接受后面板没有关闭")
	return true
end

return SoloAttackPanelCoordinatorSpec
