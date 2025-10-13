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
        -- 尝试多种方式获取tailscale日志，包括错误信息
        local commands = {
            -- 方式1: 直接过滤tailscale相关日志（包括错误）
            logread_cmd .. " -e tailscale 2>&1",
            -- 方式2: 使用grep过滤（包括错误）
            logread_cmd .. " 2>&1 | grep -i tailscale",
            -- 方式3: 获取最近500行然后过滤（增加行数）
            logread_cmd .. " | tail -500 | grep -i tailscale",
            -- 方式4: 尝试tailscaled标签
            logread_cmd .. " -e tailscaled 2>&1",
            -- 方式5: 更广泛的搜索（包括错误）
            logread_cmd .. " 2>&1 | grep -E '(tailscale|tailscaled)'",
            -- 方式6: 获取所有日志然后过滤
            logread_cmd .. " 2>&1 | grep -i 'tailscale\\|tailscaled'",
            -- 方式7: 获取最近的tailscale相关日志
            logread_cmd .. " 2>&1 | grep -i 'tailscale' | tail -100"
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
                -- 保留原始日志格式，只进行简单清理
                local formatted_line = line
                
                -- 移除多余的空白字符
                formatted_line = formatted_line:gsub("^%s+", "")
                formatted_line = formatted_line:gsub("%s+$", "")
                
                -- 确保包含tailscale相关内容（更宽松的匹配）
                if formatted_line:lower():match("tailscale") or formatted_line:lower():match("tailscaled") then
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
            "/var/log/tailscale.log",
            "/var/log/daemon.log"
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

-- 调试信息 - 显示日志获取结果
local debug_info = ""
if log_info.value and #log_info.value > 0 then
    debug_info = string.format("Found %d lines of logs", log_info.rows - 1)
else
    debug_info = "No logs found"
end

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

-- 添加调试信息显示
local debug_field = m:field(DummyValue, "debug_info", translate("Debug Info"))
debug_field.value = debug_info

-- 添加控制按钮
local button_container = m:field(DummyValue, "buttons", translate("Actions"))
button_container.template = "tailscale/log_buttons"

-- 日志显示区域 - 使用TextValue字段显示日志内容（无标签）
local log_text = m:field(TextValue, "log_content")
log_text.template = "cbi/tvalue"
log_text.rows = log_info.rows
log_text.readonly = true
log_text.default = log_info.value or translate("No logs available.")
log_text.cfgvalue = function(self, section)
    return log_info.value or translate("No logs available.")
end
log_text.write = function() end  -- 防止表单提交

-- 添加CSS样式来美化日志显示（紧凑布局）
local css_style = m:field(DummyValue, "css_style")
css_style.rawhtml = true
css_style.value = [[
<style>
/* 紧凑布局样式 */
.cbi-value {
    margin-bottom: 5px !important;
}
.cbi-value-title {
    padding: 2px 0 !important;
    width: 100px !important;
}
.cbi-value-field {
    padding: 2px 0 !important;
}

/* 日志显示区域样式 */
#widget\.log_content, [id*="log_content"] {
    background-color: #1e1e1e !important;
    color: #d4d4d4 !important;
    border: 1px solid #333 !important;
    font-family: 'Courier New', monospace !important;
    font-size: 11px !important;
    white-space: pre-wrap !important;
    max-height: 500px !important;
    overflow-y: auto !important;
    padding: 8px !important;
    line-height: 1.4 !important;
    border-radius: 3px !important;
    width: 100% !important;
    box-sizing: border-box !important;
}

/* 按钮样式优化 */
.cbi-button {
    margin: 2px !important;
    padding: 4px 8px !important;
    font-size: 11px !important;
}

/* 调试信息样式 */
#widget\.debug_info {
    font-size: 11px !important;
    color: #666 !important;
}

/* 日志级别选择器样式 */
#widget\.log_level {
    font-size: 11px !important;
    padding: 2px !important;
}
</style>
]]

return m
