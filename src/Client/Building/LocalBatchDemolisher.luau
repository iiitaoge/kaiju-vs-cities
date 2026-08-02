local LocalModelDemolisher = require(script.Parent.LocalModelDemolisher)

local LocalBatchDemolisher = {}

function LocalBatchDemolisher.Demolish(models: { Model })
	local errors = {}
	local remaining = #models

	for _, model in ipairs(models) do
		task.spawn(function()
			local success, result = pcall(LocalModelDemolisher.Demolish, model)

			if not success then
				table.insert(errors, tostring(result))
			end

			remaining -= 1
		end)
	end

	while remaining > 0 do
		task.wait()
	end

	assert(#errors == 0, "批量拆除失败：\n" .. table.concat(errors, "\n"))
end

return LocalBatchDemolisher
