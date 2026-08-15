--[[
	职责：为一个已配置实体按钮创建并更新仅本地可见的 WorldObjectUI。
	输入：按钮 Model、服务器返回的完整显示快照。
	输出：可 SetPresentation / Destroy 的句柄。
	内部算法：固定使用按钮合同中的 Pull 作为锚点，委托通用 UI 应用快照；按钮文案
		始终置顶且不按距离裁掉，避免移动端被场景遮挡。
	不负责：按钮触碰、颜色、业务请求或价格计算。
]]

local LocalWorldObjectUI = require(script.Parent.Parent.UI.LocalWorldObjectUI)

local LocalButtonWorldUIController = {}

function LocalButtonWorldUIController.Bind(button: Model)
	assert(button:IsA("Model"), "button 必须是 Model")
	local pull = button:FindFirstChild("Pull")
	assert(pull and pull:IsA("BasePart"), "按钮必须包含 BasePart Pull")

	local worldUI = LocalWorldObjectUI.CreateAbovePart(
		pull,
		"LocalButtonWorldUI",
		{
			AlwaysOnTop = true,
			-- 0 表示不限制渲染距离；按钮 UI 不会因相机远离而消失。
			MaxDistance = 0,
		}
	)
	local destroyed = false
	local handle = {}

	function handle:SetPresentation(presentation)
		if not destroyed then
			worldUI:Apply(presentation)
		end
	end

	function handle:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		worldUI:Destroy()
	end

	return handle
end

return LocalButtonWorldUIController
