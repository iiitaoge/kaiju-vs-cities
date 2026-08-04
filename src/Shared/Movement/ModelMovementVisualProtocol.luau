--[[
	职责：定义服务器权威模型移动表现命令，并在网络边界验证命令外形。
	输入：任意 command。
	输出：是否合法及稳定失败原因。
	内部算法：无外部依赖地验证公共身份、有限 CFrame，以及 Move/Cancel/Snap 专有字段。
	不负责：创建 Remote、插值模型、决定移动路径或保存客户端状态。
]]

local ModelMovementVisualProtocol = {}

ModelMovementVisualProtocol.RemoteName = "ModelMovementVisual"
ModelMovementVisualProtocol.Kinds = table.freeze({
	Move = "Move",
	Cancel = "Cancel",
	Snap = "Snap",
})

export type MoveCommand = {
	Kind: "Move",
	Model: Model,
	RequestId: number,
	StartCFrame: CFrame,
	TargetCFrame: CFrame,
	StartedAt: number,
	Duration: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
}

export type TerminalCommand = {
	Kind: "Cancel" | "Snap",
	Model: Model,
	RequestId: number,
	TargetCFrame: CFrame,
}

export type Command = MoveCommand | TerminalCommand

local function isFiniteNumber(value): boolean
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function isPositiveInteger(value): boolean
	return isFiniteNumber(value) and value >= 1 and value % 1 == 0
end

local function isFiniteCFrame(value): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { value:GetComponents() } do
		if not isFiniteNumber(component) then
			return false
		end
	end
	return true
end

function ModelMovementVisualProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if typeof(command.Model) ~= "Instance" or not command.Model:IsA("Model") then
		return false, "InvalidModel"
	end
	if not isPositiveInteger(command.RequestId) then
		return false, "InvalidRequestId"
	end
	if not isFiniteCFrame(command.TargetCFrame) then
		return false, "InvalidTargetCFrame"
	end

	if command.Kind == ModelMovementVisualProtocol.Kinds.Cancel
		or command.Kind == ModelMovementVisualProtocol.Kinds.Snap then
		return true, nil
	end
	if command.Kind ~= ModelMovementVisualProtocol.Kinds.Move then
		return false, "InvalidKind"
	end
	if not isFiniteCFrame(command.StartCFrame) then
		return false, "InvalidStartCFrame"
	end
	if not isFiniteNumber(command.StartedAt) then
		return false, "InvalidStartedAt"
	end
	if not isFiniteNumber(command.Duration) or command.Duration <= 0 then
		return false, "InvalidDuration"
	end
	if typeof(command.EasingStyle) ~= "EnumItem"
		or command.EasingStyle.EnumType ~= Enum.EasingStyle then
		return false, "InvalidEasingStyle"
	end
	if typeof(command.EasingDirection) ~= "EnumItem"
		or command.EasingDirection.EnumType ~= Enum.EasingDirection then
		return false, "InvalidEasingDirection"
	end
	return true, nil
end

return table.freeze(ModelMovementVisualProtocol)
