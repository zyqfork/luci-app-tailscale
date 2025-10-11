-- SPDX-License-Identifier: GPL-3.0-only
--
-- Copyright (C) 2024 asvow
-- Lua version for OpenWrt 18.0.3

module("luci.controller.tailscale", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/tailscale") then
		return
	end
	
	local page = entry({"admin", "vpn", "tailscale"}, firstchild(), _("Tailscale"), 90)
	page.dependent = false
	page.acl_depends = { "luci-app-tailscale" }
	
	entry({"admin", "vpn", "tailscale", "setting"}, cbi("tailscale/setting"), _("Global Settings"), 10)
	entry({"admin", "vpn", "tailscale", "interface"}, cbi("tailscale/interface"), _("Interface Info"), 20)
	entry({"admin", "vpn", "tailscale", "log"}, cbi("tailscale/log"), _("Logs"), 30)
	
	-- AJAX接口
	entry({"admin", "vpn", "tailscale", "status"}, call("get_status")).leaf = true
	entry({"admin", "vpn", "tailscale", "logout"}, call("action_logout")).leaf = true
end

function get_status()
	local sys = require "luci.sys"
	local json = require "luci.jsonc"
	
	local status = {
		isRunning = false,
		backendState = nil,
		authURL = nil,
		displayName = nil,
		onlineExitNodes = {},
		subnetRoutes = {}
	}
	
	-- 检查服务状态
	local running = sys.call("pgrep tailscaled >/dev/null") == 0
	status.isRunning = running
	
	if running then
		-- 获取tailscale状态
		local tailscale_status = sys.exec("/usr/sbin/tailscale status --json 2>/dev/null")
		if tailscale_status and #tailscale_status > 0 then
			local ok, result = pcall(json.parse, tailscale_status)
			if ok and result then
				status.backendState = result.BackendState
				status.authURL = result.AuthURL
				
				if status.backendState == "Running" and result.Self and result.User then
					local userID = result.Self.UserID
					if userID and result.User[userID] then
						status.displayName = result.User[userID].DisplayName
					end
				end
				
				-- 获取在线出口节点和子网路由
				if result.Peer then
					for _, peer in pairs(result.Peer) do
						if peer.ExitNodeOption and peer.Online then
							table.insert(status.onlineExitNodes, peer.HostName)
						end
						if peer.PrimaryRoutes then
							for _, route in ipairs(peer.PrimaryRoutes) do
								table.insert(status.subnetRoutes, route)
							end
						end
					end
				end
			end
		end
	end
	
	luci.http.prepare_content("application/json")
	luci.http.write_json(status)
end

function action_logout()
	local sys = require "luci.sys"
	
	-- 执行登出命令
	local result = sys.call("/usr/sbin/tailscale logout >/dev/null 2>&1")
	
	luci.http.prepare_content("application/json")
	luci.http.write_json({ success = (result == 0) })
end
