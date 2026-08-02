--[[
	职责：为服务器模块提供玩家存档载入门禁。
	输入：MarkLoading/MarkReady/Cancel 接收 player；Wait/Get 接收 player。
	输出：Wait 在载入结束后返回能否继续；Get 返回 Status、CanSave、Reason 快照。
	内部算法：每名受管玩家使用一个 BindableEvent 唤醒等待者；未受管玩家直接放行，便于隔离测试。
	不负责：DataStore、状态应用、Plot、模型或业务初始化。
]]

local PlayerDataReadyService = {}

type Record = {
	Status: string,
	CanSave: boolean,
	Reason: string?,
	Changed: BindableEvent,
}

local records: { [Player]: Record } = setmetatable({}, { __mode = "k" })

local function snapshot(record: Record?)
	if not record then
		return { Status = "Unmanaged", CanSave = false, Reason = nil }
	end
	return {
		Status = record.Status,
		CanSave = record.CanSave,
		Reason = record.Reason,
	}
end

function PlayerDataReadyService.MarkLoading(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local previous = records[player]
	if previous then
		previous.Status = "Cancelled"
		previous.Reason = "LoadRestarted"
		previous.Changed:Fire()
	end
	records[player] = {
		Status = "Loading",
		CanSave = false,
		Reason = nil,
		Changed = Instance.new("BindableEvent"),
	}
end

function PlayerDataReadyService.MarkReady(
	player: Player,
	canSave: boolean,
	reason: string?
)
	local record = records[player]
	if not record or record.Status ~= "Loading" then
		return false
	end
	record.Status = "Ready"
	record.CanSave = canSave
	record.Reason = reason
	record.Changed:Fire()
	return true
end

function PlayerDataReadyService.Cancel(player: Player, reason: string?): boolean
	local record = records[player]
	if not record or record.Status == "Cancelled" then
		return false
	end
	record.Status = "Cancelled"
	record.CanSave = false
	record.Reason = reason or "PlayerLeaving"
	record.Changed:Fire()
	return true
end

function PlayerDataReadyService.Get(player: Player)
	return snapshot(records[player])
end

function PlayerDataReadyService.Wait(player: Player): (boolean, string?)
	local record = records[player]
	if not record then
		return true, nil
	end
	while record.Status == "Loading" do
		record.Changed.Event:Wait()
	end
	if record.Status == "Cancelled" then
		return false, record.Reason
	end
	return true, record.Reason
end

return PlayerDataReadyService
