--[[
	职责：把一次玩家怪兽攻击中的决斗诊断事件输出为单行结构化日志。
	输入：稳定事件名和只包含可 JSON 编码值的字段表。
	输出：服务器控制台中的 [MonsterCombatTrace] JSON；无业务返回值。
	不负责：改变状态、伤害、计时、移动、恢复或回程。
]]

local HttpService = game:GetService("HttpService")

local MonsterCombatDiagnosticLog = {}

function MonsterCombatDiagnosticLog.Emit(eventName: string, fields)
	if type(eventName) ~= "string" or eventName == "" or type(fields) ~= "table" then
		warn("[MonsterCombatTrace] DiagnosticLogInputInvalid")
		return
	end

	local payload = table.clone(fields)
	payload.Event = eventName
	payload.ServerTime = workspace:GetServerTimeNow()
	local encoded, value = pcall(HttpService.JSONEncode, HttpService, payload)
	if not encoded then
		warn("[MonsterCombatTrace] DiagnosticLogEncodeFailed: " .. tostring(value))
		return
	end
	print("[MonsterCombatTrace] " .. value)
end

return table.freeze(MonsterCombatDiagnosticLog)
