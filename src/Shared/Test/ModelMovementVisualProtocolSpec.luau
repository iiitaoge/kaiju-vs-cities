local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(
	ReplicatedStorage.Shared.Movement.ModelMovementVisualProtocol
)

local ModelMovementVisualProtocolSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "ModelMovementVisualProtocolSpec: " .. message)
end

local function validMove(model: Model)
	return {
		Kind = Protocol.Kinds.Move,
		Model = model,
		RequestId = 1,
		StartCFrame = CFrame.new(1, 2, 3),
		TargetCFrame = CFrame.new(4, 5, 6),
		StartedAt = 10,
		Duration = 2,
		EasingStyle = Enum.EasingStyle.Linear,
		EasingDirection = Enum.EasingDirection.InOut,
	}
end

-- 输入：三类有效命令，以及缺字段、错误类型和数值边界。
-- 输出：协议只接受可安全执行的 Move/Cancel/Snap 命令时返回 true。
-- 内部算法：从有效命令逐字段制造错误，核对稳定失败原因和冻结约束。
function ModelMovementVisualProtocolSpec.Run(): boolean
	local model = Instance.new("Model")

	local move = validMove(model)
	local moveValid, moveReason = Protocol.Validate(move)
	expect(moveValid and moveReason == nil, "有效 Move 命令被拒绝")

	for _, kind in { Protocol.Kinds.Cancel, Protocol.Kinds.Snap } do
		local valid, reason = Protocol.Validate({
			Kind = kind,
			Model = model,
			RequestId = 2,
			TargetCFrame = CFrame.new(7, 8, 9),
		})
		expect(valid and reason == nil, "有效 " .. kind .. " 命令被拒绝")
	end

	local invalidRequest = validMove(model)
	invalidRequest.RequestId = 1.5
	local valid, reason = Protocol.Validate(invalidRequest)
	expect(not valid and reason == "InvalidRequestId", "非整数请求编号未被拒绝")

	local missingKind = validMove(model)
	missingKind.Kind = nil
	valid, reason = Protocol.Validate(missingKind)
	expect(not valid and reason == "InvalidKind", "无 Kind 的旧命令外形未被拒绝")

	local invalidDuration = validMove(model)
	invalidDuration.Duration = 0
	valid, reason = Protocol.Validate(invalidDuration)
	expect(not valid and reason == "InvalidDuration", "零时长 Move 未被拒绝")

	local invalidTarget = validMove(model)
	invalidTarget.TargetCFrame = CFrame.new(0 / 0, 0, 0)
	valid, reason = Protocol.Validate(invalidTarget)
	expect(not valid and reason == "InvalidTargetCFrame", "含 NaN 的目标 CFrame 未被拒绝")

	local invalidEasing = validMove(model)
	invalidEasing.EasingStyle = Enum.EasingDirection.In
	valid, reason = Protocol.Validate(invalidEasing)
	expect(not valid and reason == "InvalidEasingStyle", "错误缓动枚举未被拒绝")

	expect(table.isfrozen(Protocol), "协议表必须只读")
	expect(table.isfrozen(Protocol.Kinds), "Kind 表必须只读")
	expect(not pcall(function()
		Protocol.RemoteName = "Changed"
	end), "协议接受了运行时改写")

	model:Destroy()
	return true
end

return ModelMovementVisualProtocolSpec
