-- SPDX-License-Identifier: GPL-3.0-only
--
-- Copyright (C) 2024 asvow
-- Lua version for OpenWrt 18.0.3

local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local http = require "luci.http"
local json = require "luci.jsonc"

local function get_interface_subnets(interfaces)
    local subnets = {}
    if not interfaces then interfaces = {'lan', 'wan'} end
    
    for _, iface in ipairs(interfaces) do
        local net = uci:get_all("network", iface)
        if net and net.ipaddr and net.netmask then
            local ip = net.ipaddr
            local mask = net.netmask
            -- 简化的子网掩码到CIDR转换
            local mask_octets = {}
            for octet in mask:gmatch("%d+") do
                table.insert(mask_octets, tonumber(octet))
            end
            
            if #mask_octets == 4 then
                -- 预定义的子网掩码到CIDR映射
                local mask_to_cidr = {
                    ["255.255.255.255"] = 32,
                    ["255.255.255.254"] = 31,
                    ["255.255.255.252"] = 30,
                    ["255.255.255.248"] = 29,
                    ["255.255.255.240"] = 28,
                    ["255.255.255.224"] = 27,
                    ["255.255.255.192"] = 26,
                    ["255.255.255.128"] = 25,
                    ["255.255.255.0"] = 24,
                    ["255.255.254.0"] = 23,
                    ["255.255.252.0"] = 22,
                    ["255.255.248.0"] = 21,
                    ["255.255.240.0"] = 20,
                    ["255.255.224.0"] = 19,
                    ["255.255.192.0"] = 18,
                    ["255.255.128.0"] = 17,
                    ["255.255.0.0"] = 16,
                    ["255.254.0.0"] = 15,
                    ["255.252.0.0"] = 14,
                    ["255.248.0.0"] = 13,
                    ["255.240.0.0"] = 12,
                    ["255.224.0.0"] = 11,
                    ["255.192.0.0"] = 10,
                    ["255.128.0.0"] = 9,
                    ["255.0.0.0"] = 8,
                    ["254.0.0.0"] = 7,
                    ["252.0.0.0"] = 6,
                    ["248.0.0.0"] = 5,
                    ["240.0.0.0"] = 4,
                    ["224.0.0.0"] = 3,
                    ["192.0.0.0"] = 2,
                    ["128.0.0.0"] = 1,
                    ["0.0.0.0"] = 0
                }
                local mask_str = table.concat(mask_octets, ".")
                local cidr = mask_to_cidr[mask_str] or 24 -- 默认为/24
                table.insert(subnets, ip .. "/" .. cidr)
            end
        end
    end
    
    -- 去重
    local unique_subnets = {}
    local seen = {}
    for _, subnet in ipairs(subnets) do
        if not seen[subnet] then
            seen[subnet] = true
            table.insert(unique_subnets, subnet)
        end
    end
    
    return unique_subnets
end

local function get_status()
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
    
    return status
end

local function render_status(isRunning)
    if isRunning then
        return translate("Tailscale") .. " " .. translate("RUNNING")
    else
        return translate("Tailscale") .. " " .. translate("NOT RUNNING")
    end
end

local function render_login(loginStatus, authURL, displayName)
    if loginStatus == "NeedsLogin" and authURL then
        return translate("Need to log in") .. ": " .. authURL
    elseif loginStatus == "Running" and displayName then
        return displayName .. " - " .. translate("Logged in")
    else
        return translate("NOT RUNNING")
    end
end

local status = get_status()
local interface_subnets = get_interface_subnets({'lan', 'wan'})

m = Map("tailscale", translate("Tailscale"), translate("Tailscale is a cross-platform and easy to use virtual LAN."))

-- 状态显示部分
s = m:section(TypedSection, "tailscale", translate("Service Status"))
s.anonymous = true
s:option(DummyValue, "status", translate("Status")).value = render_status(status.isRunning)
s:option(DummyValue, "login", translate("Login Status")).value = render_login(status.backendState, status.authURL, status.displayName)

-- 基本设置
s = m:section(NamedSection, "settings", "config", translate("Basic Settings"))

o = s:option(Flag, "enabled", translate("Enable"))
o.default = o.disabled
o.rmempty = false

o = s:option(Value, "port", translate("Port"), translate("Set the Tailscale port number."))
o.datatype = "port"
o.default = "41641"
o.rmempty = false

o = s:option(Value, "config_path", translate("Workdir"), translate("The working directory contains config files, audit logs, and runtime info."))
o.default = "/etc/tailscale"
o.rmempty = false

o = s:option(ListValue, "fw_mode", translate("Firewall Mode"))
o:value("nftables", "nftables")
o:value("iptables", "iptables")
o.default = "nftables"
o.rmempty = false

o = s:option(Flag, "log_stdout", translate("StdOut Log"), translate("Logging program activities."))
o.default = o.enabled
o.rmempty = false

o = s:option(Flag, "log_stderr", translate("StdErr Log"), translate("Logging program errors and exceptions."))
o.default = o.enabled
o.rmempty = false

-- 高级设置
s = m:section(NamedSection, "settings", "config", translate("Advanced Settings"))

o = s:option(Flag, "accept_routes", translate("Accept Routes"), translate("Accept subnet routes that other nodes advertise."))
o.default = o.disabled
o.rmempty = false

o = s:option(Value, "hostname", translate("Device Name"), translate("Leave blank to use the device's hostname."))
o.default = ""
o.rmempty = true

o = s:option(Flag, "accept_dns", translate("Accept DNS"), translate("Accept DNS configuration from the Tailscale admin console."))
o.default = o.enabled
o.rmempty = false

o = s:option(Flag, "advertise_exit_node", translate("Exit Node"), translate("Offer to be an exit node for outbound internet traffic from the Tailscale network."))
o.default = o.disabled
o.rmempty = false

o = s:option(ListValue, "exit_node", translate("Online Exit Nodes"), translate("Select an online machine name to use as an exit node."))
if #status.onlineExitNodes > 0 then
    o.optional = true
    for _, node in ipairs(status.onlineExitNodes) do
        o:value(node, node)
    end
else
    o:value("", translate("No Available Exit Nodes"))
    o.readonly = true
end
o.default = ""
o:depends("advertise_exit_node", "0")
o.rmempty = true

o = s:option(DynamicList, "advertise_routes", translate("Expose Subnets"), translate("Expose physical network routes into Tailscale, e.g. 10.0.0.0/24."))
if #interface_subnets > 0 then
    for _, subnet in ipairs(interface_subnets) do
        o:value(subnet, subnet)
    end
end
o.default = ""
o.rmempty = true

o = s:option(Flag, "disable_snat_subnet_routes", translate("Site To Site"), translate("Use site-to-site layer 3 networking to connect subnets on the Tailscale network."))
o.default = o.disabled
o:depends("accept_routes", "1")
o.rmempty = false

o = s:option(DynamicList, "subnet_routes", translate("Subnet Routes"), translate("Select subnet routes advertised by other nodes in Tailscale network."))
if #status.subnetRoutes > 0 then
    for _, route in ipairs(status.subnetRoutes) do
        o:value(route, route)
    end
else
    o:value("", translate("No Available Subnet Routes"))
    o.readonly = true
end
o.default = ""
o:depends("disable_snat_subnet_routes", "1")
o.rmempty = true

o = s:option(MultiValue, "access", translate("Access Control"))
o:value("ts_ac_lan", translate("Tailscale access LAN"))
o:value("ts_ac_wan", translate("Tailscale access WAN"))
o:value("lan_ac_ts", translate("LAN access Tailscale"))
o:value("wan_ac_ts", translate("WAN access Tailscale"))
o.default = "ts_ac_lan ts_ac_wan lan_ac_ts"
o.rmempty = true

-- 额外设置
s = m:section(NamedSection, "settings", "config", translate("Extra Settings"))

o = s:option(DynamicList, "flags", translate("Additional Flags"),
    translate("List of extra flags. Format: --flags=value, e.g. --exit-node=10.0.0.1. <br> for enabling settings upon the initiation of Tailscale.") .. 
    ' <a href="https://tailscale.com/kb/1241/tailscale-up" target="_blank">' .. translate("Available flags") .. '</a>'
)
o.default = ""
o.rmempty = true

-- 自定义服务器设置
s = m:section(NamedSection, "settings", "config", translate("Custom Server Settings"))
s.description = translate("Use headscale to deploy a private server.")

o = s:option(Value, "login_server", translate("Server Address"))
o.default = ""
o.rmempty = true

o = s:option(Value, "authKey", translate("Auth Key"))
o.default = ""
o.rmempty = true

return m
