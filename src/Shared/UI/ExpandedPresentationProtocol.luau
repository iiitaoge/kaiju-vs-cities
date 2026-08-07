--[[
	职责：定义区域扩展与怪兽培养罐建造完成的客户端提示合同。
	输入：服务器发送的区域身份或培养罐出生点身份。
	输出：合法性结果、稳定 Kind 和 Remote 名称。
	不负责：判断业务是否成功、拼接英文文案、显示 UI 或控制显示时长。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local ExpandedPresentationProtocol = {}

ExpandedPresentationProtocol.RemoteName = "ExpandedPresentation"
ExpandedPresentationProtocol.Kinds = table.freeze({
	RegionExpanded = "RegionExpanded",
	IncubatorBuilt = "IncubatorBuilt",
})

export type RegionExpandedCommand = {
	Kind: "RegionExpanded",
	RegionId: string,
}

export type IncubatorBuiltCommand = {
	Kind: "IncubatorBuilt",
	SpawnPointId: string,
}

export type Command = RegionExpandedCommand | IncubatorBuiltCommand

function ExpandedPresentationProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if command.Kind == ExpandedPresentationProtocol.Kinds.RegionExpanded then
		if not ValueValidation.IsNonEmptyString(command.RegionId) then
			return false, "InvalidRegionId"
		end
		return true, nil
	end
	if command.Kind == ExpandedPresentationProtocol.Kinds.IncubatorBuilt then
		if not ValueValidation.IsNonEmptyString(command.SpawnPointId) then
			return false, "InvalidSpawnPointId"
		end
		return true, nil
	end
	return false, "InvalidKind"
end

return table.freeze(ExpandedPresentationProtocol)
