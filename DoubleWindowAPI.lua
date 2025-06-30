-- Версия: 1.0.0
-- Автор: XDevster
-- Дата: 2025-07-01

local buffer = require("DoubleBuffering")
local component = require("component")
local gpu = component.gpu
local computer = require("computer")
local event = require("event")
local keyboard = require("keyboard")

local gui = {}

-- Основные константы
local WINDOW_HEADER_HEIGHT = 1
local WINDOW_BORDER_COLOR = 0x3366CC
local WINDOW_HEADER_COLOR = 0x4477DD
local WINDOW_BACKGROUND_COLOR = 0x222222
local WINDOW_TEXT_COLOR = 0xFFFFFF
local WINDOW_SHADOW_COLOR = 0x111111
local WINDOW_MIN_WIDTH = 10
local WINDOW_MIN_HEIGHT = 5

-- Состояние GUI
local windows = {}
local activeWindow = nil
local nextWindowId = 1
local screenWidth, screenHeight = gpu.getResolution()

-- Вспомогательные функции
local function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

local function drawRect(x, y, width, height, color, char)
    buffer.setBackground(color)
    for dy = y, y + height - 1 do
        for dx = x, x + width - 1 do
            buffer.set(dx, dy, char or " ")
        end
    end
end

local function drawBorder(x, y, width, height, color)
    -- Углы
    buffer.set(x, y, "┌", color)
    buffer.set(x + width - 1, y, "┐", color)
    buffer.set(x, y + height - 1, "└", color)
    buffer.set(x + width - 1, y + height - 1, "┘", color)
    
    -- Горизонтальные линии
    for dx = x + 1, x + width - 2 do
        buffer.set(dx, y, "─", color)
        buffer.set(dx, y + height - 1, "─", color)
    end
    
    -- Вертикальные линии
    for dy = y + 1, y + height - 2 do
        buffer.set(x, dy, "│", color)
        buffer.set(x + width - 1, dy, "│", color)
    end
end

-- Класс окна
local Window = {}
Window.__index = Window

function Window.new(x, y, width, height, title)
    local self = setmetatable({}, Window)
    
    self.id = nextWindowId
    nextWindowId = nextWindowId + 1
    
    self.x = clamp(x, 1, screenWidth - 2)
    self.y = clamp(y, 1, screenHeight - 2)
    self.width = clamp(width, WINDOW_MIN_WIDTH, screenWidth - self.x)
    self.height = clamp(height, WINDOW_MIN_HEIGHT, screenHeight - self.y)
    self.title = title or "Window " .. self.id
    self.visible = true
    self.active = false
    self.zIndex = 1
    self.elements = {}
    
    return self
end

function Window:draw()
    if not self.visible then return end
    
    -- Тень
    drawRect(self.x + 1, self.y + 1, self.width, self.height, WINDOW_SHADOW_COLOR)
    
    -- Основное окно
    drawRect(self.x, self.y, self.width, self.height, WINDOW_BACKGROUND_COLOR)
    drawBorder(self.x, self.y, self.width, self.height, WINDOW_BORDER_COLOR)
    
    -- Заголовок
    drawRect(self.x + 1, self.y, self.width - 2, 1, WINDOW_HEADER_COLOR)
    local titleText = " " .. self.title .. " "
    buffer.set(self.x + math.floor((self.width - #titleText) / 2), self.y, titleText, WINDOW_HEADER_COLOR, WINDOW_TEXT_COLOR)
    
    -- Кнопка закрытия
    buffer.set(self.x + self.width - 3, self.y, "[×]", WINDOW_HEADER_COLOR, 0xFF5555)
    
    -- Отрисовка элементов
    for _, element in ipairs(self.elements) do
        if element.draw then
            element:draw()
        end
    end
end

function Window:addElement(element)
    table.insert(self.elements, element)
    element.parent = self
    return element
end

function Window:contains(x, y)
    return x >= self.x and x < self.x + self.width and y >= self.y and y < self.y + self.height
end

function Window:bringToFront()
    local maxZ = 1
    for _, win in ipairs(windows) do
        if win ~= self and win.zIndex >= maxZ then
            maxZ = win.zIndex + 1
        end
    end
    self.zIndex = maxZ
end

-- Элементы GUI
local Button = {}
Button.__index = Button

function Button.new(x, y, width, text, onClick)
    local self = setmetatable({}, Button)
    self.x = x
    self.y = y
    self.width = width or (#text + 4)
    self.height = 3
    self.text = text
    self.onClick = onClick or function() end
    self.enabled = true
    return self
end

function Button:draw()
    local parent = self.parent
    if not parent then return end
    
    local absX = parent.x + self.x
    local absY = parent.y + self.y
    
    local bgColor = self.enabled and 0x555555 or 0x333333
    local fgColor = self.enabled and 0xFFFFFF or 0xAAAAAA
    
    -- Основная кнопка
    drawRect(absX, absY, self.width, self.height, bgColor)
    drawBorder(absX, absY, self.width, self.height, 0x777777)
    
    -- Текст
    buffer.set(absX + math.floor((self.width - #self.text) / 2), absY + 1, self.text, bgColor, fgColor)
end

function Button:contains(x, y)
    local parent = self.parent
    if not parent then return false end
    
    local absX = parent.x + self.x
    local absY = parent.y + self.y
    
    return x >= absX and x < absX + self.width and y >= absY and y < absY + self.height
end

-- Основные функции GUI
function gui.createWindow(x, y, width, height, title)
    local window = Window.new(x, y, width, height, title)
    table.insert(windows, window)
    return window
end

function gui.drawAll()
    buffer.clear(WINDOW_TEXT_COLOR, WINDOW_BACKGROUND_COLOR)
    
    -- Сортировка окон по z-index
    table.sort(windows, function(a, b) return a.zIndex < b.zIndex end)
    
    -- Отрисовка окон
    for _, window in ipairs(windows) do
        window:draw()
    end
    
    buffer.draw()
end

function gui.handleEvents()
    while true do
        local e = {event.pull()}
        
        if e[1] == "touch" then
            local x, y = e[3], e[4]
            
            -- Проверка кликов по окнам (сверху вниз по z-index)
            for i = #windows, 1, -1 do
                local window = windows[i]
                if window:contains(x, y) then
                    window:bringToFront()
                    
                    -- Проверка кнопки закрытия
                    if x >= window.x + window.width - 3 and x < window.x + window.width and y == window.y then
                        window.visible = false
                        break
                    end
                    
                    -- Проверка элементов окна
                    for _, element in ipairs(window.elements) do
                        if element:contains(x, y) and element.onClick then
                            element:onClick()
                            break
                        end
                    end
                    
                    break
                end
            end
            
            gui.drawAll()
        elseif e[1] == "key_down" then
            -- Обработка клавиатуры для активного окна
            if activeWindow then
                -- Можно добавить обработку клавиш здесь
            end
        end
    end
end

-- Пример использования
function gui.demo()
    -- Создаем главное окно
    local mainWin = gui.createWindow(5, 3, 40, 20, "Main Window")
    
    -- Добавляем кнопку
    local btn = mainWin:addElement(Button.new(10, 5, 20, "Click me!", function()
        -- Создаем новое окно при клике
        local dialog = gui.createWindow(15, 10, 30, 10, "Dialog")
        dialog:addElement(Button.new(5, 5, 20, "Close", function()
            dialog.visible = false
            gui.drawAll()
        end))
        gui.drawAll()
    end))
    
    -- Отрисовываем интерфейс
    gui.drawAll()
    
    -- Запускаем обработку событий
    gui.handleEvents()
end

return gui
