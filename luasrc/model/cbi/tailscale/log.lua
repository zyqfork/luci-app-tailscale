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
    else
        -- 尝试使用dmesg或journalctl作为备选
        if fs.access("/bin/dmesg") then
            logread_cmd = "/bin/dmesg"
        elseif fs.access("/usr/bin/journalctl") then
            logread_cmd = "/usr/bin/journalctl"
        end
    end
    
    if logread_cmd then
        local result = ""
        
        if logread_cmd:match("journalctl") then
            -- 使用journalctl获取tailscale日志
            local cmd = logread_cmd .. " -u tailscaled -n 100 2>/dev/null"
            result = sys.exec(cmd)
        elseif logread_cmd:match("dmesg") then
            -- 使用dmesg获取tailscale相关日志
            local cmd = logread_cmd .. " | grep -i tailscale | tail -50"
            result = sys.exec(cmd)
        else
            -- 使用logread获取tailscale相关日志
            local cmd = logread_cmd .. " -e tailscale 2>/dev/null"
            result = sys.exec(cmd)
        end
        
        if result and #result > 0 then
            local lines = {}
            local status_mappings = {
                ['daemon.err'] = { status = 'StdErr', startIndex = 9 },
                ['daemon.notice'] = { status = 'Info', startIndex = 10 },
                ['daemon.info'] = { status = 'Info', startIndex = 10 },
                ['daemon.warn'] = { status = 'Warning', startIndex = 10 }
            }
            
            for line in result:gmatch("[^\r\n]+") do
                local parts = {}
                for part in line:gmatch("%S+") do
                    table.insert(parts, part)
                end
                
                if #parts >= 5 then
                    local formatted_time = ""
                    local status = ""
                    local message_start = 1
                    
                    -- 根据不同日志格式解析
                    if line:match("^%w+%s+%d+%s+%d+:%d+:%d+") then
                        -- 标准syslog格式
                        formatted_time = parts[1] .. " " .. parts[2] .. " " .. parts[3]
                        status = parts[4] or "info"
                        message_start = 5
                    elseif line:match("^%d+%-%d+%-%d+%s+%d+:%d+:%d+") then
                        -- journalctl格式
                        formatted_time = parts[1] .. " " .. parts[2]
                        status = parts[3] or "info"
                        message_start = 4
                    else
                        -- 其他格式
                        formatted_time = os.date("%Y-%m-%d %H:%M:%S")
                        status = "info"
                        message_start = 1
                    end
                    
                    local mapping = status_mappings[status] or { status = status, startIndex = message_start }
                    local new_status = mapping.status
                    local startIndex = mapping.startIndex
                    
                    local message_parts = {}
                    for i = startIndex, #parts do
                        table.insert(message_parts, parts[i])
                    end
                    local message = table.concat(message_parts, " ")
                    
                    if message:match("tailscale") or message:match("tailscaled") then
                        table.insert(lines, formatted_time .. " [ " .. new_status .. " ] - " .. message)
                    end
                end
            end
            
            log_data = table.concat(lines, "\n")
            log_lines = #lines
        else
            -- 如果没有日志，尝试直接查看tailscale日志文件
            local log_files = {
                "/var/log/tailscale.log",
                "/tmp/tailscale.log",
                "/etc/tailscale/tailscale.log"
            }
            
            for _, log_file in ipairs(log_files) do
                if fs.access(log_file) then
                    local cmd = "tail -50 " .. log_file .. " 2>/dev/null"
                    result = sys.exec(cmd)
                    if result and #result > 0 then
                        log_data = result
                        log_lines = 50
                        break
                    end
                end
            end
        end
    end
    
    return { value = log_data, rows = math.max(log_lines + 1, 10) }
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
log_text.default = log_info.value or translate("Log is empty.")

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
