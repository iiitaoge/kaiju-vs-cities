-- 重生只有一个全局 UI 入口；客户端请求 GetState 或 Execute，服务器返回完整状态快照。
return table.freeze({
	RemoteName = "RebirthRequest",
})
