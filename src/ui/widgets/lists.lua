local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local widgetUtils = require("ui.widgets.utils")

local listWidgets = {}

local function calculateWidth(orig, element)
    return element.inner.width
end

local function filterItems(items, search, caseSensitive)
    local filtered = {}

    if caseSensitive ~= false then
        search = search:lower()
    end

    for _, item in ipairs(items) do
        local text = item.text
        local textType = type(text)

        if textType == "string" then
            if caseSensitive ~= false then
                text = text:lower()
            end

            if text:contains(search) then
                table.insert(filtered, item)
            end

        else
            -- Improve this for non string in the future

            table.insert(filtered, item)
        end
    end

    return filtered
end
function listWidgets.setSelection(list, target, preventCallback, callbackRequiresChange)
    -- Select first item as default, callback if it exists
    -- If target is defined attempt to select this instead of the first item

    local selectedTarget = false
    local selectedIndex = 1
    local previousSelection = list.selected and list.selected.data
    local newSelection

    if target and target ~= false then
        for i, item in ipairs(list.children) do
            if item == target or item.data == target or item.text == target or i == target then
                newSelection = item
                selectedTarget = true
                selectedIndex = i

                break
            end
        end
    end

    if newSelection then
        list.selected = newSelection

        if not preventCallback then
            local dataChanged = newSelection.data ~= previousSelection

            if callbackRequiresChange and dataChanged or not callbackRequiresChange then
                -- Set owner manually here for now
                -- TODO - Test whether this is actually needed later
                list.selected.owner = list
                list.selected:onClick(nil, nil, 1)
            end
        end
    end

    return selectedTarget, selectedIndex
end

local function findChildIndex(parent, child)
    for i, c in ipairs(parent.children or {}) do
        if child == c then
            return i
        end
    end
end

local function findListParent(element)
    local target = element

    while target and target.__type ~= "list" do
        target = target.parent
    end

    return target
end

local function getListDropTarget(element, x, y)
    local elementList = findListParent(element)

    if not elementList.draggable then
        return false, false, false
    end

    local hovered = ui.root and ui.root:getChildAt(x, y)

    if hovered then
        local hoveredList = findListParent(hovered)

        if hoveredList then
            if elementList == hoveredList then
                return hoveredList, hovered
            end

            if elementList.draggableTag and elementList.draggableTag == hoveredList.draggableTag then
                return hoveredList, hovered
            end
        end
    end

    return false, false, false
end

-- TODO - Currently only moves the child elements, nothing else
local function moveListItem(fromList, fromListItem, toList, toListItem, fromIndex, toIndex)
    local sameList = fromList == toList

    -- No change
    if sameList and fromIndex == toIndex then
        return false
    end

    local toChildren = toList.children or {}
    local fromChildren = fromList.children or {}

    -- Make sure we don't shift around the indices when moving in same list
    if fromIndex < toIndex then
        table.insert(toChildren, toIndex, fromListItem)
        table.remove(fromChildren, fromIndex)

    else
        table.remove(fromChildren, fromIndex)
        table.insert(toChildren, toIndex, fromListItem)
    end

    return true
end

local function handleItemDrag(self, x, y)
    local ourList, ourListItem = findListParent(self), self
    local hoveredList, hoveredListItem = getListDropTarget(self, x, y)

    if hoveredList then
        local sameList = ourList == hoveredList
        local ourIndex = findChildIndex(ourList, ourListItem)
        local hoveredIndex = findChildIndex(hoveredList, hoveredListItem)
        local centerDeltaX, centerDeltaY = widgetUtils.cursorDeltaFromElementCenter(hoveredListItem, x, y)
        local insertAfter = centerDeltaY >= 0

        if insertAfter then
            hoveredIndex += 1
        end

        local moved = moveListItem(ourList, ourListItem, hoveredList, hoveredListItem, ourIndex, hoveredIndex)

        if moved then
            ourList:reflow()
            ourList:redraw()

            if not sameList then
                hoveredList:reflow()
                hoveredList:redraw()
            end
        end
    end
end

local function prepareItemDragHook()
    return {
        draw = function(orig, self)
            orig(self)
        end,
        onPress = function(orig, self, x, y, button, dragging)
            if button == 1 then
                self.dragging = dragging

            else
                orig(self, x, y, button, dragging)
            end
        end,
        onRelease = function(orig, self, x, y, button, dragging)
            if button == 1 or not dragging then
                self.dragging = dragging

                handleItemDrag(self, x, y)

            else
                orig(self, x, y, button, dragging)
            end
        end
    }
end

local function addDraggableHooks(list)
    local draggable = list.draggable

    if draggable then
        for _, item in ipairs(list.children or {}) do
            if not item._addedDraggableHook then
                item:hook(prepareItemDragHook())

                item._addedDraggableHook = true
            end
        end
    end
end

function listWidgets.updateItems(list, items, target, fromFilter, preventCallback, callbackRequiresChange)
    local previousSelection = list.selected and list.selected.data
    local newSelection

    local processedItems = items

    if not fromFilter and list.searchField then
        local search = list.searchField:getText() or ""

        processedItems = filterItems(items, search)
    end

    for _, item in ipairs(processedItems) do
        if item.data == previousSelection then
            newSelection = item
        end

        if fromFilter then
            item:reflow()
        end
    end

    list.children = processedItems

    ui.runLate(function()
        listWidgets.setSelection(list, target or newSelection, preventCallback, callbackRequiresChange)
    end)

    list:reflow()
    ui.root:recollect()

    if not fromFilter then
        list.unfilteredItems = items
    end

    addDraggableHooks(list)
end

local function filterList(list, search)
    local unfilteredItems = list.unfilteredItems
    local filteredItems = filterItems(unfilteredItems, search)

    listWidgets.updateItems(list, filteredItems, nil, true, false, true)
end

local function getSearchFieldChanged(onChange)
    return function(element, new, old)
        if onChange then
            onChange(element, new, old)
        end

        filterList(element.list, new)
        addDraggableHooks(element.list)
    end
end

function listWidgets.setFilterText(list, text, updateList)
    local searchField = list.searchField

    if searchField then
        searchField:setText(text)

        if updateList or updateList == nil then
            filterList(list, text)
        end
    end
end

local function getColumnForList(searchField, scrolledList, mode)
    local columnItems

    if mode == "below" then
        columnItems = {
            scrolledList,
            searchField:with(uiUtils.bottombound)
        }

    elseif mode == "above" then
        columnItems = {
            searchField,
            scrolledList
        }

    else
        columnItems = {scrolledList}
    end

    return uiElements.column(columnItems):with(uiUtils.fillHeight(false))
end

function listWidgets.getList(callback, items, options)
    options = options or {}
    items = items or {}

    local initialSearch = options.initialSearch or ""
    local filteredItems = filterItems(items, initialSearch)

    local list = uiElements.list(filteredItems, callback):with({
        unfilteredItems = items,
        minWidth = options.minimumWidth or 128,
        draggable = options.draggable or false,
        draggableTag = options.draggableTag or false
    })

    addDraggableHooks(list)

    ui.runLate(function()
        listWidgets.setSelection(list, list.options.initialItem)
    end)

    local scrolledList = uiElements.scrollbox(list):with(uiUtils.hook({
        calcWidth = calculateWidth
    })):with(uiUtils.fillHeight(true))

    local searchFieldCallback = getSearchFieldChanged(options.searchBarCallback)
    local searchField = uiElements.field(initialSearch, searchFieldCallback):with({
        list = list
    }):with(uiUtils.fillWidth)

    list.options = options
    list.searchField = searchField

    local column = getColumnForList(searchField, scrolledList, options.searchBarLocation)

    return column, list, searchField
end

return listWidgets