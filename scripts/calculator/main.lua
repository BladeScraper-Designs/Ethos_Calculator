-- Ethos Calculator
-- A self-contained scientific calculator system tool.

local TOOL_NAME = "Calculator"
local TOOL_VERSION = "1.2.0"
local MAX_INPUT_LEN = 160
local MAX_PARSE_DEPTH = 48
local DISPLAY_SIG_DIGITS = 7

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

local MODE_CALC = "calc"
local MODE_RC = "rc"
local currentMode = MODE_CALC
local rcPrompt = nil
local rcPromptInput = ""
local rcPromptError = nil
local consumeRtnRelease = false

local K = {
    PAGE_FIRST = _G.KEY_PAGE_FIRST or _G.KEY_PGUP_FIRST or _G.KEY_PGUP,
    PAGE_BREAK = _G.KEY_PAGE_BREAK or _G.KEY_PGUP_BREAK,
    RTN_FIRST = _G.KEY_RTN_FIRST or _G.KEY_RETURN_FIRST or _G.KEY_EXIT_FIRST or _G.KEY_BACK_FIRST,
    RTN_BREAK = _G.KEY_RTN_BREAK or _G.KEY_RETURN_BREAK or _G.KEY_EXIT_BREAK or _G.KEY_BACK_BREAK,
    RTN_LONG = _G.KEY_RTN_LONG or _G.KEY_RETURN_LONG or _G.KEY_EXIT_LONG or _G.KEY_BACK_LONG,
    ENTER_LONG = _G.KEY_ENTER_LONG,
    ENTER_BREAK = _G.KEY_ENTER_BREAK,
    DEL_BREAK = _G.KEY_DEL_BREAK,
    BACKSPACE_BREAK = _G.KEY_BACKSPACE_BREAK
}

local layoutW, layoutH = 0, 0
local displayH = 70
local buttonTop = 74
local buttonFields = {}
local colors = nil

local CALC_BUTTON_ROWS = {
    {{"AC", "clear"}, {"DEL", "backspace"}, {"(", "insert", "("}, {")", "insert", ")"}, {"D/R", "angle"}, {"ANS", "insert", "ans"}},
    {{"sin", "insert", "sin("}, {"cos", "insert", "cos("}, {"tan", "insert", "tan("}, {"asin", "insert", "asin("}, {"acos", "insert", "acos("}, {"atan", "insert", "atan("}},
    {{"ln", "insert", "ln("}, {"log", "insert", "log("}, {"sqrt", "insert", "sqrt("}, {"x^y", "insert", "^"}, {"pi", "insert", "pi"}, {"e", "insert", "e"}},
    {{"7", "insert", "7"}, {"8", "insert", "8"}, {"9", "insert", "9"}, {"/", "insert", "/"}, {"%", "insert", "%"}, {"!", "insert", "!"}},
    {{"4", "insert", "4"}, {"5", "insert", "5"}, {"6", "insert", "6"}, {"*", "insert", "*"}, {"M+", "memoryAdd"}, {"MR", "memoryRecall"}},
    {{"1", "insert", "1"}, {"2", "insert", "2"}, {"3", "insert", "3"}, {"-", "insert", "-"}, {"MS", "memoryStore"}, {"MC", "memoryClear"}},
    {{"0", "insert", "0"}, {".", "insert", "."}, {"+/-", "negate"}, {"+", "insert", "+"}, {"EE", "insert", "e"}, {"=", "equals"}}
}

local THROTTLE_SCALES = {
    {
        label = "0-100%",
        inputLabel = "Throttle 0-100%",
        resultLabel = "Throttle 0-100 value",
        signedResult = false,
        toBase = function(value) return value * 2 - 100 end,
        fromBase = function(value) return (value + 100) / 2 end
    },
    {
        label = "+/-100%",
        inputLabel = "Throttle +/-100%",
        resultLabel = "Throttle +/-100 value",
        signedResult = true,
        toBase = function(value) return value end,
        fromBase = function(value) return value end
    }
}

local CHANNEL_PWM_MIN = 800
local CHANNEL_PWM_MAX = 2200
local CHANNEL_PERCENT_MIN = -125
local CHANNEL_PERCENT_MAX = 125

local function validateChannelPwm(value)
    if value < CHANNEL_PWM_MIN or value > CHANNEL_PWM_MAX then
        return false, "PWM us must be 800 to 2200"
    end
    return true, nil
end

local function validateChannelPercent(value)
    if value < CHANNEL_PERCENT_MIN or value > CHANNEL_PERCENT_MAX then
        return false, "Channel % must be -125 to +125"
    end
    return true, nil
end

local function requireChannelPwm(value)
    local ok, message = validateChannelPwm(value)
    if not ok then error(message, 0) end
end

local function requireChannelPercent(value)
    local ok, message = validateChannelPercent(value)
    if not ok then error(message, 0) end
end

local UNIT_GROUPS = {
    {
        label = "Channel",
        units = {
            {
                label = "PWM us",
                inputLabel = "PWM pulse width us",
                resultLabel = "PWM pulse width value",
                signedResult = false,
                validateInput = validateChannelPwm,
                toBase = function(value) return (value - 1500) / 5 end,
                fromBase = function(value) return 1500 + (value * 5) end
            },
            {
                label = "Channel %",
                inputLabel = "Channel percent",
                resultLabel = "Channel percent value",
                signedResult = true,
                validateInput = validateChannelPercent,
                toBase = function(value) return value end,
                fromBase = function(value) return value end
            }
        }
    },
    {
        label = "Length",
        units = {
            {
                label = "mi",
                inputLabel = "Miles",
                resultLabel = "Miles value",
                signedResult = false,
                toBase = function(value) return value * 1609.344 end,
                fromBase = function(value) return value / 1609.344 end
            },
            {
                label = "yd",
                inputLabel = "Yards",
                resultLabel = "Yards value",
                signedResult = false,
                toBase = function(value) return value * 0.9144 end,
                fromBase = function(value) return value / 0.9144 end
            },
            {
                label = "ft",
                inputLabel = "Feet",
                resultLabel = "Feet value",
                signedResult = false,
                toBase = function(value) return value * 0.3048 end,
                fromBase = function(value) return value / 0.3048 end
            },
            {
                label = "in",
                inputLabel = "Inches",
                resultLabel = "Inches value",
                signedResult = false,
                toBase = function(value) return value * 0.0254 end,
                fromBase = function(value) return value / 0.0254 end
            },
            {
                label = "km",
                inputLabel = "Kilometers",
                resultLabel = "Kilometers value",
                signedResult = false,
                toBase = function(value) return value * 1000 end,
                fromBase = function(value) return value / 1000 end
            },
            {
                label = "m",
                inputLabel = "Meters",
                resultLabel = "Meters value",
                signedResult = false,
                toBase = function(value) return value end,
                fromBase = function(value) return value end
            },
            {
                label = "cm",
                inputLabel = "Centimeters",
                resultLabel = "Centimeters value",
                signedResult = false,
                toBase = function(value) return value / 100 end,
                fromBase = function(value) return value * 100 end
            },
            {
                label = "mm",
                inputLabel = "Millimeters",
                resultLabel = "Millimeters value",
                signedResult = false,
                toBase = function(value) return value / 1000 end,
                fromBase = function(value) return value * 1000 end
            }
        }
    },
    {
        label = "Weight",
        units = {
            {
                label = "kg",
                inputLabel = "Kilograms",
                resultLabel = "Kilograms value",
                signedResult = false,
                toBase = function(value) return value * 1000 end,
                fromBase = function(value) return value / 1000 end
            },
            {
                label = "g",
                inputLabel = "Grams",
                resultLabel = "Grams value",
                signedResult = false,
                toBase = function(value) return value end,
                fromBase = function(value) return value end
            },
            {
                label = "mg",
                inputLabel = "Milligrams",
                resultLabel = "Milligrams value",
                signedResult = false,
                toBase = function(value) return value / 1000 end,
                fromBase = function(value) return value * 1000 end
            },
            {
                label = "lb",
                inputLabel = "Pounds",
                resultLabel = "Pounds value",
                signedResult = false,
                toBase = function(value) return value * 453.59237 end,
                fromBase = function(value) return value / 453.59237 end
            },
            {
                label = "oz",
                inputLabel = "Ounces",
                resultLabel = "Ounces value",
                signedResult = false,
                toBase = function(value) return value * 28.349523125 end,
                fromBase = function(value) return value / 28.349523125 end
            }
        }
    },
    {
        label = "Temp",
        units = {
            {
                label = "degC",
                inputLabel = "Degrees C",
                resultLabel = "Degrees C value",
                signedResult = false,
                toBase = function(value) return value + 273.15 end,
                fromBase = function(value) return value - 273.15 end
            },
            {
                label = "degF",
                inputLabel = "Degrees F",
                resultLabel = "Degrees F value",
                signedResult = false,
                toBase = function(value) return ((value - 32) * 5 / 9) + 273.15 end,
                fromBase = function(value) return ((value - 273.15) * 9 / 5) + 32 end
            },
            {
                label = "Kelvin",
                inputLabel = "Kelvin",
                resultLabel = "Kelvin value",
                signedResult = false,
                toBase = function(value) return value end,
                fromBase = function(value) return value end
            }
        }
    }
}

local function selectedThrottleScale(which)
    local index = rcPrompt and rcPrompt[which .. "Index"] or 1
    return THROTTLE_SCALES[index] or THROTTLE_SCALES[1]
end

local function selectedUnitGroup()
    local index = rcPrompt and rcPrompt.groupIndex or 1
    return UNIT_GROUPS[index] or UNIT_GROUPS[1]
end

local function selectedUnit(which)
    local group = selectedUnitGroup()
    local index = rcPrompt and rcPrompt[which .. "Index"] or 1
    return group.units[index] or group.units[1]
end

local RC_BUTTON_ROWS = {
    {{"Throttle Scale Converter", "openTool", "throttle"}, {"Unit Converter", "openTool", "unit"}},
    {{"Ohm's Law Solver", "openTool", "ohms"}, {"Back to Calculator", "modeCalc"}}
}

local THROTTLE_PROMPT_BUTTON_ROWS = {
    {{function() return "From " .. selectedThrottleScale("from").label end, "noop"}, {function() return "To " .. selectedThrottleScale("to").label end, "noop"}, {"Swap", "throttleSwap"}, {"Cancel", "promptCancel"}},
    {{"7", "promptInsert", "7"}, {"8", "promptInsert", "8"}, {"9", "promptInsert", "9"}, {"DEL", "promptBackspace"}},
    {{"4", "promptInsert", "4"}, {"5", "promptInsert", "5"}, {"6", "promptInsert", "6"}, {"Clear", "promptClear"}},
    {{"1", "promptInsert", "1"}, {"2", "promptInsert", "2"}, {"3", "promptInsert", "3"}, {"+/-", "promptNegate"}},
    {{"Cancel", "promptCancel"}, {"0", "promptInsert", "0"}, {".", "promptInsert", "."}, {"OK", "promptOk"}}
}

local UNIT_PROMPT_BUTTON_ROWS = {
    {{function() return selectedUnitGroup().label end, "unitCycleGroup"}, {function() return "From " .. selectedUnit("from").label end, "unitCycle", "from"}, {function() return "To " .. selectedUnit("to").label end, "unitCycle", "to"}, {"Swap", "unitSwap"}},
    {{"7", "promptInsert", "7"}, {"8", "promptInsert", "8"}, {"9", "promptInsert", "9"}, {"DEL", "promptBackspace"}},
    {{"4", "promptInsert", "4"}, {"5", "promptInsert", "5"}, {"6", "promptInsert", "6"}, {"Clear", "promptClear"}},
    {{"1", "promptInsert", "1"}, {"2", "promptInsert", "2"}, {"3", "promptInsert", "3"}, {"+/-", "promptNegate"}},
    {{"Cancel", "promptCancel"}, {"0", "promptInsert", "0"}, {".", "promptInsert", "."}, {"OK", "promptOk"}}
}

local OHMS_PROMPT_BUTTON_ROWS = {
    {{"Volts=", "ohmsField", "v"}, {"Amps=", "ohmsField", "i"}, {"Ohms=", "ohmsField", "r"}, {"Watts=", "ohmsField", "p"}},
    {{"7", "promptInsert", "7"}, {"8", "promptInsert", "8"}, {"9", "promptInsert", "9"}, {"DEL", "promptBackspace"}},
    {{"4", "promptInsert", "4"}, {"5", "promptInsert", "5"}, {"6", "promptInsert", "6"}, {"Clear", "promptClear"}},
    {{"1", "promptInsert", "1"}, {"2", "promptInsert", "2"}, {"3", "promptInsert", "3"}, {"+/-", "promptNegate"}},
    {{"Cancel", "promptCancel"}, {"0", "promptInsert", "0"}, {".", "promptInsert", "."}, {"Solve", "promptOk"}}
}

local GENERIC_PROMPT_BUTTON_ROWS = {
    {{"7", "promptInsert", "7"}, {"8", "promptInsert", "8"}, {"9", "promptInsert", "9"}, {"DEL", "promptBackspace"}},
    {{"4", "promptInsert", "4"}, {"5", "promptInsert", "5"}, {"6", "promptInsert", "6"}, {"Clear", "promptClear"}},
    {{"1", "promptInsert", "1"}, {"2", "promptInsert", "2"}, {"3", "promptInsert", "3"}, {"+/-", "promptNegate"}},
    {{"Cancel", "promptCancel"}, {"0", "promptInsert", "0"}, {".", "promptInsert", "."}, {"OK", "promptOk"}}
}

local RC_CONVERSIONS = {
    thr_ethos = {
        label = "Throttle 0-100 to -100/+100",
        inputLabel = "Spektrum throttle %",
        resultLabel = "Ethos/EdgeTX throttle",
        signedResult = true,
        apply = function(value) return value * 2 - 100 end
    },
    thr_spektrum = {
        label = "Throttle -100/+100 to 0-100",
        inputLabel = "Ethos/EdgeTX throttle %",
        resultLabel = "Spektrum throttle",
        apply = function(value) return (value + 100) / 2 end
    },
    pwm_pct = {
        label = "PWM microseconds to percent",
        inputLabel = "Pulse width us",
        resultLabel = "Channel percent",
        signedResult = true,
        apply = function(value)
            requireChannelPwm(value)
            return (value - 1500) / 5
        end
    },
    pct_pwm = {
        label = "Percent to PWM microseconds",
        inputLabel = "Channel percent",
        resultLabel = "Pulse width us",
        apply = function(value)
            requireChannelPercent(value)
            return 1500 + (value * 5)
        end
    },
    in_mm = {
        label = "Inches to millimeters",
        inputLabel = "Inches",
        resultLabel = "Millimeters",
        apply = function(value) return value * 25.4 end
    },
    mm_in = {
        label = "Millimeters to inches",
        inputLabel = "Millimeters",
        resultLabel = "Inches",
        apply = function(value) return value / 25.4 end
    },
    oz_g = {
        label = "Ounces to grams",
        inputLabel = "Ounces",
        resultLabel = "Grams",
        apply = function(value) return value * 28.349523125 end
    },
    g_oz = {
        label = "Grams to ounces",
        inputLabel = "Grams",
        resultLabel = "Ounces",
        apply = function(value) return value / 28.349523125 end
    }
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

    -- Ethos exposes float noise past roughly seven significant digits on some builds.
    local text = string.format("%." .. tostring(DISPLAY_SIG_DIGITS) .. "g", value + 0.0)

    text = text:gsub("e%+0?", "e"):gsub("e%-0?", "e-")
    if text == "-0" then text = "0" end
    return text
end

local function formatSignedNumber(value)
    local text = formatNumber(value)
    if type(value) == "number" and value > 0 and text:sub(1, 1) ~= "+" then
        return "+" .. text
    end
    return text
end

local function formatRcResult(tool, value)
    if tool and tool.signedResult then return formatSignedNumber(value) end
    return formatNumber(value)
end

local function formatEvaluationResult(expression, value)
    local lower = tostring(expression or ""):lower()
    for name, tool in pairs(RC_CONVERSIONS) do
        if tool.signedResult and lower:match("^%s*" .. name .. "%s*%(") then
            return formatSignedNumber(value)
        end
    end
    return formatNumber(value)
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

    local rcTool = RC_CONVERSIONS[name]
    if rcTool then
        need(1)
        return rcTool.apply(args[1])
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

    if input == "0" and text == "-" then
        input = ""
    elseif input == "0" and shouldStartNew(text) and text ~= "." then
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
        input = formatEvaluationResult(lastExpression, ans)
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

local setMode
local toggleMode
local resetLayout
local ensureLayout

local function rebuildLayout()
    if resetLayout then resetLayout() end
    if ensureLayout then ensureLayout() end
    invalidate()
end

local function showRcHelp()
    status = "Pick a tool, set units, enter values, then OK"
    errorMessage = nil
    invalidate()
end

local function closeRcPrompt(message)
    rcPrompt = nil
    rcPromptInput = ""
    rcPromptError = nil
    if message then status = message end
    rebuildLayout()
end

local function clearPromptResult()
    if not rcPrompt then return end
    rcPrompt.resultText = nil
    rcPrompt.justConverted = false
end

local function setPromptResult(text)
    if not rcPrompt then return end
    rcPrompt.resultText = text
    rcPrompt.justConverted = true
    rcPromptError = nil
end

local function promptDisplayValue()
    if rcPrompt and rcPrompt.justConverted and rcPrompt.resultText then
        return rcPrompt.resultText
    end

    if rcPrompt and rcPrompt.kind == "ohms" then
        local active = rcPrompt.active or "v"
        local value = (rcPrompt.values and rcPrompt.values[active]) or ""
        local labels = {v = "Volts=", i = "Amps=", r = "Ohms=", p = "Watts="}
        if value == "" then return labels[active] or "Value" end
        return (labels[active] or "Value=") .. value
    end

    if rcPromptInput == "" then return "Enter value" end
    return rcPromptInput
end

local function promptStatusLine()
    if rcPromptError then return rcPromptError end
    if not rcPrompt then return "" end

    if rcPrompt.kind == "throttle" then
        return selectedThrottleScale("from").label .. " to " .. selectedThrottleScale("to").label .. "  OK converts"
    elseif rcPrompt.kind == "unit" then
        return selectedUnitGroup().label .. ": " .. selectedUnit("from").label .. " to " .. selectedUnit("to").label
    elseif rcPrompt.kind == "ohms" then
        local values = rcPrompt.values or {}
        local function valueOrBlank(key)
            local value = values[key]
            if value == nil or value == "" then return "" end
            return value
        end
        return "V=" .. valueOrBlank("v") .. "  I=" .. valueOrBlank("i") ..
            "  R=" .. valueOrBlank("r") .. "  P=" .. valueOrBlank("p")
    elseif rcPrompt.tool then
        return (rcPrompt.tool.inputLabel or rcPrompt.tool.label) .. "  OK converts"
    end

    return "Enter value, then OK"
end

local function showPromptError(message)
    rcPromptError = message
    status = message
    invalidate()
end

local function setPromptInput(text)
    clearPromptResult()
    rcPromptInput = text or ""
    if rcPrompt and rcPrompt.kind == "ohms" then
        rcPrompt.values = rcPrompt.values or {}
        rcPrompt.values[rcPrompt.active or "v"] = rcPromptInput
    end
    rcPromptError = nil
    invalidate()
end

local function insertPromptText(text)
    text = tostring(text or "")

    if rcPrompt and rcPrompt.justConverted then
        clearPromptResult()
        rcPromptInput = ""
    end

    if text == "." then
        if rcPromptInput:find("%.", 1, true) then return end
        if rcPromptInput == "" or rcPromptInput == "-" then
            setPromptInput(rcPromptInput .. "0.")
        else
            setPromptInput(rcPromptInput .. ".")
        end
        return
    end

    if rcPromptInput == "0" then
        setPromptInput(text)
    elseif rcPromptInput == "-0" then
        setPromptInput("-" .. text)
    else
        setPromptInput(rcPromptInput .. text)
    end
end

local function backspacePrompt()
    clearPromptResult()
    if rcPromptInput ~= "" then
        setPromptInput(rcPromptInput:sub(1, -2))
    end
end

local function negatePrompt()
    clearPromptResult()
    if rcPromptInput == "" then
        setPromptInput("-")
    elseif rcPromptInput:sub(1, 1) == "-" then
        setPromptInput(rcPromptInput:sub(2))
    else
        setPromptInput("-" .. rcPromptInput)
    end
end

local function cycleIndex(current, count)
    current = current or 1
    current = current + 1
    if current > count then current = 1 end
    return current
end

local function swapPromptSelection(a, b)
    clearPromptResult()
    local temp = rcPrompt[a]
    rcPrompt[a] = rcPrompt[b]
    rcPrompt[b] = temp
    rebuildLayout()
end

local function cycleUnitGroup()
    if not rcPrompt then return end
    clearPromptResult()
    rcPrompt.groupIndex = cycleIndex(rcPrompt.groupIndex, #UNIT_GROUPS)
    rcPrompt.fromIndex = 1
    rcPrompt.toIndex = 2
    rebuildLayout()
end

local function cycleUnit(which)
    if not rcPrompt then return end
    clearPromptResult()
    local group = selectedUnitGroup()
    rcPrompt[which .. "Index"] = cycleIndex(rcPrompt[which .. "Index"], #group.units)
    rebuildLayout()
end

local function selectOhmsField(name)
    if not rcPrompt or rcPrompt.kind ~= "ohms" then return end
    clearPromptResult()
    rcPrompt.values = rcPrompt.values or {}
    rcPrompt.active = name
    rcPromptInput = rcPrompt.values[name] or ""
    rcPromptError = nil
    invalidate()
end

local function completeNamedConversion(name, sourceText, value)
    local tool = RC_CONVERSIONS[name]
    if not tool then return end

    local ok, result = pcall(tool.apply, value)
    if not ok then
        showPromptError(trimError(result))
        return
    end

    if type(result) ~= "number" or not isFinite(result) then
        showPromptError("Result out of range")
        return
    end

    local resultText = formatRcResult(tool, result)
    ans = result + 0.0
    lastExpression = name .. "(" .. sourceText .. ")"
    input = resultText
    status = (tool.resultLabel or tool.label) .. " value"
    errorMessage = nil
    setPromptResult(resultText)
    justEvaluated = true
    invalidate()
end

local function completeThrottlePrompt(value, sourceText, prompt)
    local fromScale = THROTTLE_SCALES[(prompt and prompt.fromIndex) or 1] or THROTTLE_SCALES[1]
    local toScale = THROTTLE_SCALES[(prompt and prompt.toIndex) or 2] or THROTTLE_SCALES[2]
    local result = toScale.fromBase(fromScale.toBase(value))
    if type(result) ~= "number" or not isFinite(result) then
        showPromptError("Result out of range")
        return
    end

    local resultText = toScale.signedResult and formatSignedNumber(result) or formatNumber(result)
    ans = result + 0.0
    lastExpression = "throttle(" .. sourceText .. " " .. fromScale.label .. " to " .. toScale.label .. ")"
    input = resultText
    status = toScale.resultLabel
    errorMessage = nil
    setPromptResult(resultText)
    justEvaluated = true
    invalidate()
end

local function completeUnitPrompt(value, sourceText, prompt)
    local group = UNIT_GROUPS[(prompt and prompt.groupIndex) or 1] or UNIT_GROUPS[1]
    local fromUnit = group.units[(prompt and prompt.fromIndex) or 1] or group.units[1]
    local toUnit = group.units[(prompt and prompt.toIndex) or 2] or group.units[2]

    if fromUnit.validateInput then
        local ok, message = fromUnit.validateInput(value)
        if not ok then
            showPromptError(message)
            return
        end
    end

    local result = toUnit.fromBase(fromUnit.toBase(value))
    if type(result) ~= "number" or not isFinite(result) then
        showPromptError("Result out of range")
        return
    end

    local resultText = toUnit.signedResult and formatSignedNumber(result) or formatNumber(result)
    ans = result + 0.0
    lastExpression = "unit(" .. sourceText .. " " .. fromUnit.label .. " to " .. toUnit.label .. ")"
    input = resultText
    status = toUnit.resultLabel
    errorMessage = nil
    setPromptResult(resultText)
    justEvaluated = true
    invalidate()
end

local OHM_FIELDS = {
    {key = "v", label = "V", unit = "V"},
    {key = "i", label = "I", unit = "A"},
    {key = "r", label = "R", unit = "ohm"},
    {key = "p", label = "P", unit = "W"}
}

local function ohmValue(values, key)
    local text = values[key]
    if text == nil or text == "" then return nil end
    local value = tonumber(text)
    if not value then return nil, "Bad " .. key:upper() .. " value" end
    if value <= 0 then return nil, "Use positive values" end
    return value, nil
end

local function formatOhmPair(values, a, b)
    local byKey = {}
    for _, field in ipairs(OHM_FIELDS) do byKey[field.key] = field end
    return byKey[a].label .. "=" .. formatNumber(values[a]) .. byKey[a].unit ..
        "  " .. byKey[b].label .. "=" .. formatNumber(values[b]) .. byKey[b].unit
end

local function completeOhmsPrompt()
    local raw = (rcPrompt and rcPrompt.values) or {}
    local values = {}
    local known = {}

    for _, field in ipairs(OHM_FIELDS) do
        local value, err = ohmValue(raw, field.key)
        if err then
            showPromptError(err)
            return
        end
        if value then
            values[field.key] = value
            known[#known + 1] = field.key
        end
    end

    if #known ~= 2 then
        showPromptError("Enter exactly two values")
        return
    end

    local have = {}
    for _, key in ipairs(known) do have[key] = true end

    if have.v and have.i then
        values.r = values.v / values.i
        values.p = values.v * values.i
    elseif have.v and have.r then
        values.i = values.v / values.r
        values.p = values.v * values.i
    elseif have.v and have.p then
        values.i = values.p / values.v
        values.r = values.v / values.i
    elseif have.i and have.r then
        values.v = values.i * values.r
        values.p = values.v * values.i
    elseif have.i and have.p then
        values.v = values.p / values.i
        values.r = values.v / values.i
    elseif have.r and have.p then
        values.i = values.p / values.r
        if values.i < 0 then
            showPromptError("Bad R/P values")
            return
        end
        values.i = values.i ^ 0.5
        values.v = values.i * values.r
    end

    for _, field in ipairs(OHM_FIELDS) do
        if type(values[field.key]) ~= "number" or not isFinite(values[field.key]) then
            showPromptError("Result out of range")
            return
        end
    end

    local missing = {}
    for _, field in ipairs(OHM_FIELDS) do
        if not have[field.key] then missing[#missing + 1] = field.key end
    end

    local resultText = formatOhmPair(values, missing[1], missing[2])

    ans = values.p + 0.0
    lastExpression = "ohms(" .. formatOhmPair(values, known[1], known[2]) .. ")"
    input = resultText
    status = "Ohm's Law from " .. known[1]:upper() .. " and " .. known[2]:upper()
    errorMessage = nil
    setPromptResult(resultText)
    justEvaluated = true
    invalidate()
end

local function completeRcPrompt()
    if not rcPrompt then return end

    if rcPrompt.kind == "ohms" then
        completeOhmsPrompt()
        return
    end

    local sourceText = rcPromptInput
    local value = tonumber(sourceText)
    if not value then
        showPromptError("Enter a number")
        return
    end

    local prompt = rcPrompt
    local kind = prompt.kind
    local conversionName = prompt.name
    rcPromptError = nil

    if kind == "throttle" then
        completeThrottlePrompt(value, sourceText, prompt)
    elseif kind == "unit" then
        completeUnitPrompt(value, sourceText, prompt)
    else
        completeNamedConversion(conversionName, sourceText, value)
    end
end

local function openRcPrompt(name)
    rcPromptInput = ""
    rcPromptError = nil
    errorMessage = nil

    if name == "throttle" then
        rcPrompt = {kind = "throttle", fromIndex = 1, toIndex = 2}
        status = "Throttle scale: use Swap, enter value"
    elseif name == "unit" then
        rcPrompt = {kind = "unit", groupIndex = 1, fromIndex = 1, toIndex = 2}
        status = "Unit Converter: choose category and units"
    elseif name == "ohms" then
        rcPrompt = {kind = "ohms", active = "v", values = {v = "", i = "", r = "", p = ""}}
        status = "Ohm's Law: enter any two values"
    else
        local tool = RC_CONVERSIONS[name]
        if not tool then return end
        rcPrompt = {kind = "named", name = name, tool = tool}
        status = tool.inputLabel or tool.label
    end

    rebuildLayout()
end

local function pressButton(action, value)
    if action == "noop" then
        return
    elseif action == "insert" then
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
    elseif action == "openTool" or action == "rcConvert" then
        openRcPrompt(value)
    elseif action == "rcHelp" then
        showRcHelp()
    elseif action == "modeCalc" and setMode then
        setMode(MODE_CALC)
    elseif action == "throttleSwap" then
        swapPromptSelection("fromIndex", "toIndex")
    elseif action == "unitCycleGroup" then
        cycleUnitGroup()
    elseif action == "unitCycle" then
        cycleUnit(value)
    elseif action == "unitSwap" then
        swapPromptSelection("fromIndex", "toIndex")
    elseif action == "ohmsField" then
        selectOhmsField(value)
    elseif action == "promptInsert" then
        insertPromptText(value)
    elseif action == "promptBackspace" then
        backspacePrompt()
    elseif action == "promptClear" then
        setPromptInput("")
    elseif action == "promptNegate" then
        negatePrompt()
    elseif action == "promptCancel" then
        closeRcPrompt("Quick Tools: select a tool")
    elseif action == "promptOk" then
        completeRcPrompt()
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

local function activeButtonRows()
    if rcPrompt then
        if rcPrompt.kind == "throttle" then return THROTTLE_PROMPT_BUTTON_ROWS end
        if rcPrompt.kind == "unit" then return UNIT_PROMPT_BUTTON_ROWS end
        if rcPrompt.kind == "ohms" then return OHMS_PROMPT_BUTTON_ROWS end
        return GENERIC_PROMPT_BUTTON_ROWS
    end
    if currentMode == MODE_RC then return RC_BUTTON_ROWS end
    return CALC_BUTTON_ROWS
end

local function computeLayout(w, h)
    local rows = activeButtonRows()
    local rowCount = #rows
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

    local rows = activeButtonRows()
    local rowCount = #rows
    local colCount = #rows[1]
    local gap = 3
    local usableW = w - (gap * (colCount + 1))
    local usableH = h - buttonTop - (gap * (rowCount + 1))
    local buttonW = Math.max(28, Math.floor(usableW / colCount))
    local buttonH = Math.max(18, Math.floor(usableH / rowCount))
    local y = buttonTop + gap

    for r, row in ipairs(rows) do
        local x = gap
        for c, item in ipairs(row) do
            local label, action, value = item[1], item[2], item[3]
            if type(label) == "function" then label = label() end
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

ensureLayout = function()
    if not lcd or not lcd.getWindowSize then return end
    local w, h = lcd.getWindowSize()
    if w ~= layoutW or h ~= layoutH then
        buildButtons(w, h)
        invalidate()
    end
end

resetLayout = function()
    -- Ethos keeps Lua state alive between tool opens, but recreates form controls.
    layoutW, layoutH = 0, 0
    buttonFields = {}
end

setMode = function(mode)
    if mode ~= MODE_CALC and mode ~= MODE_RC then return end
    if currentMode == mode then return end

    currentMode = mode
    rcPrompt = nil
    rcPromptInput = ""
    rcPromptError = nil
    errorMessage = nil
    if currentMode == MODE_RC then
        status = "Quick Tools: RTN returns to calculator"
    else
        status = "Calculator: PAGE opens Quick Tools"
    end

    resetLayout()
    ensureLayout()
    invalidate()
end

toggleMode = function()
    if currentMode == MODE_RC then
        setMode(MODE_CALC)
    else
        setMode(MODE_RC)
    end
end

local function goBack()
    if rcPrompt then
        closeRcPrompt("Quick Tools: select a tool")
        return true
    elseif currentMode == MODE_RC then
        setMode(MODE_CALC)
        return true
    end

    return false
end

local function create()
    setupColors()
    resetLayout()
    ensureLayout()
end

local function close()
    rcPrompt = nil
    rcPromptInput = ""
    rcPromptError = nil
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

    local topText
    if rcPrompt then
        if rcPrompt.kind == "ohms" then
            topText = "Ohm's Law Entry  RTN Back"
        elseif rcPrompt.kind == "unit" then
            topText = "Unit Converter  RTN Back"
        elseif rcPrompt.kind == "throttle" then
            topText = "Throttle Scale Converter  RTN Back"
        else
            topText = "Quick Tools Entry  RTN Back"
        end
    elseif currentMode == MODE_RC then
        topText = "Quick Tools  RTN Calc  ANS " .. formatNumber(ans)
    else
        topText = angleMode .. "  PAGE Tools  ANS " .. formatNumber(ans)
    end
    if memorySet then topText = topText .. "  M " .. formatNumber(memory) end

    lcd.color(c.dim)
    drawLeft(margin + 6, margin + 4, panelW - 12, topText, FONT_SMALL)

    lcd.color(c.text)
    local exprY = margin + Math.max(16, Math.floor(panelH * 0.35))
    drawRight(margin + 6, exprY, panelW - 12, rcPrompt and promptDisplayValue() or input, FONT_BIG)

    local line
    if rcPrompt then
        line = promptStatusLine()
    else
        line = errorMessage and ("Error: " .. errorMessage) or status
        if line == "" and lastExpression ~= "" then line = lastExpression end
    end

    lcd.color((errorMessage or rcPromptError) and c.error or c.warn)
    drawRight(margin + 6, margin + panelH - 18, panelW - 12, line, FONT_SMALL)
end

local function event(_, category, value)
    if category == _G.EVT_KEY then
        if K.PAGE_FIRST and value == K.PAGE_FIRST then
            if rcPrompt then closeRcPrompt("Quick Tools: select a tool") else toggleMode() end
            return true
        elseif not K.PAGE_FIRST and K.PAGE_BREAK and value == K.PAGE_BREAK then
            if rcPrompt then closeRcPrompt("Quick Tools: select a tool") else toggleMode() end
            return true
        elseif K.RTN_BREAK and value == K.RTN_BREAK and consumeRtnRelease then
            consumeRtnRelease = false
            return true
        elseif K.RTN_LONG and value == K.RTN_LONG and consumeRtnRelease then
            return true
        elseif K.RTN_FIRST and value == K.RTN_FIRST then
            local handled = goBack()
            consumeRtnRelease = handled
            return handled
        elseif K.RTN_LONG and value == K.RTN_LONG then
            local handled = goBack()
            consumeRtnRelease = handled
            return handled
        elseif not K.RTN_FIRST and K.RTN_BREAK and value == K.RTN_BREAK then
            return goBack()
        elseif value == K.ENTER_LONG then
            if rcPrompt then completeRcPrompt() else evaluate() end
            if system and system.killEvents and K.ENTER_BREAK then system.killEvents(K.ENTER_BREAK) end
            return true
        elseif value == K.DEL_BREAK or value == K.BACKSPACE_BREAK then
            if rcPrompt then backspacePrompt() else backspace() end
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
