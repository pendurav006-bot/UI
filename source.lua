--[[
  Elegant UI Library (single file)
  API:
    local library = loadstring(game:HttpGet("<your-raw-url-here>"))()

    local Window = library:CreateWindow("cattoware UI", Vector2.new(492, 598), Enum.KeyCode.Delete)
    local tab = Window:CreateTab("example")
    local sector = tab:CreateSector("controls", "left")

    -- Controls:
    sector:AddToggle(name, default, [flag], [callback])
      -> returns toggleControl with :AddColorpicker(defaultColor3, callback)

    sector:AddSlider(name, min, default, max, step, callback)

    sector:AddKeybind(name, defaultKeyCode, toggleModeBool, [flag], [callback])
      (toggleMode: if true, pressing the key toggles an on/off flag)

    sector:AddDropdown(name, list, default, isMulti, callback)

    sector:AddLabel(text)

    sector:AddColorpicker(name, defaultColor3, callback)  -- sector-level picker

    -- Config System on a tab:
    tab:CreateConfigSystem("right")

    -- Theming:
    library.theme = {
      accentcolor   = Color3.fromRGB(158, 97, 255),
      accentcolor2  = Color3.fromRGB(158, 97, 255),
      background    = Color3.fromRGB(20, 20, 20),
      stroke        = Color3.fromRGB(50, 50, 50),
      text          = Color3.fromRGB(230, 230, 230),
      tilesize      = 90,
    }

    library.flags    -- table of flagName -> current value
    library:SaveConfig(name)
    library:LoadConfig(name)
    library:DeleteConfig(name)
    library:ListConfigs() -> { "myconfig", ... }
]]--

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- // File API shim (executor-provided or in-memory fallback)
local _isfile   = isfile or function(_) return false end
local _write    = writefile or function(_,_) end
local _read     = readfile or function(_) return "" end
local _isfolder = isfolder or function(_) return false end
local _makefld  = makefolder or function(_) end
local _list     = listfiles or function(_) return {} end
local _delf     = delfile or function(_) end

-- // Library root
local library = {
  _gui = nil,
  _tabs = {},
  _tabButtons = {},
  _activeTab = nil,
  _tracked = { accents = {}, backgrounds = {}, text = {}, strokes = {} },
  _setters = {},      -- flag -> function(value, silent)
  flags = {},         -- flag -> value
  theme = {
    accentcolor  = Color3.fromRGB(158, 97, 255),
    accentcolor2 = Color3.fromRGB(158, 97, 255),
    background   = Color3.fromRGB(20, 20, 20),
    stroke       = Color3.fromRGB(50, 50, 50),
    text         = Color3.fromRGB(230, 230, 230),
    tilesize     = 90,
  },
  _basePath = "elegant-ui",
  _cfgPath  = "elegant-ui/configs",
}

-- Ensure folders
if not _isfolder(library._basePath) then _makefld(library._basePath) end
if not _isfolder(library._cfgPath) then _makefld(library._cfgPath) end

-- // Small helpers
local function new(klass, props, children, parent)
  local inst = Instance.new(klass)
  if props then
    for k,v in pairs(props) do
      inst[k] = v
    end
  end
  if children then
    for _,c in ipairs(children) do
      c.Parent = inst
    end
  end
  if parent then inst.Parent = parent end
  return inst
end

local function roundToStep(val, step)
  if step == 0 or step == nil then return val end
  return math.floor((val / step) + 0.5) * step
end

local function color3ToTable(c)
  return { r = math.floor(c.R * 255 + 0.5), g = math.floor(c.G * 255 + 0.5), b = math.floor(c.B * 255 + 0.5) }
end
local function tableToColor3(t)
  return Color3.fromRGB(t.r or 255, t.g or 255, t.b or 255)
end

-- // Theme registration
function library:_track(kind, inst, prop)
  table.insert(self._tracked[kind], {inst=inst, prop=prop})
end

function library:_applyTheme()
  for _,e in ipairs(self._tracked.accents) do
    if e.inst and e.inst.Parent then e.inst[e.prop] = self.theme.accentcolor end
  end
  for _,e in ipairs(self._tracked.backgrounds) do
    if e.inst and e.inst.Parent then e.inst[e.prop] = self.theme.background end
  end
  for _,e in ipairs(self._tracked.text) do
    if e.inst and e.inst.Parent then e.inst[e.prop] = self.theme.text end
  end
  for _,e in ipairs(self._tracked.strokes) do
    if e.inst and e.inst.Parent then e.inst[e.prop] = self.theme.stroke end
  end
end

-- // Dragging behavior
local function makeDraggable(frame, dragHandle)
  local dragging, dragStart, startPos
  dragHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      dragging = true
      dragStart = input.Position
      startPos = frame.Position
      input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then dragging = false end
      end)
    end
  end)
  dragHandle.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
      local delta = input.Position - dragStart
      frame.Position = UDim2.fromOffset(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y)
    end
  end)
end

-- // Config I/O
function library:ListConfigs()
  local items = {}
  for _,path in ipairs(_list(self._cfgPath)) do
    local name = path:match("[/\\]([^/\\]+)%.json$")
    if name then table.insert(items, name) end
  end
  table.sort(items)
  return items
end

function library:SaveConfig(name)
  if not name or name == "" then return false, "empty name" end
  local payload = { flags = {}, theme = {
    accentcolor  = color3ToTable(self.theme.accentcolor),
    accentcolor2 = color3ToTable(self.theme.accentcolor2),
    background   = color3ToTable(self.theme.background),
    stroke       = color3ToTable(self.theme.stroke),
    text         = color3ToTable(self.theme.text),
    tilesize     = self.theme.tilesize,
  }}
  for k,v in pairs(self.flags) do
    -- KeyCode values -> string; Color3 tables handled by controls themselves on set
    if typeof(v) == "EnumItem" and v.EnumType == Enum.KeyCode then
      payload.flags[k] = { __keycode = v.Name }
    else
      payload.flags[k] = v
    end
  end
  local ok, data = pcall(HttpService.JSONEncode, HttpService, payload)
  if not ok then return false, "json encode failed" end
  _write(("%s/%s.json"):format(self._cfgPath, name), data)
  return true
end

function library:LoadConfig(name)
  local path = ("%s/%s.json"):format(self._cfgPath, name)
  if not _isfile(path) then return false, "not found" end
  local raw = _read(path)
  local ok, payload = pcall(HttpService.JSONDecode, HttpService, raw)
  if not ok or type(payload) ~= "table" then return false, "bad json" end

  -- theme
  if payload.theme then
    local T = payload.theme
    self.theme.accentcolor  = tableToColor3(T.accentcolor or {r=158,g=97,b=255})
    self.theme.accentcolor2 = tableToColor3(T.accentcolor2 or {r=158,g=97,b=255})
    self.theme.background   = tableToColor3(T.background or {r=20,g=20,b=20})
    self.theme.stroke       = tableToColor3(T.stroke or {r=50,g=50,b=50})
    self.theme.text         = tableToColor3(T.text or {r=230,g=230,b=230})
    self.theme.tilesize     = T.tilesize or 90
    self:_applyTheme()
  end

  -- flags (call setters)
  if payload.flags then
    for flag, val in pairs(payload.flags) do
      if type(val) == "table" and val.__keycode then
        val = Enum.KeyCode[val.__keycode] or Enum.KeyCode.Unknown
      end
      local setter = self._setters[flag]
      if setter then
        setter(val, true) -- silent (no callback spam)
      else
        self.flags[flag] = val
      end
    end
  end
  return true
end

function library:DeleteConfig(name)
  local path = ("%s/%s.json"):format(self._cfgPath, name)
  if _isfile(path) then _delf(path) return true end
  return false
end

-- // Window + Tabs
function library:CreateWindow(title, sizeVec2, toggleKey)
  if self._gui then self._gui:Destroy() end

  local gui = new("ScreenGui", { Name="ElegantUILib", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling }, nil, CoreGui)
  self._gui = gui

  local root = new("Frame", {
    Name="Window",
    Size = UDim2.fromOffset(sizeVec2.X, sizeVec2.Y),
    Position = UDim2.fromOffset(200, 150),
    BackgroundColor3 = self.theme.background,
    BorderSizePixel = 0
  }, nil, gui)
  self:_track("backgrounds", root, "BackgroundColor3")

  local stroke = new("UIStroke", { Color = self.theme.stroke, Thickness = 1 }, nil, root)
  self:_track("strokes", stroke, "Color")

  local corner = new("UICorner", { CornerRadius = UDim.new(0, 6) }, nil, root)

  local titlebar = new("Frame", {
    Name="Titlebar",
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = self.theme.background,
    BorderSizePixel = 0
  }, nil, root)
  self:_track("backgrounds", titlebar, "BackgroundColor3")

  new("UICorner", { CornerRadius = UDim.new(0, 6) }, nil, titlebar)

  local titleLbl = new("TextLabel", {
    Size = UDim2.new(1, -12, 1, 0),
    Position = UDim2.fromOffset(12, 0),
    Text = title or "Elegant UI",
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = self.theme.text,
    BackgroundTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Left
  }, nil, titlebar)
  self:_track("text", titleLbl, "TextColor3")

  local tabsBar = new("Frame", {
    Name="TabsBar",
    Size = UDim2.new(1, -24, 0, 28),
    Position = UDim2.fromOffset(12, 40),
    BackgroundTransparency = 1,
  }, nil, root)

  local tabLayout = new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    HorizontalAlignment = Enum.HorizontalAlignment.Left
  }, nil, tabsBar)

  local content = new("Frame", {
    Name="Content",
    Size = UDim2.new(1, -24, 1, -40-12-12),
    Position = UDim2.fromOffset(12, 40+28+12),
    BackgroundTransparency = 1
  }, nil, root)

  -- toggle key to show/hide
  if toggleKey then
    UserInputService.InputBegan:Connect(function(input, gpe)
      if gpe then return end
      if input.KeyCode == toggleKey then
        root.Visible = not root.Visible
      end
    end)
  end

  makeDraggable(root, titlebar)

  -- Window object
  local Window = {}
  Window._tabFrames = {}
  Window._tabButtons = {}
  Window._active = nil
  Window._content = content
  Window._tabsBar = tabsBar

  function Window:_switch(toName)
    for name, frame in pairs(self._tabFrames) do
      frame.Visible = (name == toName)
    end
    for name, btn in pairs(self._tabButtons) do
      btn.BackgroundColor3 = (name == toName) and library.theme.accentcolor or library.theme.background
      btn.TextColor3 = (name == toName) and Color3.new(1,1,1) or library.theme.text
    end
    library:_applyTheme()
    self._active = toName
  end

  function Window:CreateTab(name)
    name = tostring(name)

    local btn = new("TextButton", {
      Size = UDim2.fromOffset(110, 28),
      Text = name,
      Font = Enum.Font.Gotham,
      TextSize = 13,
      BackgroundColor3 = library.theme.background,
      TextColor3 = library.theme.text,
      AutoButtonColor = false
    }, nil, tabsBar)
    library:_track("backgrounds", btn, "BackgroundColor3")
    library:_track("text", btn, "TextColor3")

    local tabFrame = new("Frame", {
      Name = "Tab_"..name,
      Size = UDim2.new(1, 0, 1, 0),
      BackgroundTransparency = 1,
      Visible = false
    }, nil, content)

    -- two columns
    local leftCol = new("Frame", {
      Name="Left",
      Size = UDim2.new(0.5, -6, 1, 0),
      BackgroundTransparency = 1
    }, nil, tabFrame)

    local leftLayout = new("UIListLayout", {
      Padding = UDim.new(0, 8),
      FillDirection = Enum.FillDirection.Vertical,
      HorizontalAlignment = Enum.HorizontalAlignment.Left,
      SortOrder = Enum.SortOrder.LayoutOrder
    }, nil, leftCol)

    local rightCol = new("Frame", {
      Name="Right",
      Size = UDim2.new(0.5, -6, 1, 0),
      Position = UDim2.new(0.5, 12, 0, 0),
      BackgroundTransparency = 1
    }, nil, tabFrame)

    local rightLayout = new("UIListLayout", {
      Padding = UDim.new(0, 8),
      FillDirection = Enum.FillDirection.Vertical,
      HorizontalAlignment = Enum.HorizontalAlignment.Left,
      SortOrder = Enum.SortOrder.LayoutOrder
    }, nil, rightCol)

    btn.MouseButton1Click:Connect(function()
      Window:_switch(name)
    end)

    self._tabFrames[name] = tabFrame
    self._tabButtons[name] = btn

    local Tab = {}
    Tab._left = leftCol
    Tab._right = rightCol

    function Tab:CreateSector(title, side)
      local parent = (side == "right") and rightCol or leftCol
      local sector = new("Frame", {
        Name = "Sector_"..title,
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = library.theme.background,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y
      }, nil, parent)
      library:_track("backgrounds", sector, "BackgroundColor3")
      new("UICorner", {CornerRadius = UDim.new(0, 6)}, nil, sector)
      local outline = new("UIStroke", {Color = library.theme.stroke, Thickness = 1}, nil, sector)
      library:_track("strokes", outline, "Color")

      local sectorTitle = new("TextLabel", {
        Text = string.lower(title),
        Size = UDim2.new(1, -12, 0, 20),
        Position = UDim2.fromOffset(12, 8),
        BackgroundTransparency = 1,
        TextColor3 = library.theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
      }, nil, sector)
      library:_track("text", sectorTitle, "TextColor3")

      local container = new("Frame", {
        Name = "Container",
        Size = UDim2.new(1, -24, 0, 0),
        Position = UDim2.fromOffset(12, 32),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y
      }, nil, sector)

      local list = new("UIListLayout", {
        Padding = UDim.new(0, 8),
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder
      }, nil, container)

      -- Control builders

      local function makeRow(height)
        local row = new("Frame", {
          Size = UDim2.new(1, 0, 0, height or 28),
          BackgroundTransparency = 1
        }, nil, container)
        return row
      end

      local function makeLabel(text)
        local row = makeRow(20)
        local lbl = new("TextLabel", {
          Text = text,
          Size = UDim2.new(1, 0, 1, 0),
          BackgroundTransparency = 1,
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextXAlignment = Enum.TextXAlignment.Left
        }, nil, row)
        library:_track("text", lbl, "TextColor3")
      end

      local function registerSetter(flag, setter)
        if not flag then return end
        library._setters[flag] = setter
      end

      local Sector = {}

      function Sector:AddLabel(text)
        makeLabel(text)
      end

      -- Toggle
      function Sector:AddToggle(name, default, arg3, arg4)
        local flag, callback
        if typeof(arg3) == "string" then
          flag = arg3; callback = arg4
        elseif typeof(arg3) == "function" then
          callback = arg3
        end

        local row = makeRow(28)
        local btn = new("TextButton", {
          Size = UDim2.new(0, 22, 0, 22),
          Position = UDim2.fromOffset(0, 3),
          BackgroundColor3 = Color3.fromRGB(35,35,35),
          AutoButtonColor = false,
          Text = ""
        }, nil, row)
        new("UICorner", {CornerRadius = UDim.new(0, 4)}, nil, btn)
        local tick = new("Frame", {
          Size = UDim2.fromScale(default and 1 or 0, 1),
          BackgroundColor3 = library.theme.accentcolor,
          BorderSizePixel = 0
        }, nil, btn)
        library:_track("accents", tick, "BackgroundColor3")

        local lbl = new("TextLabel", {
          Size = UDim2.new(1, -26, 1, 0),
          Position = UDim2.fromOffset(26, 0),
          BackgroundTransparency = 1,
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextXAlignment = Enum.TextXAlignment.Left,
          Text = string.lower(name)
        }, nil, row)
        library:_track("text", lbl, "TextColor3")

        local state = not not default
        if flag then library.flags[flag] = state end
        local function set(v, silent)
          state = not not v
          tick.Size = UDim2.fromScale(state and 1 or 0, 1)
          if flag then library.flags[flag] = state end
          if callback and not silent then callback(state) end
        end
        btn.MouseButton1Click:Connect(function() set(not state) end)

        registerSetter(flag, set)

        local ToggleObject = {}
        function ToggleObject:Get() return state end
        function ToggleObject:Set(v) set(v) end

        -- inline colorpicker under the toggle
        function ToggleObject:AddColorpicker(defaultColor, cpCallback)
          local rowCP = makeRow(28)
          local swatch = new("TextButton", {
            Size = UDim2.fromOffset(22, 22),
            Position = UDim2.fromOffset(0, 3),
            BackgroundColor3 = defaultColor or Color3.fromRGB(255,255,255),
            AutoButtonColor = false,
            Text = ""
          }, nil, rowCP)
          new("UICorner", {CornerRadius = UDim.new(0, 4)}, nil, swatch)
          local label = new("TextLabel", {
            Size = UDim2.new(1, -126, 1, 0),
            Position = UDim2.fromOffset(26, 0),
            BackgroundTransparency = 1,
            Text = "color",
            TextColor3 = library.theme.text,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
          }, nil, rowCP)
          library:_track("text", label, "TextColor3")

          -- simple RGB sliders popup
          local popup = new("Frame", {
            Size = UDim2.fromOffset(220, 110),
            Position = UDim2.fromOffset(26, 26),
            BackgroundColor3 = library.theme.background,
            BorderSizePixel = 0,
            Visible = false
          }, nil, rowCP)
          library:_track("backgrounds", popup, "BackgroundColor3")
          new("UICorner", {CornerRadius = UDim.new(0, 6)}, nil, popup)
          new("UIStroke", {Color = library.theme.stroke, Thickness = 1}, nil, popup)

          local function sliderRow(y, labelText, initial, cb)
            local r = new("Frame", {Size=UDim2.new(1,-12,0,24), Position=UDim2.fromOffset(6,y), BackgroundTransparency=1}, nil, popup)
            local t = new("TextLabel", {Text=labelText, Size=UDim2.fromOffset(30,24), BackgroundTransparency=1, TextColor3=library.theme.text, Font=Enum.Font.Gotham, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left}, nil, r)
            library:_track("text", t, "TextColor3")
            local bar = new("Frame", {Size=UDim2.new(1,-40,0,6), Position=UDim2.fromOffset(36,9), BackgroundColor3=Color3.fromRGB(40,40,40), BorderSizePixel=0}, nil, r)
            new("UICorner", {CornerRadius = UDim.new(1,0)}, nil, bar)
            local fill = new("Frame", {Size=UDim2.fromScale((initial/255),1), BackgroundColor3=library.theme.accentcolor, BorderSizePixel=0}, nil, bar)
            library:_track("accents", fill, "BackgroundColor3")
            local value = initial
            local dragging = false
            bar.InputBegan:Connect(function(i)
              if i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                local x = (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
                x = math.clamp(x, 0, 1)
                value = math.floor(x*255 + 0.5)
                fill.Size = UDim2.fromScale(x, 1)
                cb(value)
              end
            end)
            bar.InputChanged:Connect(function(i)
              if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                local x = (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
                x = math.clamp(x, 0, 1)
                value = math.floor(x*255 + 0.5)
                fill.Size = UDim2.fromScale(x, 1)
                cb(value)
              end
            end)
            UserInputService.InputEnded:Connect(function(i)
              if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
            end)
            return { set = function(v) value = v; fill.Size = UDim2.fromScale((v/255),1) end }
          end

          local col = swatch.BackgroundColor3
          local rS = sliderRow(6,  "R", math.floor(col.R*255+0.5), function(v)
            col = Color3.fromRGB(v, math.floor(col.G*255+0.5), math.floor(col.B*255+0.5))
            swatch.BackgroundColor3 = col; if cpCallback then cpCallback(col) end
          end)
          local gS = sliderRow(38, "G", math.floor(col.G*255+0.5), function(v)
            col = Color3.fromRGB(math.floor(col.R*255+0.5), v, math.floor(col.B*255+0.5))
            swatch.BackgroundColor3 = col; if cpCallback then cpCallback(col) end
          end)
          local bS = sliderRow(70, "B", math.floor(col.B*255+0.5), function(v)
            col = Color3.fromRGB(math.floor(col.R*255+0.5), math.floor(col.G*255+0.5), v)
            swatch.BackgroundColor3 = col; if cpCallback then cpCallback(col) end
          end)

          swatch.MouseButton1Click:Connect(function()
            popup.Visible = not popup.Visible
          end)

          return {
            Set = function(c)
              col = c
              swatch.BackgroundColor3 = col
              rS.set(math.floor(col.R*255+0.5))
              gS.set(math.floor(col.G*255+0.5))
              bS.set(math.floor(col.B*255+0.5))
              if cpCallback then cpCallback(col) end
            end,
            Get = function() return col end
          }
        end

        return ToggleObject
      end

      -- Slider
      function Sector:AddSlider(name, min, default, max, step, callback)
        min, max, step = tonumber(min) or 0, tonumber(max) or 100, tonumber(step) or 1
        local value = tonumber(default) or min

        local row = makeRow(38)
        local nameLbl = new("TextLabel", {
          Size = UDim2.new(1, 0, 0, 18),
          BackgroundTransparency = 1,
          Text = string.lower(name).."  ("..tostring(value)..")",
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextXAlignment = Enum.TextXAlignment.Left
        }, nil, row)
        library:_track("text", nameLbl, "TextColor3")

        local bar = new("Frame", {
          Size = UDim2.new(1, 0, 0, 6),
          Position = UDim2.fromOffset(0, 22),
          BackgroundColor3 = Color3.fromRGB(40,40,40),
          BorderSizePixel = 0
        }, nil, row)
        new("UICorner", {CornerRadius = UDim.new(1,0)}, nil, bar)

        local fill = new("Frame", {
          Size = UDim2.fromScale((value-min)/(max-min), 1),
          BackgroundColor3 = library.theme.accentcolor,
          BorderSizePixel = 0
        }, nil, bar)
        library:_track("accents", fill, "BackgroundColor3")

        local dragging = false
        local function set(val, silent)
          val = math.clamp(val, min, max)
          val = roundToStep(val, step)
          value = val
          local pct = (value-min) / (max-min)
          fill.Size = UDim2.fromScale(pct, 1)
          nameLbl.Text = string.lower(name).."  ("..tostring(value)..")"
          if callback and not silent then callback(value) end
        end

        bar.InputBegan:Connect(function(i)
          if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            local x = (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
            set(min + x*(max-min))
          end
        end)
        bar.InputChanged:Connect(function(i)
          if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local x = (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
            set(min + x*(max-min))
          end
        end)
        UserInputService.InputEnded:Connect(function(i)
          if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)

        return { Set=set, Get=function() return value end }
      end

      -- Keybind
      function Sector:AddKeybind(name, defaultKey, toggleMode, flag, callback)
        local row = makeRow(28)
        local lbl = new("TextLabel", {
          Size = UDim2.new(1, -100, 1, 0),
          BackgroundTransparency = 1,
          Text = string.lower(name),
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextXAlignment = Enum.TextXAlignment.Left
        }, nil, row)
        library:_track("text", lbl, "TextColor3")

        local btn = new("TextButton", {
          Size = UDim2.fromOffset(90, 22),
          Position = UDim2.new(1, -90, 0, 3),
          BackgroundColor3 = Color3.fromRGB(35,35,35),
          AutoButtonColor = false,
          Text = defaultKey and defaultKey.Name or "NONE",
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextColor3 = library.theme.text
        }, nil, row)
        library:_track("text", btn, "TextColor3")
        new("UICorner", {CornerRadius = UDim.new(0, 4)}, nil, btn)

        local capture = false
        local current = defaultKey or Enum.KeyCode.Unknown
        if flag then library.flags[flag] = current end

        btn.MouseButton1Click:Connect(function()
          btn.Text = "..."
          capture = true
        end)

        UserInputService.InputBegan:Connect(function(input, gpe)
          if capture and input.UserInputType == Enum.UserInputType.Keyboard then
            current = input.KeyCode
            btn.Text = current.Name
            capture = false
            if flag then library.flags[flag] = current end
            if callback then callback(current) end
          end
        end)

        -- toggle mode: pressing key toggles flag on/off
        local toggleState = false
        if toggleMode and flag then
          library.flags[flag] = false
          UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == current then
              toggleState = not toggleState
              library.flags[flag] = toggleState
              if callback then callback(current) end
            end
          end)
        end

        local function setKey(key, silent)
          current = key or Enum.KeyCode.Unknown
          btn.Text = current.Name
          if flag then library.flags[flag] = current end
          if callback and not silent then callback(current) end
        end
        library._setters[flag or ("__key_"..name)] = setKey

        return { Set = setKey, Get = function() return current end }
      end

      -- Dropdown (single/multi)
      function Sector:AddDropdown(name, list, default, isMulti, callback)
        list = list or {}
        local row = makeRow(28 + 6)
        local lbl = new("TextLabel", {
          Size = UDim2.new(1, -110, 1, 0),
          BackgroundTransparency = 1,
          Text = string.lower(name),
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextXAlignment = Enum.TextXAlignment.Left
        }, nil, row)
        library:_track("text", lbl, "TextColor3")

        local btn = new("TextButton", {
          Size = UDim2.fromOffset(100, 22),
          Position = UDim2.new(1, -100, 0, 3),
          BackgroundColor3 = Color3.fromRGB(35,35,35),
          AutoButtonColor = false,
          Text = (isMulti and "0 selected") or tostring(default or list[1] or "-"),
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextColor3 = library.theme.text
        }, nil, row)
        library:_track("text", btn, "TextColor3")
        new("UICorner", {CornerRadius = UDim.new(0, 4)}, nil, btn)

        local popup = new("Frame", {
          Size = UDim2.fromOffset(180, math.clamp(#list*22 + 8, 36, 200)),
          Position = UDim2.new(1, -100-180-6, 0, 28),
          BackgroundColor3 = library.theme.background,
          BorderSizePixel = 0,
          Visible = false
        }, nil, row)
        library:_track("backgrounds", popup, "BackgroundColor3")
        new("UICorner", {CornerRadius = UDim.new(0, 6)}, nil, popup)
        new("UIStroke", {Color = library.theme.stroke, Thickness = 1}, nil, popup)
        local scroller = new("ScrollingFrame", {
          Size = UDim2.new(1, 0, 1, -8),
          Position = UDim2.fromOffset(0, 4),
          BackgroundTransparency = 1,
          ScrollBarThickness = 4,
          CanvasSize = UDim2.fromOffset(0, (#list*22))
        }, nil, popup)
        local lay = new("UIListLayout", {Padding=UDim.new(0,4)}, nil, scroller)

        local selected
        if isMulti then selected = {} else selected = default or list[1] end

        local function recomputeText()
          if isMulti then
            local n=0 for _,v in pairs(selected) do if v then n=n+1 end end
            btn.Text = tostring(n).." selected"
          else
            btn.Text = tostring(selected or "-")
          end
          if callback then
            callback(isMulti and selected or selected)
          end
        end

        for _,opt in ipairs(list) do
          local item = new("TextButton", {
            Size = UDim2.new(1, -8, 0, 22),
            Position = UDim2.fromOffset(4, 0),
            BackgroundColor3 = Color3.fromRGB(35,35,35),
            Text = tostring(opt),
            AutoButtonColor = false,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = library.theme.text
          }, nil, scroller)
          library:_track("text", item, "TextColor3")
          new("UICorner", {CornerRadius = UDim.new(0,4)}, nil, item)
          item.MouseButton1Click:Connect(function()
            if isMulti then
              selected[opt] = not selected[opt]
              item.BackgroundColor3 = selected[opt] and library.theme.accentcolor or Color3.fromRGB(35,35,35)
              recomputeText()
            else
              selected = opt
              recomputeText()
              popup.Visible = false
            end
          end)
        end

        btn.MouseButton1Click:Connect(function()
          popup.Visible = not popup.Visible
        end)

        recomputeText()
        return {
          Get = function() return selected end,
          Set = function(v)
            if isMulti and type(v)=="table" then
              selected = {}
              for k,val in pairs(v) do selected[k] = val and true or nil end
            else
              selected = v
            end
            recomputeText()
          end
        }
      end

      -- Sector-level colorpicker (e.g., theme controls)
      function Sector:AddColorpicker(name, defaultColor, callback)
        local row = makeRow(28)
        local lbl = new("TextLabel", {
          Size = UDim2.new(1, -100, 1, 0),
          BackgroundTransparency = 1,
          Text = string.lower(name),
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12,
          TextXAlignment = Enum.TextXAlignment.Left
        }, nil, row)
        library:_track("text", lbl, "TextColor3")

        local swatch = new("TextButton", {
          Size = UDim2.fromOffset(90, 22),
          Position = UDim2.new(1, -90, 0, 3),
          BackgroundColor3 = defaultColor or Color3.fromRGB(255,255,255),
          AutoButtonColor = false,
          Text = "",
        }, nil, row)
        new("UICorner", {CornerRadius = UDim.new(0, 4)}, nil, swatch)

        local cp = {}
        local function makeCP()
          local popup = new("Frame", {
            Size = UDim2.fromOffset(220, 110),
            Position = UDim2.fromOffset(row.AbsoluteSize.X-220, 26),
            BackgroundColor3 = library.theme.background,
            BorderSizePixel = 0,
            Visible = false
          }, nil, row)
          library:_track("backgrounds", popup, "BackgroundColor3")
          new("UICorner", {CornerRadius = UDim.new(0, 6)}, nil, popup)
          new("UIStroke", {Color = library.theme.stroke, Thickness = 1}, nil, popup)

          local col = swatch.BackgroundColor3
          local function cRow(y, labelText, initial, onv)
            local r = new("Frame", {Size=UDim2.new(1,-12,0,24), Position=UDim2.fromOffset(6,y), BackgroundTransparency=1}, nil, popup)
            local t = new("TextLabel", {Text=labelText, Size=UDim2.fromOffset(30,24), BackgroundTransparency=1, TextColor3=library.theme.text, Font=Enum.Font.Gotham, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left}, nil, r)
            library:_track("text", t, "TextColor3")
            local bar = new("Frame", {Size=UDim2.new(1,-40,0,6), Position=UDim2.fromOffset(36,9), BackgroundColor3=Color3.fromRGB(40,40,40), BorderSizePixel=0}, nil, r)
            new("UICorner", {CornerRadius = UDim.new(1,0)}, nil, bar)
            local fill = new("Frame", {Size=UDim2.fromScale((initial/255),1), BackgroundColor3=library.theme.accentcolor, BorderSizePixel=0}, nil, bar)
            library:_track("accents", fill, "BackgroundColor3")
            local dragging=false
            bar.InputBegan:Connect(function(i)
              if i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging=true
                local x=(i.Position.X-bar.AbsolutePosition.X)/bar.AbsoluteSize.X
                x=math.clamp(x,0,1)
                local v=math.floor(x*255+0.5); fill.Size=UDim2.fromScale(x,1); onv(v)
              end
            end)
            bar.InputChanged:Connect(function(i)
              if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
                local x=(i.Position.X-bar.AbsolutePosition.X)/bar.AbsoluteSize.X
                x=math.clamp(x,0,1)
                local v=math.floor(x*255+0.5); fill.Size=UDim2.fromScale(x,1); onv(v)
              end
            end)
            UserInputService.InputEnded:Connect(function(i)
              if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
            end)
            return { set = function(v) fill.Size = UDim2.fromScale((v/255),1) end }
          end
          local r0 = math.floor(col.R*255+0.5)
          local g0 = math.floor(col.G*255+0.5)
          local b0 = math.floor(col.B*255+0.5)
          local R = cRow(6, "R", r0, function(v) col = Color3.fromRGB(v, math.floor(col.G*255+0.5), math.floor(col.B*255+0.5)); swatch.BackgroundColor3 = col; if callback then callback(col) end end)
          local G = cRow(38,"G", g0, function(v) col = Color3.fromRGB(math.floor(col.R*255+0.5), v, math.floor(col.B*255+0.5)); swatch.BackgroundColor3 = col; if callback then callback(col) end end)
          local B = cRow(70,"B", b0, function(v) col = Color3.fromRGB(math.floor(col.R*255+0.5), math.floor(col.G*255+0.5), v); swatch.BackgroundColor3 = col; if callback then callback(col) end end)

          cp._popup = popup
          cp._set = function(c)
            col = c
            swatch.BackgroundColor3 = col
            R.set(math.floor(col.R*255+0.5))
            G.set(math.floor(col.G*255+0.5))
            B.set(math.floor(col.B*255+0.5))
            if callback then callback(col) end
          end
        end
        makeCP()

        swatch.MouseButton1Click:Connect(function()
          cp._popup.Visible = not cp._popup.Visible
        end)

        return {
          Set = function(c) cp._set(c) end,
          Get = function() return swatch.BackgroundColor3 end
        }
      end

      -- Config System (sector automatically built)
      function Tab:CreateConfigSystem(side)
        local sectorX = self:CreateSector("configs", side or "right")
        local host = sectorX -- sector frame
        -- build a little UI
        local rowName = new("Frame", {Size=UDim2.new(1,0,0,28), BackgroundTransparency=1}, nil, host.Container)
        local nameBox = new("TextBox", {
          PlaceholderText="config name",
          Text = "",
          Size = UDim2.new(1, -210, 1, -6),
          Position = UDim2.fromOffset(0,3),
          BackgroundColor3 = Color3.fromRGB(35,35,35),
          TextColor3 = library.theme.text,
          Font = Enum.Font.Gotham,
          TextSize = 12
        }, nil, rowName)
        library:_track("text", nameBox, "TextColor3")
        new("UICorner", {CornerRadius = UDim.new(0,4)}, nil, nameBox)

        local btnSave = new("TextButton", {
          Text="Save", Size=UDim2.fromOffset(60,22), Position=UDim2.new(1,-200,0,3),
          BackgroundColor3=library.theme.accentcolor, TextColor3=Color3.new(1,1,1),
          AutoButtonColor=false, Font=Enum.Font.Gotham, TextSize=12
        }, nil, rowName)
        library:_track("accents", btnSave, "BackgroundColor3")
        new("UICorner", {CornerRadius = UDim.new(0,4)}, nil, btnSave)

        local btnLoad = new("TextButton", {
          Text="Load", Size=UDim2.fromOffset(60,22), Position=UDim2.new(1,-135,0,3),
          BackgroundColor3=library.theme.accentcolor, TextColor3=Color3.new(1,1,1),
          AutoButtonColor=false, Font=Enum.Font.Gotham, TextSize=12
        }, nil, rowName)
        library:_track("accents", btnLoad, "BackgroundColor3")
        new("UICorner", {CornerRadius = UDim.new(0,4)}, nil, btnLoad)

        local btnDelete = new("TextButton", {
          Text="Delete", Size=UDim2.fromOffset(60,22), Position=UDim2.new(1,-70,0,3),
          BackgroundColor3=library.theme.accentcolor, TextColor3=Color3.new(1,1,1),
          AutoButtonColor=false, Font=Enum.Font.Gotham, TextSize=12
        }, nil, rowName)
        library:_track("accents", btnDelete, "BackgroundColor3")
        new("UICorner", {CornerRadius = UDim.new(0,4)}, nil, btnDelete)

        local rowList = new("Frame", {Size=UDim2.new(1,0,0,130), BackgroundTransparency=1}, nil, host.Container)
        local listFrame = new("ScrollingFrame", {
          Size=UDim2.new(1,0,1,0),
          CanvasSize=UDim2.new(0,0,0,0),
          ScrollBarThickness=4,
          BackgroundTransparency=1
        }, nil, rowList)
        local listLayout = new("UIListLayout", {Padding=UDim.new(0,4)}, nil, listFrame)

        local currentPick = nil
        local function refreshList()
          for _,child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
          end
          local items = library:ListConfigs()
          local total = 0
          for _,nm in ipairs(items) do
            local b = new("TextButton", {
              Size=UDim2.new(1,-4,0,22), Position=UDim2.fromOffset(2,0),
              BackgroundColor3 = Color3.fromRGB(35,35,35),
              Text = nm,
              Font=Enum.Font.Gotham, TextSize=12, TextColor3=library.theme.text,
              AutoButtonColor=false
            }, nil, listFrame)
            library:_track("text", b, "TextColor3")
            new("UICorner", {CornerRadius = UDim.new(0,4)}, nil, b)
            b.MouseButton1Click:Connect(function()
              currentPick = nm
              nameBox.Text = nm
            end)
            total = total + 22 + 4
          end
          listFrame.CanvasSize = UDim2.fromOffset(0, math.max(0,total))
        end
        refreshList()

        btnSave.MouseButton1Click:Connect(function()
          local n = string.gsub(nameBox.Text or "", "[^%w%-_ ]", "")
          if n == "" then return end
          library:SaveConfig(n)
          refreshList()
        end)
        btnLoad.MouseButton1Click:Connect(function()
          local n = nameBox.Text ~= "" and nameBox.Text or currentPick
          if n then library:LoadConfig(n) end
        end)
        btnDelete.MouseButton1Click:Connect(function()
          local n = nameBox.Text ~= "" and nameBox.Text or currentPick
          if n then library:DeleteConfig(n) refreshList() end
        end)

        return sectorX
      end

      return Sector
    end

    -- Auto select the first tab created
    if not Window._active then
      Window:_switch(name)
    end

    return Tab
  end

  -- expose to library
  library._window = Window
  return Window
end

-- // Expose manual theme update (if user changes library.theme values)
function library:ApplyTheme()
  self:_applyTheme()
end

return library
