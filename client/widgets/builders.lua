--[[
    builders.lua — DXUI

    Widget registration. registerWidget(name, class) makes a widget class
    available as:
      - ui:name(props)   — context builder (auto-mounts to root)
      - node:name(props) — parent-scoped builder (attaches as child)

    Internal widgets are registered here; external plugins call
    DXUI.registerWidget to add their own without editing core.
]]

DXUI = DXUI or {}

DXUI._widgets = DXUI._widgets or {}

--- Registers a widget class under a name. class must have a .build(context,
-- props) method returning a node.
function DXUI.registerWidget(name, class)
    DXUI._widgets[name] = class
    -- context builder: ui:name(props)
    DXUI.Context[name] = function(self, props)
        local node = class.build(self, props)
        self:mount(node)
        return node
    end
    -- parent-scoped builder: node:name(props)
    DXUI.Node[name] = function(self, props)
        local node = class.build(self.context, props)
        node:setParent(self)
        return node
    end
end

-- Internal widgets.
DXUI.registerWidget("panel",       DXUI.Panel)
DXUI.registerWidget("label",       DXUI.Label)
DXUI.registerWidget("image",       DXUI.Image)
DXUI.registerWidget("button",      DXUI.Button)
DXUI.registerWidget("checkbox",    DXUI.CheckBox)
DXUI.registerWidget("radiobutton", DXUI.RadioButton)
DXUI.registerWidget("slider",      DXUI.Slider)
DXUI.registerWidget("progressbar", DXUI.ProgressBar)
DXUI.registerWidget("edit",        DXUI.Edit)
DXUI.registerWidget("scrollpanel", DXUI.ScrollPanel)
DXUI.registerWidget("gridlist",    DXUI.GridList)
DXUI.registerWidget("tabpanel",    DXUI.TabPanel)
DXUI.registerWidget("combobox",    DXUI.ComboBox)
DXUI.registerWidget("contextmenu", DXUI.ContextMenu)
DXUI.registerWidget("popup",       DXUI.Popup)
DXUI.registerWidget("window",      DXUI.Window)
-- New widgets
DXUI.registerWidget("memo",        DXUI.Memo)
DXUI.registerWidget("menu",        DXUI.Menu)
DXUI.registerWidget("selector",    DXUI.Selector)
DXUI.registerWidget("switchbutton", DXUI.SwitchButton)
DXUI.registerWidget("line",        DXUI.Line)
DXUI.registerWidget("layout",      DXUI.LayoutBox)
DXUI.registerWidget("scalepane",   DXUI.ScalePane)
