local PlayerAttackViewAccess = require(script.Parent.PlayerAttackViewAccess)

local WorkspacePlayerAttackViewAccess = {}

export type CreateOptions = {
	GetPlot: (Player) -> Model?,
}

-- 场景路径：Plot/AttackViewBounds。只读取一个总范围，不读取 Zone 状态。
function WorkspacePlayerAttackViewAccess.Create(options: CreateOptions): PlayerAttackViewAccess.Access
	assert(type(options) == "table" and type(options.GetPlot) == "function", "GetPlot 必须是 function")

	return {
		GetAttackView = function(player: Player): PlayerAttackViewAccess.AttackView?
			local plot = options.GetPlot(player)
			if not plot then
				return nil
			end
			local bounds = plot:FindFirstChild("AttackViewBounds")
			if not bounds or not bounds:IsA("BasePart") then
				return nil
			end
			return {
				CFrame = bounds.CFrame,
				Size = bounds.Size,
			}
		end,
	}
end

return WorkspacePlayerAttackViewAccess
