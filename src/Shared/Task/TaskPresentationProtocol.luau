--[[
	职责：定义任务卡片展示的 Remote 名称、请求种类和快照校验。
	输入：客户端请求 GetState；服务端发送单个任务卡片快照。
	输出：稳定的 Remote 名称、请求常量和快照合法性结果。
	内部算法：只校验跨网络所需的基本字段，不计算任务进度或奖励。
	不负责：读取玩家状态、发放奖励、选择任务或操作 UI Instance。
]]

local TaskProtocol = require(script.Parent.TaskProtocol)

local TaskPresentationProtocol = {}

TaskPresentationProtocol.RemoteName = "TaskPresentation"
TaskPresentationProtocol.QueryRemoteName = "TaskPresentationRequest"
TaskPresentationProtocol.RequestKinds = table.freeze({
	GetState = "GetState",
})

export type Snapshot = {
	Visible: boolean,
	TaskId: string?,
	Text: string?,
	Current: number?,
	Target: number?,
	RewardKind: string?,
	RewardAmount: number?,
}

local function isFiniteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

function TaskPresentationProtocol.Validate(snapshot): (boolean, string?)
	if type(snapshot) ~= "table" or type(snapshot.Visible) ~= "boolean" then
		return false, "InvalidTaskSnapshot"
	end
	if not snapshot.Visible then
		return true, nil
	end
	if type(snapshot.TaskId) ~= "string" or snapshot.TaskId == "" then
		return false, "InvalidTaskSnapshotTaskId"
	end
	if type(snapshot.Text) ~= "string" or snapshot.Text == "" then
		return false, "InvalidTaskSnapshotText"
	end
	if not isFiniteNonNegative(snapshot.Current)
		or not isFiniteNonNegative(snapshot.Target)
		or snapshot.Target <= 0
		or snapshot.Current > snapshot.Target
	then
		return false, "InvalidTaskSnapshotProgress"
	end
	if snapshot.RewardKind ~= TaskProtocol.RewardKinds.Money
		and snapshot.RewardKind ~= TaskProtocol.RewardKinds.Diamond
	then
		return false, "InvalidTaskSnapshotRewardKind"
	end
	if not isFiniteNonNegative(snapshot.RewardAmount) or snapshot.RewardAmount <= 0 then
		return false, "InvalidTaskSnapshotRewardAmount"
	end
	return true, nil
end

return table.freeze(TaskPresentationProtocol)
