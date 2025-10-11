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
    
    -- 优先使用logread命令获取日志
    local logread_cmd = "/sbin/logread"
    if not fs.access(logread_cmd) then
        logread_cmd = "/usr/sbin/logread"
    end
    
    if fs.access(logread_cmd) then
        -- 尝试多种方式获取tailscale日志
        local commands = {
            -- 方式1: 直接过滤tailscale相关日志
            logread_cmd .. " -e tailscale 2>/dev/null",
            -- 方式2: 使用grep过滤
            logread_cmd .. " 2>/dev/null | grep -i tailscale",
            -- 方式3: 获取最近100行然后过滤
            logread_cmd .. " | tail -200 | grep -i tailscale"
        }
        
        local result = ""
        for _, cmd in ipairs(commands) do
            result = sys.exec(cmd)
            if result and #result > 0 then
                break
            end
        end
        
        if result and #result > 0 then
            local lines = {}
            
            for line in result:gmatch("[^\r\n]+") do
                -- 简化日志格式，保留关键信息
                local formatted_line = line
                
                -- 尝试解析标准syslog格式
                if line:match("^%w+%s+%d+%s+%d+:%d+:%d+") then
                    -- 格式: Month Day Time hostname tag: message
                    local time_part = line:match("^(%w+%s+%d+%s+%d+:%d+:%d+)")
                    local message_part = line:match(":%s*(.+)$") or line
                    
                    if message_part:lower():match("tailscale") then
                        formatted_line = time_part .. " - " .. message_part
                    end
                elseif line:lower():match("tailscale") then
                    -- 任何包含tailscale的行都保留
                    formatted_line = line
                end
                
                if formatted_line and #formatted_line > 0 then
                    table.insert(lines, formatted_line)
                end
            end
            
            if #lines > 0 then
                log_data = table.concat(lines, "\n")
                log_lines = #lines
            end
        end
    end
    
    -- 如果系统日志中没有找到，尝试直接查看日志文件
    if #log_data == 0 then
        local log_files = {
            "/var/log/messages",  -- OpenWrt常见日志文件
            "/var/log/syslog",    -- 标准syslog
            "/tmp/tailscale.log", -- tailscale特定日志
            "/var/log/tailscale.log"
        }
        
        for _, log_file in ipairs(log_files) do
            if fs.access(log_file) then
                local cmd = "tail -100 " .. log_file .. " 2>/dev/null | grep -i tailscale"
                local result = sys.exec(cmd)
                if result and #result > 0 then
                    log_data = result
                    log_lines = select(2, result:gsub("\n", "\n")) + 1
                    break
                end
            end
        end
    end
    
    -- 如果还是没有日志，检查tailscaled是否正在运行
    if #log_data == 0 then
        local is_running = sys.call("pgrep tailscaled >/dev/null") == 0
        if not is_running then
            log_data = translate("Tailscale service is not running. Please start the service first.")
        else
            -- 服务正在运行但没有日志，显示状态信息
            local status_info = sys.exec("/usr/sbin/tailscale status 2>/dev/null")
            if status_info and #status_info > 0 then
                log_data = translate("Tailscale service is running but no recent log entries found.") .. "\n\n" .. 
                          translate("Current status:") .. "\n" .. status_info
            else
                log_data = translate("No Tailscale logs found. The service may be running but not generating logs, or logs may be in a different location.")
            end
        end
    end
    
    return { value = log_data, rows = math.max(log_lines + 1, 15) }
end

m = SimpleForm("tailscale_log", translate("Tailscale Logs"), translate("View Tailscale service logs"))
m.reset = false
m.submit = false

-- 获取日志数据
local log_info = get_log_data()

-- 添加日志级别选择
local log_level = m:field(ListValue, "log_level", translate("Log Level"))
log_level:value("all", translate("All"))
log_level:value("info", translate("Info"))
log_level:value("warning", translate("Warning"))
log_level:value("error", translate("Error"))
log_level.default = "all"
log_level.write = function(self, section, value)
    -- 这里可以添加按级别过滤的逻辑
    m.log_level_filter = value
end

-- 添加控制按钮
local button_container = m:field(DummyValue, "buttons", translate("Actions"))
button_container.template = "tailscale/log_buttons"

-- 日志显示区域
local log_text = m:field(TextValue, "log_content")
log_text.template = "cbi/tvalue"
log_text.rows = log_info.rows
log_text.readonly = true
log_text.default = log_info.value or translate("Log is empty.")

return m
