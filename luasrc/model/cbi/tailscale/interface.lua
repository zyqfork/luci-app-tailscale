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
                        ipv4 = nil,
                        ipv6 = nil,
                        mtu = iface.mtu or 0,
                        rxBytes = 0,
                        txBytes = 0
                    }
                    
                    -- 解析IP地址
                    if iface.addr_info then
                        for _, addr in ipairs(iface.addr_info) do
                            if addr.family == "inet" and not interface_info.ipv4 then
                                interface_info.ipv4 = addr.local
                            elseif addr.family == "inet6" and not interface_info.ipv6 then
                                interface_info.ipv6 = addr.local
                            end
                        end
                    end
                    
                    -- 解析统计信息
                    if iface.stats64 then
                        if iface.stats64.rx and iface.stats64.rx.bytes then
                            interface_info.rxBytes = iface.stats64.rx.bytes
                        end
                        if iface.stats64.tx and iface.stats64.tx.bytes then
                            interface_info.txBytes = iface.stats64.tx.bytes
                        end
                    end
                    
                    table.insert(interfaces, interface_info)
                end
            end
        end
    end
    
    return interfaces
end

local function format_bytes(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    
    local units = {"B", "KB", "MB", "GB", "TB"}
    local size = tonumber(bytes)
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
    m:field(DummyValue, "no_interface", translate("No interface online."))
else
    -- 创建表格显示接口信息
    local s = m:section(Table, interfaces, translate("Network Interface Information"))
    
    o = s:option(DummyValue, "name", translate("Interface Name"))
    o.width = "25%"
    
    o = s:option(DummyValue, "ipv4", translate("IPv4 Address"))
    o.width = "25%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, self.option)
        return value or translate("None")
    end
    
    o = s:option(DummyValue, "ipv6", translate("IPv6 Address"))
    o.width = "25%"
    o.cfgvalue = function(self, section)
        local value = AbstractValue.cfgvalue(self, section)
        return value or translate("None")
    end
    
    o = s:option(DummyValue, "mtu", translate("MTU"))
    o.width = "25%"
    
    o = s:option(DummyValue, "rxBytes", translate("Total Download"))
    o.width = "25%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, self.option)
        return format_bytes(value)
    end
    
    o = s:option(DummyValue, "txBytes", translate("Total Upload"))
    o.width = "25%"
    o.cfgvalue = function(self, section)
        local value = self.map:get(section, self.option)
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
