--[[
    tooltip.lua — DXUI V2

    Tooltip: hover-подсказка. node:setTooltip(text) — панель + подпись как
    дети узла (destroy-каскад сносит их без утечки), LAYER_TOOLTIP, ниже узла.
    Показ на mouseenter, скрытие на mouseleave. setTooltip(nil) — убрать.

    Задержка показа (hover delay) — future polish (§52), сейчас мгновенно.
]]

DXUI = DXUI or {}

local Node = DXUI.Node
local LAYER = DXUI.LAYER

function Node:setTooltip(text)
    if text == nil then
        if self._tooltip then
            self._tooltip:destroy()
            self._tooltip = nil
        end
        return self
    end

    if not self._tooltip then
        local k = self._context
        if not k then
            DXUI._warn("setTooltip: node is not mounted (no context)")
            return self
        end
        local panel = k:panel({
            layer = LAYER.TOOLTIP,
            visible = false,
            color = 0xE61E1E1E,
        })
        panel.enabled = false
        panel:setParent(self)
        local label = k:label({ color = 0xFFFFFFFF })
        label:setParent(panel)
        self._tooltip = panel
        self._tooltipLabel = label

        self:on("mouseenter", function()
            if panel:isAlive() then
                panel:setPosition(0, self.height + 4)
                panel.visible = true
            end
        end)
        self:on("mouseleave", function()
            if panel:isAlive() then panel.visible = false end
        end)
    end

    self._tooltipLabel.text = text
    -- ширина по text engine (§43): точные метрики шрифта в MTA
    local tw = DXUI.Text.measure(text, self._tooltipLabel.font, 1) + 8
    self._tooltip:setSize(tw, 20)
    self._tooltipLabel:setPosition(4, 3)
    self._tooltipLabel:setSize(tw - 8, 14)
    return self
end
