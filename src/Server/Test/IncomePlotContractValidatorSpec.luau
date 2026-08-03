-- 输入：当前 Workspace/PlayerPlots。
-- 输出：成功时返回八个通过场景合同验证的 Plot 数量。
-- 算法：调用生产验证器，确认无错误且本 Place 已准备八个玩家地块。

local IncomePlotContractValidator = require(script.Parent.Parent.IncomePlotContractValidator)

local Spec = {}

function Spec.Run()
	local result = IncomePlotContractValidator.ValidateAll()
	assert(result.Valid, table.concat(result.Errors, "\n"))
	assert(result.PlotCount == 8, string.format("多人场景应有 8 个 Plot，实际为 %d", result.PlotCount))
	return result.PlotCount
end

return Spec
