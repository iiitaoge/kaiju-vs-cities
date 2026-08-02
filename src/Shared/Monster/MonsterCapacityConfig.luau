-- 初始容量只决定新玩家可以建造多少个出生点；后续升级逻辑调用 SetCapacity 修改绝对上限。
return table.freeze({
	InitialCapacity = 1,
})
