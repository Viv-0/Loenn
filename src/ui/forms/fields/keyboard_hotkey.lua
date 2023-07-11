local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local stringField = require("ui.forms.fields.string")
local iconUtils = require("ui.utils.icons")
local utils = require("utils")
local languageRegistry = require("language_registry")

local hotkeyStruct = require("structs.hotkey")
local inputCapturingDevice = require("input_devices.input_capture_device")

local shortcutField = {}

shortcutField._MT = {}
shortcutField._MT.__index = {}

function shortcutField._MT.__index:setValue(value)
    self.field:setText(value)
    self.currentValue = value
end

function shortcutField._MT.__index:getValue()
    return self.currentValue
end

function shortcutField._MT.__index:fieldValid()
    return true
end

shortcutField.fieldType = "keyboard_hotkey"

local function captureKeyboard(formField, buttonElement)
    local previousText = buttonElement.text
    local language = languageRegistry.getLanguage()

    buttonElement:setText(tostring(language.ui.userInput.capturing))

    return function(hotkeyActivator)
        if hotkeyActivator then
            formField:setValue(hotkeyActivator)
            formField:notifyFieldChanged()
            buttonElement:setText(hotkeyActivator)

        else
            buttonElement:setText(previousText)
        end
    end
end

function shortcutField.getElement(name, value, options)
    local formField = {}

    local language = languageRegistry.getLanguage()
    local buttonText = value or tostring(language.ui.userInput.noValue)

    local label = uiElements.label(options.displayName or name)
    local buttonElement = uiElements.button(buttonText, function(self, x, y, button)
        inputCapturingDevice.captureKeyboardHotkey(captureKeyboard(formField, self))
    end)

    local minWidth = options.minWidth or options.width or 160
    local maxWidth = options.maxWidth or options.width or 160

    buttonElement:with({
        minWidth = minWidth,
        maxWidth = maxWidth
    })

    label.centerVertically = true

    formField.label = label
    formField.field = buttonElement
    formField.name = name
    formField.initialValue = value
    formField.currentValue = value
    formField.width = 2
    formField.elements = {
        label, buttonElement
    }

    return setmetatable(formField, shortcutField._MT)
end

return shortcutField