-- TurtleColorPicker UI
-- WoW 1.12 / Lua 5.0

TurtleColorPicker_UI = {}

local TCP = TurtleColorPicker
local HSVtoRGB = TCP.HSVtoRGB
local RGBtoHSV = TCP.RGBtoHSV
local RGBtoHex = TCP.RGBtoHex
local HexToRGB = TCP.HexToRGB
local Clamp = TCP.Clamp

-- ============================================================
-- CONSTANTS
-- ============================================================

local SV_SIZE = 150
local HUE_WIDTH = 20
local HUE_HEIGHT = SV_SIZE
local HUE_GAP = 8
local PADDING = 10
local SWATCH_HEIGHT = 24
local BTN_WIDTH = 80
local BTN_HEIGHT = 22

local FRAME_WIDTH = PADDING + SV_SIZE + HUE_GAP + HUE_WIDTH + PADDING  -- 198
local MIN_FRAME_WIDTH = 210

-- Ensure minimum width for buttons/hex
if FRAME_WIDTH < MIN_FRAME_WIDTH then
    FRAME_WIDTH = MIN_FRAME_WIDTH
end

local HUE_COLORS = {
    {1, 0, 0},  -- 0°   Red
    {1, 1, 0},  -- 60°  Yellow
    {0, 1, 0},  -- 120° Green
    {0, 1, 1},  -- 180° Cyan
    {0, 0, 1},  -- 240° Blue
    {1, 0, 1},  -- 300° Magenta
    {1, 0, 0},  -- 360° Red (wrap)
}

-- ============================================================
-- STATE
-- ============================================================

local initialized = false
local session = nil

-- Frames (created once)
local mainFrame
local svFrame, svBase, svWhite, svBlack, svCursor
local hueFrame, hueCursor
local oldSwatch, newSwatch, previewBorder
local hexContainer, hexLabel, hexEditBox
local alphaContainer, alphaSlider, alphaLabel, alphaValText
local okBtn, cancelBtn

local draggingSV = false
local draggingHue = false

-- ============================================================
-- CURSOR DRAWING (simple crosshair via textures)
-- ============================================================

local function CreateCrosshairCursor(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(size)
    f:SetHeight(size)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)

    local half = size / 2
    local thick = 1
    local len = half - 1

    -- Horizontal line (left half)
    local hl = f:CreateTexture(nil, "OVERLAY")
    hl:SetWidth(len)
    hl:SetHeight(thick)
    hl:SetPoint("RIGHT", f, "CENTER", -2, 0)
    hl:SetTexture(1, 1, 1, 0.9)

    -- Horizontal line (right half)
    local hr = f:CreateTexture(nil, "OVERLAY")
    hr:SetWidth(len)
    hr:SetHeight(thick)
    hr:SetPoint("LEFT", f, "CENTER", 2, 0)
    hr:SetTexture(1, 1, 1, 0.9)

    -- Vertical line (top half)
    local vt = f:CreateTexture(nil, "OVERLAY")
    vt:SetWidth(thick)
    vt:SetHeight(len)
    vt:SetPoint("BOTTOM", f, "CENTER", 0, 2)
    vt:SetTexture(1, 1, 1, 0.9)

    -- Vertical line (bottom half)
    local vb = f:CreateTexture(nil, "OVERLAY")
    vb:SetWidth(thick)
    vb:SetHeight(len)
    vb:SetPoint("TOP", f, "CENTER", 0, -2)
    vb:SetTexture(1, 1, 1, 0.9)

    -- Black outline (shadow lines for contrast)
    local shl = f:CreateTexture(nil, "ARTWORK")
    shl:SetWidth(len + 1)
    shl:SetHeight(thick + 2)
    shl:SetPoint("RIGHT", f, "CENTER", -1, 0)
    shl:SetTexture(0, 0, 0, 0.6)

    local shr = f:CreateTexture(nil, "ARTWORK")
    shr:SetWidth(len + 1)
    shr:SetHeight(thick + 2)
    shr:SetPoint("LEFT", f, "CENTER", 1, 0)
    shr:SetTexture(0, 0, 0, 0.6)

    local svt = f:CreateTexture(nil, "ARTWORK")
    svt:SetWidth(thick + 2)
    svt:SetHeight(len + 1)
    svt:SetPoint("BOTTOM", f, "CENTER", 0, 1)
    svt:SetTexture(0, 0, 0, 0.6)

    local svb = f:CreateTexture(nil, "ARTWORK")
    svb:SetWidth(thick + 2)
    svb:SetHeight(len + 1)
    svb:SetPoint("TOP", f, "CENTER", 0, -1)
    svb:SetTexture(0, 0, 0, 0.6)

    return f
end

-- ============================================================
-- UPDATE FUNCTIONS
-- ============================================================

local function UpdateColor()
    if not session then return end

    local r, g, b = HSVtoRGB(session.h, session.s, session.v)
    local a = session.alpha

    -- SV square base color = pure hue at full saturation/value
    local hr, hg, hb = HSVtoRGB(session.h, 1, 1)
    svBase:SetTexture(hr, hg, hb, 1)

    -- SV cursor position (S = left→right, V = bottom→top)
    svCursor:ClearAllPoints()
    svCursor:SetPoint("CENTER", svFrame, "BOTTOMLEFT", session.s * SV_SIZE, session.v * SV_SIZE)

    -- Hue cursor position (H = top→bottom)
    hueCursor:ClearAllPoints()
    hueCursor:SetPoint("CENTER", hueFrame, "TOPLEFT", HUE_WIDTH / 2, -(session.h * HUE_HEIGHT))

    -- New color swatch
    newSwatch:SetTexture(r, g, b, 1)

    -- Hex input (only update if not focused)
    if hexEditBox and hexEditBox:IsShown() then
        if not hexEditBox:HasFocus() then
            hexEditBox:SetText(RGBtoHex(r, g, b))
        end
    end

    -- Alpha slider value text
    if alphaValText and alphaSlider and alphaSlider:IsShown() then
        alphaValText:SetText(string.format("%d%%", math.floor(a * 100 + 0.5)))
    end

    -- Notify
    TCP:_NotifyChange()
end

local function UpdateSVFromMouse()
    if not session then return end
    local cx, cy = GetCursorPosition()
    local scale = svFrame:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale

    local left = svFrame:GetLeft()
    local bottom = svFrame:GetBottom()

    session.s = Clamp((cx - left) / SV_SIZE, 0, 1)
    session.v = Clamp((cy - bottom) / SV_SIZE, 0, 1)

    UpdateColor()
end

local function UpdateHueFromMouse()
    if not session then return end
    local cx, cy = GetCursorPosition()
    local scale = hueFrame:GetEffectiveScale()
    cy = cy / scale

    local top = hueFrame:GetTop()

    session.h = Clamp((top - cy) / HUE_HEIGHT, 0, 0.9999)

    UpdateColor()
end

-- ============================================================
-- LAYOUT
-- ============================================================

local function RecalcLayout()
    if not session then return end

    local hasHex = session.hasHexInput
    local hasAlpha = session.hasAlpha

    -- Content width inside padding
    local contentW = FRAME_WIDTH - PADDING * 2

    -- Vertical cursor: track current y offset from top of mainFrame
    local yOff = -PADDING

    -- SV Square + Hue Bar are fixed at top
    -- (anchored in Init, no need to re-anchor)
    yOff = yOff - SV_SIZE

    -- Preview swatches
    yOff = yOff - 8
    previewBorder:ClearAllPoints()
    previewBorder:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PADDING, yOff)
    previewBorder:SetWidth(contentW)
    previewBorder:Show()

    local swatchW = math.floor((contentW - 4) / 2)  -- -4 for gap
    oldSwatch:SetWidth(swatchW)
    newSwatch:SetWidth(swatchW)

    yOff = yOff - SWATCH_HEIGHT

    -- Hex input
    if hasHex then
        yOff = yOff - 8
        hexContainer:ClearAllPoints()
        hexContainer:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PADDING, yOff)
        hexContainer:SetWidth(contentW)
        hexContainer:Show()
        yOff = yOff - 24
    else
        hexContainer:Hide()
    end

    -- Alpha slider
    if hasAlpha then
        yOff = yOff - 8
        alphaContainer:ClearAllPoints()
        alphaContainer:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PADDING, yOff)
        alphaContainer:SetWidth(contentW)
        alphaContainer:Show()
        yOff = yOff - 36
    else
        alphaContainer:Hide()
    end

    -- Buttons
    yOff = yOff - 8
    okBtn:ClearAllPoints()
    cancelBtn:ClearAllPoints()
    local btnAreaW = BTN_WIDTH * 2 + 10
    local btnStartX = PADDING + math.floor((contentW - btnAreaW) / 2)
    okBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", btnStartX, yOff)
    cancelBtn:SetPoint("TOPLEFT", okBtn, "TOPRIGHT", 10, 0)
    yOff = yOff - BTN_HEIGHT

    -- Final frame height
    mainFrame:SetHeight(math.abs(yOff) + PADDING)
end

-- ============================================================
-- INITIALIZATION (called once, lazily)
-- ============================================================

local function Init()
    if initialized then return end
    initialized = true

    -- --------------------------------------------------------
    -- Main Frame
    -- --------------------------------------------------------
    mainFrame = CreateFrame("Frame", "TurtleColorPickerFrame", UIParent)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetWidth(FRAME_WIDTH)
    mainFrame:SetHeight(300)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    mainFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    mainFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    mainFrame:Hide()

    mainFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    -- ESC to close
    table.insert(UISpecialFrames, "TurtleColorPickerFrame")

    mainFrame:SetScript("OnHide", function()
        draggingSV = false
        draggingHue = false
        TCP:_NotifyCancel()
        session = nil
        TCP._session = nil
    end)

    -- --------------------------------------------------------
    -- SV Square
    -- --------------------------------------------------------
    svFrame = CreateFrame("Frame", nil, mainFrame)
    svFrame:SetWidth(SV_SIZE)
    svFrame:SetHeight(SV_SIZE)
    svFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PADDING, -PADDING)
    svFrame:EnableMouse(true)

    -- Layer 1: Solid hue color
    svBase = svFrame:CreateTexture(nil, "BACKGROUND")
    svBase:SetAllPoints(svFrame)
    svBase:SetTexture(1, 0, 0, 1)

    -- Layer 2: White→transparent gradient (left=white, right=transparent) = Saturation
    svWhite = svFrame:CreateTexture(nil, "BORDER")
    svWhite:SetAllPoints(svFrame)
    svWhite:SetTexture(1, 1, 1, 1)
    svWhite:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)

    -- Layer 3: Transparent→black gradient (top=transparent, bottom=black) = Value
    -- WoW VERTICAL: min = bottom, max = top
    svBlack = svFrame:CreateTexture(nil, "ARTWORK")
    svBlack:SetAllPoints(svFrame)
    svBlack:SetTexture(0, 0, 0, 1)
    svBlack:SetGradientAlpha("VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0)

    -- SV Border
    local svBorder = CreateFrame("Frame", nil, svFrame)
    svBorder:SetAllPoints(svFrame)
    svBorder:SetFrameLevel(svFrame:GetFrameLevel() + 3)
    svBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    svBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- SV Cursor (crosshair)
    svCursor = CreateCrosshairCursor(svFrame, 15)

    -- SV Mouse interaction
    svFrame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            draggingSV = true
            UpdateSVFromMouse()
        end
    end)
    svFrame:SetScript("OnMouseUp", function()
        draggingSV = false
    end)
    svFrame:SetScript("OnUpdate", function()
        if draggingSV then
            if not IsMouseButtonDown("LeftButton") then
                draggingSV = false
                return
            end
            UpdateSVFromMouse()
        end
    end)

    -- --------------------------------------------------------
    -- Hue Bar
    -- --------------------------------------------------------
    hueFrame = CreateFrame("Frame", nil, mainFrame)
    hueFrame:SetWidth(HUE_WIDTH)
    hueFrame:SetHeight(HUE_HEIGHT)
    hueFrame:SetPoint("TOPLEFT", svFrame, "TOPRIGHT", HUE_GAP, 0)
    hueFrame:EnableMouse(true)

    -- 6 gradient segments
    local segHeight = HUE_HEIGHT / 6
    for i = 1, 6 do
        local capturedI = i
        local seg = hueFrame:CreateTexture(nil, "ARTWORK")
        seg:SetWidth(HUE_WIDTH)
        seg:SetHeight(segHeight)
        seg:SetPoint("TOPLEFT", hueFrame, "TOPLEFT", 0, -(capturedI - 1) * segHeight)
        seg:SetTexture(1, 1, 1, 1)
        -- VERTICAL: min = bottom color, max = top color
        local top = HUE_COLORS[capturedI]
        local bot = HUE_COLORS[capturedI + 1]
        seg:SetGradient("VERTICAL", bot[1], bot[2], bot[3], top[1], top[2], top[3])
    end

    -- Hue Border
    local hueBorder = CreateFrame("Frame", nil, hueFrame)
    hueBorder:SetAllPoints(hueFrame)
    hueBorder:SetFrameLevel(hueFrame:GetFrameLevel() + 3)
    hueBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    hueBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- Hue Cursor (horizontal white bar with black outline)
    hueCursor = CreateFrame("Frame", nil, hueFrame)
    hueCursor:SetWidth(HUE_WIDTH + 6)
    hueCursor:SetHeight(7)
    hueCursor:SetFrameLevel(hueFrame:GetFrameLevel() + 5)

    local hcBg = hueCursor:CreateTexture(nil, "ARTWORK")
    hcBg:SetAllPoints(hueCursor)
    hcBg:SetTexture(0, 0, 0, 0.7)

    local hcInner = hueCursor:CreateTexture(nil, "OVERLAY")
    hcInner:SetPoint("TOPLEFT", hueCursor, "TOPLEFT", 1, -1)
    hcInner:SetPoint("BOTTOMRIGHT", hueCursor, "BOTTOMRIGHT", -1, 1)
    hcInner:SetTexture(1, 1, 1, 0.9)

    -- Hue Mouse interaction
    hueFrame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            draggingHue = true
            UpdateHueFromMouse()
        end
    end)
    hueFrame:SetScript("OnMouseUp", function()
        draggingHue = false
    end)
    hueFrame:SetScript("OnUpdate", function()
        if draggingHue then
            if not IsMouseButtonDown("LeftButton") then
                draggingHue = false
                return
            end
            UpdateHueFromMouse()
        end
    end)

    -- --------------------------------------------------------
    -- Color Preview Swatches
    -- --------------------------------------------------------
    previewBorder = CreateFrame("Frame", nil, mainFrame)
    previewBorder:SetHeight(SWATCH_HEIGHT)
    previewBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    previewBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- Old color (left)
    oldSwatch = previewBorder:CreateTexture(nil, "ARTWORK")
    oldSwatch:SetHeight(SWATCH_HEIGHT)
    oldSwatch:SetPoint("TOPLEFT", previewBorder, "TOPLEFT", 2, -2)
    oldSwatch:SetTexture(1, 1, 1, 1)

    -- "Old" label
    local oldLabel = previewBorder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oldLabel:SetPoint("CENTER", oldSwatch, "CENTER", 0, 0)
    oldLabel:SetText("Old")
    oldLabel:SetTextColor(0, 0, 0, 0.6)

    -- New color (right)
    newSwatch = previewBorder:CreateTexture(nil, "ARTWORK")
    newSwatch:SetHeight(SWATCH_HEIGHT)
    newSwatch:SetPoint("TOPRIGHT", previewBorder, "TOPRIGHT", -2, -2)
    newSwatch:SetTexture(1, 0, 0, 1)

    -- "New" label
    local newLabel = previewBorder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newLabel:SetPoint("CENTER", newSwatch, "CENTER", 0, 0)
    newLabel:SetText("New")
    newLabel:SetTextColor(0, 0, 0, 0.6)

    -- --------------------------------------------------------
    -- Hex Input (optional)
    -- --------------------------------------------------------
    hexContainer = CreateFrame("Frame", nil, mainFrame)
    hexContainer:SetHeight(24)
    hexContainer:Hide()

    hexLabel = hexContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hexLabel:SetPoint("LEFT", hexContainer, "LEFT", 0, 0)
    hexLabel:SetText("#")
    hexLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    hexEditBox = CreateFrame("EditBox", "TurtleColorPickerHexInput", hexContainer)
    hexEditBox:SetWidth(70)
    hexEditBox:SetHeight(20)
    hexEditBox:SetPoint("LEFT", hexLabel, "RIGHT", 4, 0)
    hexEditBox:SetFontObject(GameFontHighlightSmall)
    hexEditBox:SetAutoFocus(false)
    hexEditBox:SetMaxLetters(6)
    hexEditBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    hexEditBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    hexEditBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hexEditBox:SetTextInsets(4, 4, 0, 0)

    hexEditBox:SetScript("OnEnterPressed", function()
        if not session then return end
        local text = hexEditBox:GetText()
        local r, g, b = HexToRGB(text)
        if r then
            session.h, session.s, session.v = RGBtoHSV(r, g, b)
            UpdateColor()
        else
            -- Reset to current color
            local cr, cg, cb = HSVtoRGB(session.h, session.s, session.v)
            hexEditBox:SetText(RGBtoHex(cr, cg, cb))
        end
        hexEditBox:ClearFocus()
    end)

    hexEditBox:SetScript("OnEscapePressed", function()
        if not session then return end
        local r, g, b = HSVtoRGB(session.h, session.s, session.v)
        hexEditBox:SetText(RGBtoHex(r, g, b))
        hexEditBox:ClearFocus()
    end)

    -- Live hex preview: update when text is exactly 6 valid hex chars
    hexEditBox:SetScript("OnTextChanged", function()
        if not session then return end
        if not hexEditBox:HasFocus() then return end
        local text = hexEditBox:GetText()
        if string.len(text) == 6 then
            local r, g, b = HexToRGB(text)
            if r then
                session.h, session.s, session.v = RGBtoHSV(r, g, b)
                UpdateColor()
            end
        end
    end)

    -- --------------------------------------------------------
    -- Alpha Slider (optional)
    -- --------------------------------------------------------
    alphaContainer = CreateFrame("Frame", nil, mainFrame)
    alphaContainer:SetHeight(36)
    alphaContainer:Hide()

    alphaLabel = alphaContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alphaLabel:SetPoint("TOPLEFT", alphaContainer, "TOPLEFT", 0, 0)
    alphaLabel:SetText("Alpha")
    alphaLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local sliderName = "TurtleColorPickerAlphaSlider"
    alphaSlider = CreateFrame("Slider", sliderName, alphaContainer, "OptionsSliderTemplate")
    alphaSlider:SetWidth(130)
    alphaSlider:SetHeight(16)
    alphaSlider:SetPoint("TOPLEFT", alphaLabel, "BOTTOMLEFT", 0, -2)
    alphaSlider:SetMinMaxValues(0, 100)
    alphaSlider:SetValueStep(1)

    -- Hide default template labels
    local low = getglobal(sliderName .. "Low")
    local high = getglobal(sliderName .. "High")
    local text = getglobal(sliderName .. "Text")
    if low then low:Hide() end
    if high then high:Hide() end
    if text then text:Hide() end

    alphaValText = alphaSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alphaValText:SetPoint("LEFT", alphaSlider, "RIGHT", 8, 0)
    alphaValText:SetText("100%")

    alphaSlider:SetScript("OnValueChanged", function()
        if not session then return end
        local val = alphaSlider:GetValue()
        session.alpha = val / 100
        alphaValText:SetText(string.format("%d%%", val))
        -- Update swatch with alpha
        local r, g, b = HSVtoRGB(session.h, session.s, session.v)
        newSwatch:SetTexture(r, g, b, 1)
        TCP:_NotifyChange()
    end)

    -- --------------------------------------------------------
    -- OK / Cancel Buttons
    -- --------------------------------------------------------
    okBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    okBtn:SetWidth(BTN_WIDTH)
    okBtn:SetHeight(BTN_HEIGHT)
    okBtn:SetText("OK")
    okBtn:SetScript("OnClick", function()
        TCP:_NotifyOk()
    end)

    cancelBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(BTN_WIDTH)
    cancelBtn:SetHeight(BTN_HEIGHT)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        TCP:_NotifyCancel()
        mainFrame:Hide()
    end)
end

-- ============================================================
-- PUBLIC: Show / Hide
-- ============================================================

function TurtleColorPicker_UI:Show(sess)
    Init()
    session = sess

    -- Set old color swatch
    oldSwatch:SetTexture(sess.origR, sess.origG, sess.origB, 1)

    -- Set alpha slider
    if sess.hasAlpha then
        alphaSlider:SetValue(math.floor(sess.alpha * 100 + 0.5))
    end

    -- Set hex input
    if sess.hasHexInput then
        local r, g, b = HSVtoRGB(sess.h, sess.s, sess.v)
        hexEditBox:SetText(RGBtoHex(r, g, b))
        hexEditBox:ClearFocus()
    end

    -- Layout
    RecalcLayout()

    -- Initial color update
    UpdateColor()

    -- Show
    mainFrame:Show()
end

function TurtleColorPicker_UI:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end
