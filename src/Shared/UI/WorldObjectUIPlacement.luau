--[[
	职责：保存房屋和按钮世界 UI 的独立位置/刷新参数。
	输入/输出：无函数；供客户端放置器读取。
	不负责：查找模型、创建 Attachment 或解释业务状态。
]]

return table.freeze({
	-- 模板高 6 studs 且 UIListLayout 顶对齐；3.5 让第一行落在目标顶部约 0.5 stud 之上。
	HouseTopOffsetStuds = 3.5,
	ButtonTopOffsetStuds = 3.5,
	AccumulatedMoneyRefreshSeconds = 0.2,
})
