-- Ethos Calculator
-- A self-contained scientific calculator system tool.

local TOOL_NAME = "Calculator"
local TOOL_VERSION = "1.0.1"
local MAX_INPUT_LEN = 160
local MAX_PARSE_DEPTH = 48

local Math = math
local PI = (Math and Math.pi) or 3.14159265358979323846
local E = 2.71828182845904523536
local HUGE = (Math and Math.huge) or (1 / 0)

local FONT_SMALL = _G.FONT_XS or _G.FONT_S or 0
local FONT_MED = _G.FONT_S or _G.FONT_STD or 0
local FONT_BIG = _G.FONT_L or _G.FONT_XL or _G.FONT_STD or 0

local icon
if lcd and lcd.loadMask then
    local function loadIcon(path)
        local ok, loaded = pcall(lcd.loadMask, path)
        if ok then return loaded end
        return nil
    end

    icon = loadIcon("gfx/icon.png")
end

local input = "0"
local status = "Use ENTER long or = to evaluate"
local lastExpression = ""
local errorMessage = nil
local ans = 0
local memory = 0
local memorySet = false
local angleMode = "DEG"
local justEvaluated = false

local layoutW, layoutH = 0, 0
local displayH = 70
local buttonTop = 74
local buttonFields = {}
local colors = nil

local BUTTON_ROWS = {
    {{"AC", "clear"}, {"DEL", "backspace"}, {"(", "insert", "("}, {")", "insert", ")"}, {"D/R", "angle"}, {"ANS", "insert", "ans"}},
    {{"sin", "insert", "sin("}, {"cos", "insert", "cos("}, {"tan", "insert", "tan("}, {"asin", "insert", "asin("}, {"acos", "insert", "acos("}, {"atan", "insert", "atan("}},
    {{"ln", "insert", "ln("}, {"log", "insert", "log("}, {"sqrt", "insert", "sqrt("}, {"x^y", "insert", "^"}, {"pi", "insert", "pi"}, {"e", "insert", "e"}},
    {{"7", "insert", "7"}, {"8", "insert", "8"}, {"9", "insert", "9"}, {"/", "insert", "/"}, {"%", "insert", "%"}, {"!", "insert", "!"}},
    {{"4", "insert", "4"}, {"5", "insert", "5"}, {"6", "insert", "6"}, {"*", "insert", "*"}, {"M+", "memoryAdd"}, {"MR", "memoryRecall"}},
    {{"1", "insert", "1"}, {"2", "insert", "2"}, {"3", "insert", "3"}, {"-", "insert", "-"}, {"MS", "memoryStore"}, {"MC", "memoryClear"}},
    {{"0", "insert", "0"}, {".", "insert", "."}, {"+/-", "negate"}, {"+", "insert", "+"}, {"EE", "insert", "e"}, {"=", "equals"}}
}

local function invalidate()
    if lcd and lcd.invalidate then lcd.invalidate() end
end

local function fail(message)
    error(message, 0)
end

local function isFinite(value)
    return value == value and value ~= HUGE and value ~= -HUGE
end

local function checked(value, message)
    if type(value) ~= "number" then fail(message or "Expected a number") end
    value = value + 0.0
    if not isFinite(value) then fail(message or "Number out of range") end
    return value
end

local function trimError(message)
    local text = tostring(message or "Error")
    local short = text:match(":%d+:%s*(.+)$")
    return short or text
end

local function showError(message)
    errorMessage = message
    status = "Error: " .. message
    invalidate()
end

local function showEntryLimit()
    errorMessage = nil
    status = "Entry limit: " .. tostring(MAX_INPUT_LEN) .. " chars"
    invalidate()
end

local function formatNumber(value)
    if type(value) ~= "number" then return tostring(value or "") end
    if value ~= value then return "NaN" end
    if value == HUGE then return "Inf" end
    if value == -HUGE then return "-Inf" end
    if Math.abs(value) < 1e-12 then value = 0 end

    local absValue = Math.abs(value)
    local text
    if value ~= 0 and (absValue >= 1e10 or absValue < 1e-6) then
        text = string.format("%.12g", value)
    else
        text = string.format("%.10f", value)
        text = text:gsub("0+$", ""):gsub("%.$", "")
    end

    text = text:gsub("e%+0?", "e"):gsub("e%-0?", "e-")
    return text
end

local function mathFunction(name)
    local fn = Math and Math[name]
    if type(fn) ~= "function" then fail("math." .. name .. " is not available") end
    return fn
end

local function toRadians(value)
    if angleMode == "DEG" then return value * PI / 180 end
    return value
end

local function fromRadians(value)
    if angleMode == "DEG" then return value * 180 / PI end
    return value
end

local function factorial(value)
    local floor = mathFunction("floor")
    if value < 0 or floor(value) ~= value then fail("Factorial needs a non-negative integer") end
    if value > 170 then fail("Factorial too large") end

    local result = 1.0
    for n = 2, value do
        result = checked(result * n, "Factorial too large")
    end
    return result
end

local function tokenize(expression)
    local tokens = {}
    local i, len = 1, #expression

    local function push(kind, value, text)
        tokens[#tokens + 1] = {kind = kind, value = value, text = text or tostring(value)}
    end

    while i <= len do
        local ch = expression:sub(i, i)

        if ch:match("%s") then
            i = i + 1
        elseif ch:match("[%d.]") then
            local start = i
            local sawDigit = false
            local sawDot = false

            while i <= len do
                local c = expression:sub(i, i)
                if c:match("%d") then
                    sawDigit = true
                    i = i + 1
                elseif c == "." and not sawDot then
                    sawDot = true
                    i = i + 1
                else
                    break
                end
            end

            local c = expression:sub(i, i)
            local n1 = expression:sub(i + 1, i + 1)
            local n2 = expression:sub(i + 2, i + 2)
            if (c == "e" or c == "E") and (n1:match("%d") or ((n1 == "+" or n1 == "-") and n2:match("%d"))) then
                i = i + 1
                if expression:sub(i, i) == "+" or expression:sub(i, i) == "-" then i = i + 1 end
                while i <= len and expression:sub(i, i):match("%d") do
                    i = i + 1
                end
            end

            local text = expression:sub(start, i - 1)
            local value = tonumber(text)
            if not sawDigit or not value then fail("Bad number: " .. text) end
            push("number", checked(value, "Number out of range"), text)
        elseif ch:match("[%a_]") then
            local start = i
            while i <= len and expression:sub(i, i):match("[%w_]") do
                i = i + 1
            end
            local text = expression:sub(start, i - 1):lower()
            push("ident", text, text)
        elseif ch == "," then
            push("comma", ch, ch)
            i = i + 1
        elseif ch == "(" or ch == ")" or ch == "+" or ch == "-" or ch == "*" or ch == "/" or ch == "^" or ch == "%" or ch == "!" then
            push("symbol", ch, ch)
            i = i + 1
        else
            fail("Unexpected character: " .. ch)
        end
    end

    push("eof", "eof", "")
    return tokens
end

local function callFunction(name, args)
    local function need(count)
        if #args ~= count then fail(name .. " needs " .. tostring(count) .. " argument(s)") end
    end

    local function atLeast(count)
        if #args < count then fail(name .. " needs at least " .. tostring(count) .. " argument(s)") end
    end

    if name == "sin" then
        need(1)
        return mathFunction("sin")(toRadians(args[1]))
    elseif name == "cos" then
        need(1)
        return mathFunction("cos")(toRadians(args[1]))
    elseif name == "tan" then
        need(1)
        local value = toRadians(args[1])
        local tan = Math and Math.tan
        if type(tan) == "function" then return tan(value) end
        return mathFunction("sin")(value) / mathFunction("cos")(value)
    elseif name == "asin" then
        need(1)
        return fromRadians(mathFunction("asin")(args[1]))
    elseif name == "acos" then
        need(1)
        return fromRadians(mathFunction("acos")(args[1]))
    elseif name == "atan" then
        if #args == 1 then
            return fromRadians(mathFunction("atan")(args[1]))
        elseif #args == 2 then
            local atan2 = Math.atan2
            if type(atan2) == "function" then return fromRadians(atan2(args[1], args[2])) end
            return fromRadians(mathFunction("atan")(args[1] / args[2]))
        end
        fail("atan needs 1 or 2 argument(s)")
    elseif name == "sqrt" then
        need(1)
        if args[1] < 0 then fail("sqrt needs a non-negative value") end
        return mathFunction("sqrt")(args[1])
    elseif name == "cbrt" then
        need(1)
        if args[1] < 0 then return -((-args[1]) ^ (1 / 3)) end
        return args[1] ^ (1 / 3)
    elseif name == "ln" then
        need(1)
        if args[1] <= 0 then fail("ln needs a positive value") end
        return mathFunction("log")(args[1])
    elseif name == "log" or name == "log10" then
        need(1)
        if args[1] <= 0 then fail("log needs a positive value") end
        return mathFunction("log")(args[1]) / mathFunction("log")(10)
    elseif name == "exp" then
        need(1)
        return mathFunction("exp")(args[1])
    elseif name == "abs" then
        need(1)
        return mathFunction("abs")(args[1])
    elseif name == "floor" then
        need(1)
        return mathFunction("floor")(args[1])
    elseif name == "ceil" then
        need(1)
        return mathFunction("ceil")(args[1])
    elseif name == "round" then
        need(1)
        local floor = mathFunction("floor")
        if args[1] >= 0 then return floor(args[1] + 0.5) end
        return -floor(-args[1] + 0.5)
    elseif name == "pow" then
        need(2)
        return args[1] ^ args[2]
    elseif name == "mod" then
        need(2)
        if args[2] == 0 then fail("Modulo by zero") end
        return args[1] % args[2]
    elseif name == "min" then
        atLeast(1)
        local result = args[1]
        for i = 2, #args do
            if args[i] < result then result = args[i] end
        end
        return result
    elseif name == "max" then
        atLeast(1)
        local result = args[1]
        for i = 2, #args do
            if args[i] > result then result = args[i] end
        end
        return result
    elseif name == "deg" then
        need(1)
        return args[1] * 180 / PI
    elseif name == "rad" then
        need(1)
        return args[1] * PI / 180
    elseif name == "rand" then
        if #args == 0 then return Math.random() end
        if #args == 1 then return Math.random(args[1]) end
        if #args == 2 then return Math.random(args[1], args[2]) end
        fail("rand needs 0, 1, or 2 argument(s)")
    end

    fail("Unknown function: " .. name)
end

local function evaluateExpression(expression)
    local tokens = tokenize(expression)
    local pos = 1
    local depth = 0

    local parseExpression
    local parseAddSub
    local parseMulDiv
    local parseUnary
    local parsePower
    local parsePostfix
    local parsePrimary

    local function peek()
        return tokens[pos]
    end

    local function acceptSymbol(symbol)
        local token = peek()
        if token.kind == "symbol" and token.value == symbol then
            pos = pos + 1
            return true
        end
        return false
    end

    local function acceptComma()
        if peek().kind == "comma" then
            pos = pos + 1
            return true
        end
        return false
    end

    local function expectSymbol(symbol)
        if not acceptSymbol(symbol) then fail("Expected " .. symbol) end
    end

    local function startsFactor(token)
        return token.kind == "number" or token.kind == "ident" or (token.kind == "symbol" and token.value == "(")
    end

    local function constantValue(name)
        if name == "pi" then return PI end
        if name == "e" then return E end
        if name == "ans" then return ans end
        if name == "m" or name == "mem" then return memory end
        return nil
    end

    parseExpression = function()
        depth = depth + 1
        if depth > MAX_PARSE_DEPTH then fail("Expression too deeply nested") end
        local value = parseAddSub()
        depth = depth - 1
        return checked(value, "Result out of range")
    end

    parseAddSub = function()
        local value = parseMulDiv()

        while true do
            if acceptSymbol("+") then
                value = checked(value + parseMulDiv(), "Result out of range")
            elseif acceptSymbol("-") then
                value = checked(value - parseMulDiv(), "Result out of range")
            else
                return value
            end
        end
    end

    parseMulDiv = function()
        local value = parseUnary()

        while true do
            if acceptSymbol("*") then
                value = checked(value * parseUnary(), "Result out of range")
            elseif acceptSymbol("/") then
                local rhs = parseUnary()
                if rhs == 0 then fail("Division by zero") end
                value = checked(value / rhs, "Result out of range")
            elseif startsFactor(peek()) then
                value = checked(value * parseUnary(), "Result out of range")
            else
                return value
            end
        end
    end

    parseUnary = function()
        if acceptSymbol("+") then return checked(parseUnary(), "Result out of range") end
        if acceptSymbol("-") then return checked(-parseUnary(), "Result out of range") end
        return parsePower()
    end

    parsePower = function()
        local value = parsePostfix()
        if acceptSymbol("^") then
            value = checked(value ^ parseUnary(), "Result out of range")
        end
        return value
    end

    parsePostfix = function()
        local value = parsePrimary()

        while true do
            if acceptSymbol("%") then
                value = checked(value / 100, "Result out of range")
            elseif acceptSymbol("!") then
                value = checked(factorial(value), "Result out of range")
            else
                return value
            end
        end
    end

    parsePrimary = function()
        local token = peek()

        if token.kind == "number" then
            pos = pos + 1
            return checked(token.value, "Number out of range")
        end

        if acceptSymbol("(") then
            local value = parseExpression()
            expectSymbol(")")
            return value
        end

        if token.kind == "ident" then
            local name = token.value
            pos = pos + 1

            local constant = constantValue(name)
            if constant ~= nil then return checked(constant, "Number out of range") end

            if acceptSymbol("(") then
                local args = {}
                if not acceptSymbol(")") then
                    while true do
                        args[#args + 1] = parseExpression()
                        if acceptComma() then
                            -- Continue.
                        else
                            break
                        end
                    end
                    expectSymbol(")")
                end
                return checked(callFunction(name, args), "Result out of range")
            end

            fail(name .. " needs parentheses")
        end

        fail("Expected a value")
    end

    local result = parseExpression()
    if peek().kind ~= "eof" then fail("Unexpected input: " .. tostring(peek().text)) end
    if not isFinite(result) then fail("Result out of range") end
    return result
end

local function evaluateSafe(expression)
    local ok, result = pcall(evaluateExpression, expression)
    if ok then return result, nil end
    return nil, trimError(result)
end

local binaryOperators = {["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["^"] = true}

local function shouldStartNew(text)
    return not binaryOperators[text] and text ~= ")" and text ~= "%" and text ~= "!"
end

local function atEntryStart()
    return input == "" or input:match("[%+%-%*/%^%(]$")
end

local function appendText(text)
    if justEvaluated then
        if shouldStartNew(text) then
            input = ""
        end
        justEvaluated = false
        status = ""
        errorMessage = nil
    end

    if input == "0" and shouldStartNew(text) and text ~= "." then
        input = ""
    end

    if text == "." then
        local tail = input:match("([%d%.]+)$") or ""
        if tail:find("%.", 1, true) then return end
        if atEntryStart() then text = "0." end
    end

    if #input + #text > MAX_INPUT_LEN then
        showEntryLimit()
        return
    end

    input = input .. text
    if input == "" then input = "0" end
    invalidate()
end

local function clearAll()
    input = "0"
    status = "Cleared"
    lastExpression = ""
    errorMessage = nil
    justEvaluated = false
    invalidate()
end

local function backspace()
    if justEvaluated then
        input = "0"
        justEvaluated = false
    else
        input = input:sub(1, -2)
        if input == "" then input = "0" end
    end
    status = ""
    errorMessage = nil
    invalidate()
end

local function negate()
    local newInput
    if input == "0" then
        newInput = "-"
    elseif input:sub(1, 2) == "-(" and input:sub(-1) == ")" then
        newInput = input:sub(3, -2)
    else
        newInput = "-(" .. input .. ")"
    end

    if #newInput > MAX_INPUT_LEN then
        showEntryLimit()
        return
    end

    input = newInput
    justEvaluated = false
    status = ""
    errorMessage = nil
    invalidate()
end

local function evaluate()
    local value, err = evaluateSafe(input)
    if value then
        ans = value + 0.0
        lastExpression = input
        input = formatNumber(ans)
        status = lastExpression .. " ="
        errorMessage = nil
        justEvaluated = true
    else
        showError(err)
        justEvaluated = false
    end
    invalidate()
    return value
end

local function currentValue()
    if justEvaluated then return ans end
    local value, err = evaluateSafe(input)
    if value then return value end
    showError(err)
    return nil
end

local function storeMemory()
    local value = currentValue()
    if not value then return end
    memory = value + 0.0
    memorySet = true
    status = "M = " .. formatNumber(memory)
    errorMessage = nil
    invalidate()
end

local function addMemory()
    local value = currentValue()
    if not value then return end
    local newMemory = memory + value
    if not isFinite(newMemory) then
        showError("Memory out of range")
        return
    end
    memory = newMemory + 0.0
    memorySet = true
    status = "M+ -> " .. formatNumber(memory)
    errorMessage = nil
    invalidate()
end

local function recallMemory()
    local text = "m"
    if not memorySet then
        memory = 0
        memorySet = true
    end
    appendText(text)
end

local function clearMemory()
    memory = 0
    memorySet = false
    status = "Memory cleared"
    errorMessage = nil
    invalidate()
end

local function toggleAngleMode()
    if angleMode == "DEG" then angleMode = "RAD" else angleMode = "DEG" end
    status = "Angle mode: " .. angleMode
    errorMessage = nil
    invalidate()
end

local function pressButton(action, value)
    if action == "insert" then
        appendText(value)
    elseif action == "clear" then
        clearAll()
    elseif action == "backspace" then
        backspace()
    elseif action == "equals" then
        evaluate()
    elseif action == "negate" then
        negate()
    elseif action == "angle" then
        toggleAngleMode()
    elseif action == "memoryStore" then
        storeMemory()
    elseif action == "memoryAdd" then
        addMemory()
    elseif action == "memoryRecall" then
        recallMemory()
    elseif action == "memoryClear" then
        clearMemory()
    end
end

local function setupColors()
    if colors or not lcd or not lcd.RGB then return end
    colors = {
        bg = lcd.RGB(8, 10, 12),
        panel = lcd.RGB(22, 25, 28),
        panelEdge = lcd.RGB(66, 72, 78),
        text = lcd.RGB(235, 238, 240),
        dim = lcd.RGB(150, 158, 166),
        accent = lcd.RGB(92, 196, 164),
        warn = lcd.RGB(255, 196, 87),
        error = lcd.RGB(255, 118, 118)
    }
end

local function measureText(text, font)
    text = tostring(text or "")
    if lcd and lcd.font and font then lcd.font(font) end
    if lcd and lcd.getTextSize then
        local w, h = lcd.getTextSize(text)
        return w or (#text * 8), h or 12
    end
    return #text * 8, 12
end

local function fitRight(text, width, font)
    text = tostring(text or "")
    if select(1, measureText(text, font)) <= width then return text end

    local tail = text
    while #tail > 0 do
        tail = tail:sub(2)
        local clipped = "..." .. tail
        if select(1, measureText(clipped, font)) <= width then return clipped end
    end
    return ""
end

local function drawRight(x, y, width, text, font)
    local clipped = fitRight(text, width, font)
    local textW = select(1, measureText(clipped, font))
    lcd.drawText(x + width - textW, y, clipped, font)
end

local function drawLeft(x, y, width, text, font)
    lcd.drawText(x, y, fitRight(text, width, font), font)
end

local function computeLayout(w, h)
    local rowCount = #BUTTON_ROWS
    local gap = 3
    local wantedDisplay = Math.floor(h * 0.25)
    local minButtonH = 18
    local maxDisplay = h - (rowCount * minButtonH) - ((rowCount + 1) * gap)

    displayH = Math.max(44, Math.min(82, wantedDisplay))
    if displayH > maxDisplay then displayH = Math.max(44, maxDisplay) end
    buttonTop = displayH
end

local function buildButtons(w, h)
    if not form or not form.addButton then return end

    setupColors()
    computeLayout(w, h)
    layoutW, layoutH = w, h
    buttonFields = {}

    if form.clear then form.clear() end

    local rowCount = #BUTTON_ROWS
    local colCount = #BUTTON_ROWS[1]
    local gap = 3
    local usableW = w - (gap * (colCount + 1))
    local usableH = h - buttonTop - (gap * (rowCount + 1))
    local buttonW = Math.max(28, Math.floor(usableW / colCount))
    local buttonH = Math.max(18, Math.floor(usableH / rowCount))
    local y = buttonTop + gap

    for r, row in ipairs(BUTTON_ROWS) do
        local x = gap
        for c, item in ipairs(row) do
            local label, action, value = item[1], item[2], item[3]
            local pos = {x = x, y = y, w = buttonW, h = buttonH}
            buttonFields[#buttonFields + 1] = form.addButton(nil, pos, {
                text = label,
                icon = nil,
                options = FONT_MED,
                paint = function() end,
                press = function()
                    pressButton(action, value)
                end
            })

            if r == rowCount and c == colCount and buttonFields[#buttonFields] and buttonFields[#buttonFields].focus then
                buttonFields[#buttonFields]:focus()
            end

            x = x + buttonW + gap
        end
        y = y + buttonH + gap
    end
end

local function ensureLayout()
    if not lcd or not lcd.getWindowSize then return end
    local w, h = lcd.getWindowSize()
    if w ~= layoutW or h ~= layoutH then
        buildButtons(w, h)
        invalidate()
    end
end

local function resetLayout()
    -- Ethos keeps Lua state alive between tool opens, but recreates form controls.
    layoutW, layoutH = 0, 0
    buttonFields = {}
end

local function create()
    setupColors()
    resetLayout()
    ensureLayout()
end

local function close()
    resetLayout()
    return true
end

local function wakeup()
    ensureLayout()
end

local function paint()
    if not lcd or not lcd.getWindowSize then return end
    setupColors()
    ensureLayout()

    local w = layoutW
    local top = buttonTop
    local margin = 4
    local panelH = Math.max(36, top - (margin * 2))
    local panelW = w - (margin * 2)
    local c = colors

    lcd.color(c.bg)
    lcd.drawFilledRectangle(0, 0, w, top)
    lcd.color(c.panel)
    lcd.drawFilledRectangle(margin, margin, panelW, panelH)
    lcd.color(c.panelEdge)
    lcd.drawFilledRectangle(margin, margin + panelH - 1, panelW, 1)
    lcd.color(c.accent)
    lcd.drawFilledRectangle(margin, margin + panelH - 3, panelW, 2)

    local topText = angleMode .. "  ANS " .. formatNumber(ans)
    if memorySet then topText = topText .. "  M " .. formatNumber(memory) end

    lcd.color(c.dim)
    drawLeft(margin + 6, margin + 4, panelW - 12, topText, FONT_SMALL)

    lcd.color(c.text)
    local exprY = margin + Math.max(16, Math.floor(panelH * 0.35))
    drawRight(margin + 6, exprY, panelW - 12, input, FONT_BIG)

    local line = errorMessage and ("Error: " .. errorMessage) or status
    if line == "" and lastExpression ~= "" then line = lastExpression end
    lcd.color(errorMessage and c.error or c.warn)
    drawRight(margin + 6, margin + panelH - 18, panelW - 12, line, FONT_SMALL)
end

local function event(_, category, value)
    if category == _G.EVT_KEY then
        if value == _G.KEY_ENTER_LONG then
            evaluate()
            if system and system.killEvents and _G.KEY_ENTER_BREAK then system.killEvents(_G.KEY_ENTER_BREAK) end
            return true
        elseif value == _G.KEY_DEL_BREAK or value == _G.KEY_BACKSPACE_BREAK then
            backspace()
            return true
        end
    end

    return false
end

local function name()
    return TOOL_NAME
end

local function init()
    system.registerSystemTool({
        name = name,
        icon = icon,
        create = create,
        wakeup = wakeup,
        paint = paint,
        event = event,
        close = close
    })
end

return {init = init, version = TOOL_VERSION}
