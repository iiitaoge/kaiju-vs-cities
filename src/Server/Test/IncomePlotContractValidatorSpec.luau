-- 输入：当前 Workspace/PlayerPlots。
-- 输出：成功时返回八个通过场景合同验证的 Plot 数量。
-- 算法：调用生产验证器，确认无错误且本 Place 已准备八个玩家地块。

local PlayerPlotContractValidator = require(script.Parent.Parent.PlayerPlotContractValidator)

local Spec = {}

function Spec.Run()
	local result = PlayerPlotContractValidator.ValidateAll()
	assert(result.Valid, table.concat(result.Errors, "\n"))
	assert(result.PlotCount == 8, string.format("多人场景应有 8 个 Plot，实际为 %d", result.PlotCount))
	assert(result.RequiredMaxPlayers == 8, "场景合同要求的玩家数必须为 8")
	assert(result.CapacityValid, string.format("当前环境容量不足，实际 MaxPlayers 为 %d", result.MaxPlayers))
	return result.PlotCount
end

return Spec
