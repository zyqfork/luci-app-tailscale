-- SPDX-License-Identifier: GPL-3.0-only
--
-- Copyright (C) 2024 asvow
-- Lua version for OpenWrt 18.0.3

local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"

local function get_log_data()
    local log_data = ""
    local log_lines = 0
    
    -- 检查logread命令位置
    local logread_cmd = nil
    if fs.access("/sbin/logread") then
        logread_cmd = "/sbin/logread"
    elseif fs.access("/usr/sbin/logread") then
        logread_cmd = "/usr/sbin/logread"
    end
    
    if logread_cmd then
        -- 获取tailscale相关日志
        local cmd = logread_cmd .. " -e tailscale 2>/dev/null"
        local result = sys.exec(cmd)
        
        if result and #result > 0 then
            local lines = {}
            local status_mappings = {
                ['daemon.err'] = { status = 'StdErr', startIndex = 9 },
                ['daemon.notice'] = { status = 'Info', startIndex = 10 }
            }
            
            for line in result:gmatch("[^\r\n]+") do
                local parts = {}
                for part in line:gmatch("%S+") do
                    table.insert(parts, part)
                end
                
                if #parts >= 6 then
                    local formatted_time = parts[1] .. " " .. parts[2] .. " - " .. parts[3]
                    local status = parts[5]
                    local mapping = status_mappings[status] or { status = status, startIndex = 9 }
                    local new_status = mapping.status
                    local startIndex = mapping.startIndex
                    
                    local message_parts = {}
                    for i = startIndex, #parts do
                        table.insert(message_parts, parts[i])
                    end
                    local message = table.concat(message_parts, " ")
                    
                    table.insert(lines, formatted_time .. " [ " .. new_status .. " ] - " .. message)
                end
            end
            
            log_data = table.concat(lines, "\n")
            log_lines = #lines
        end
    end
    
    return { value = log_data, rows = log_lines + 1 }
end

m = SimpleForm("tailscale_log", translate("Tailscale Logs"), translate("View Tailscale service logs"))
m.reset = false
m.submit = false

-- 获取日志数据
local log_info = get_log_data()

-- 添加滚动到顶部按钮
local scroll_up = m:field(Button, "scroll_up", translate("Scroll to head"))
scroll_up.inputstyle = "neutral"
scroll_up.write = function() end

-- 日志显示区域
local log_text = m:field(TextValue, "log_content")
log_text.template = "cbi/tvalue"
log_text.rows = log_info.rows
log_text.readonly = true
log_text:value(log_info.value or translate("Log is empty."))

-- 添加滚动到底部按钮
local scroll_down = m:field(Button, "scroll_down", translate("Scroll to tail"))
scroll_down.inputstyle = "neutral"
scroll_down.write = function() end

-- 添加刷新按钮
local refresh = m:field(Button, "refresh", translate("Refresh"))
refresh.inputstyle = "reload"
refresh.write = function()
    luci.http.redirect(luci.dispatcher.build_url("admin/vpn/tailscale/log"))
end

return m
