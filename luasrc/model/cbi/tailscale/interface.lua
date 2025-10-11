-- SPDX-License-Identifier: GPL-3.0-only
--
-- Copyright (C) 2022 ImmortalWrt.org
-- Copyright (C) 2024 asvow
-- Lua version for OpenWrt 18.0.3

local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"
local json = require "luci.jsonc"

local function get_interface_info()
    local interfaces = {}
    
    -- 执行ip命令获取接口信息
    local cmd = "/sbin/ip -s -j addr"
    local result = sys.exec(cmd .. " 2>/dev/null")
    
    if result and #result > 0 then
        local ok, data = pcall(json.parse, result)
        if ok and data then
            for _, iface in ipairs(data) do
                -- 检查是否为tailscale接口
                if iface.ifname and iface.ifname:match("tailscale[0-9]+") then
                    local interface_info = {
                        name = iface.ifname,
                        ipv4 = "",
                        ipv6 = "",
                        mtu = iface.mtu or "0",
                        rxBytes = "0",
                        txBytes = "0"
                    }
                    
                    -- 解析IP地址
                    if iface.addr_info then
                        for _, addr in ipairs(iface.addr_info) do
                            if addr.family == "inet" and interface_info.ipv4 == "" then
                                interface_info.ipv4 = addr.local or ""
                            elseif addr.family == "inet6" and interface_info.ipv6 == "" then
                                interface_info.ipv6 = addr.local or ""
                            end
                        end
                    end
                    
                    -- 解析统计信息
                    if iface.stats64 then
                        if iface.stats64.rx and iface.stats64.rx.bytes then
                            interface_info.rxBytes = tostring(iface.stats64.rx.bytes)
                        end
                        if iface.stats64.tx and iface.stats64.tx.bytes then
                            interface_info.txBytes = tostring(iface.stats64.tx.bytes)
                        end
                    end
                    
                    table.insert(interfaces, interface_info)
                end
            end
        end
    end
    
    return interfaces
end

local function format_bytes(bytes_str)
    local bytes = tonumber(bytes_str) or 0
    if bytes == 0 then return "0 B" end
    
    local units = {"B", "KB", "MB", "GB", "TB"}
    local size = bytes
    local unit_index = 1
    
    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end
    
    return string.format("%.2f %s", size, units[unit_index])
end

m = SimpleForm("tailscale", translate("Tailscale"), translate("Tailscale is a cross-platform and easy to use virtual LAN."))
m.reset = false
m.submit = false

-- 获取接口信息
local interfaces = get_interface_info()

if #interfaces == 0 then
    local s = m:section(SimpleSection)
    s:option(DummyValue, "no_interface", translate("No interface online."))
else
    -- 创建表格显示接口信息
    local s = m:section(Table, interfaces, translate("Network Interface Information"))
    
    o = s:option(DummyValue, "name", translate("Interface Name"))
    o.width = "20%"
    
    o = s:option(DummyValue, "ipv4", translate("IPv4 Address"))
    o.width = "20%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, "ipv4")
        return (value and value ~= "") and value or translate("None")
    end
    
    o = s:option(DummyValue, "ipv6", translate("IPv6 Address"))
    o.width = "20%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, "ipv6")
        return (value and value ~= "") and value or translate("None")
    end
    
    o = s:option(DummyValue, "mtu", translate("MTU"))
    o.width = "13%"
    
    o = s:option(DummyValue, "rxBytes", translate("Download"))
    o.width = "13%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, "rxBytes")
        return format_bytes(value)
    end
    
    o = s:option(DummyValue, "txBytes", translate("Upload"))
    o.width = "14%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, "txBytes")
        return format_bytes(value)
    end
end

-- 添加刷新按钮
local refresh = m:field(Button, "refresh", translate("Refresh"))
refresh.inputstyle = "reload"
refresh.write = function()
    luci.http.redirect(luci.dispatcher.build_url("admin/vpn/tailscale/interface"))
end

return m
