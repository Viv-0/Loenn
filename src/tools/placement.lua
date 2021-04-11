local state = require("loaded_state")
local placementUtils = require("placement_utils")
local layerHandlers = require("layer_handlers")
local viewportHandler = require("viewport_handler")
local keyboardHelper = require("keyboard_helper")
local configs = require("configs")
local utils = require("utils")
local toolUtils = require("tool_utils")
local history = require("history")
local nodeStruct = require("structs.node")
local snapshotUtils = require("snapshot_utils")
local selectionUtils = require("selections")
local selectionItemUtils = require("selection_item_utils")

local tool = {}

tool._type = "tool"
tool.name = "placement"
tool.group = "placement"
tool.image = nil

tool.layer = "entities"
tool.validLayers = {
    "entities",
    "triggers",
    "decalsFg",
    "decalsBg"
}

local placementsAvailable = nil
local placementTemplate = nil

local placementCurrentX = 0
local placementCurrentY = 0
local placementDragStartX = 0
local placementDragStartY = 0
local placementRectangle = nil
local placementDragCompleted = false

local function getCurrentPlacementType()
    local placementInfo = placementTemplate and placementTemplate.placement
    local placementType = placementInfo and placementInfo.placementType

    return placementType
end

local function placeItemWithHistory(room)
    local snapshot = snapshotUtils.roomLayerSnapshot(function()
        placementUtils.placeItem(room, tool.layer, utils.deepcopy(placementTemplate.item))
    end, room, tool.layer, "Placement")

    history.addSnapshot(snapshot)
end

-- Get grid position and figure out if it should be offset or not based on the placement type
local function getGridPosition(x, y, precise)
    local placementType = getCurrentPlacementType()
    local addHalf = placementType ~= "rectangle"

    return placementUtils.getGridPosition(x, y, precise, addHalf)
end

local function dragStarted(x, y)
    x, y = getGridPosition(x, y)

    placementRectangle = utils.rectangle(x, y, 0, 0)
    placementDragCompleted = false

    placementDragStartX = x
    placementDragStartY = y
end

local function dragChanged(x, y, width, height)
    if placementRectangle then
        local gridSize = placementUtils.getGridSize()

        x, y = getGridPosition(x, y)
        width, height = getGridPosition(width, height)

        width += gridSize * utils.sign(width)
        height += gridSize * utils.sign(height)

        -- Pivot around the start tile
        -- Feels better when dragging towards top left
        if width < 0 then
            x += gridSize
        end

        if height < 0 then
            y += gridSize
        end

        -- Only update if needed
        if x ~= placementRectangle.x or y ~= placementRectangle.y or width ~= placementRectangle.width or height ~= placementRectangle.height then
            placementRectangle = utils.rectangle(x, y, width, height)
        end
    end
end

local function dragFinished()
    local room = state.getSelectedRoom()

    if room then
        local placementType = getCurrentPlacementType()

        if placementType == "rectangle" or placementType == "line" then
            placeItemWithHistory(room)
            toolUtils.redrawTargetLayer(room, tool.layer)
        end
    end

    placementDragCompleted = true
end

local function mouseMoved(x, y)
    placementCurrentX = x
    placementCurrentY = y
end

local function placePointPlacement()
    local room = state.getSelectedRoom()

    if room then
        local placementType = getCurrentPlacementType()

        if placementType == "point" then
            placeItemWithHistory(room)
            toolUtils.redrawTargetLayer(room, tool.layer)
        end
    end
end

-- TODO - Clean up
local function getPlacementOffset()
    local placementType = getCurrentPlacementType()

    if placementType == "rectangle" or placementType == "line" then
        if placementRectangle and not placementDragCompleted then
            return placementRectangle.x, placementRectangle.y
        end
    end

    return getGridPosition(placementCurrentX, placementCurrentY)
end

local function updatePlacementDrawable()
    if placementTemplate then
        local target = placementTemplate.item._name or placementTemplate.item.texture
        local drawable = placementUtils.getDrawable(tool.layer, target, state.getSelectedRoom(), placementTemplate.item)

        placementTemplate.drawable = drawable
    end
end

local function updatePointPlacement(template, item, itemX, itemY)
    if itemX ~= item.x or itemY ~= item.y then
        item.x = itemX
        item.y = itemY

        return true
    end

    return false
end

local function updateRectanglePlacement(template, item, itemX, itemY)
    local needsUpdate = false
    local dragging = placementRectangle and not placementDragCompleted

    local room = state.getSelectedRoom()
    local layer = tool.layer

    local resizeWidth, resizeHeight = placementUtils.canResize(room, layer, item)
    local minimumWidth, minimumHeight = placementUtils.minimumSize(room, layer, item)

    local gridSize = placementUtils.getGridSize()
    local itemWidth = math.max(dragging and placementRectangle.width or gridSize, minimumWidth or gridSize)
    local itemHeight = math.max(dragging and placementRectangle.height or gridSize, minimumHeight or gridSize)

    -- Always update when not dragging
    if not dragging then
        if itemX ~= item.x or itemY ~= item.y then
            item.x = itemX
            item.y = itemY

            needsUpdate = true
        end
    end

    -- When dragging only update the x position if we have width
    if resizeWidth and item.width then
        if dragging and itemX ~= item.x or itemWidth ~= item.width then
            item.x = itemX
            item.width = itemWidth

            needsUpdate = true
        end
    end

    -- When dragging only update the y position if we have height
    if resizeHeight and item.height then
        if not dragging and itemY ~= item.y or itemHeight ~= item.height then
            item.y = itemY
            item.height = itemHeight

            needsUpdate = true
        end
    end

    return needsUpdate
end

local function updateLinePlacement(template, item, itemX, itemY)
    local dragging = placementRectangle and not placementDragCompleted
    local firstNode = item.nodes[1] or {}
    local needsUpdate = false

    if not dragging then
        if itemX ~= item.x or itemY ~= item.y then
            item.x = itemX
            item.y = itemY

            firstNode.x = itemX + 16
            firstNode.y = itemY

            needsUpdate = true
        end

    else
        local stopX, stopY = getGridPosition(placementCurrentX, placementCurrentY)

        if stopX ~= firstNode.x or stopY ~= firstNode.y then
            firstNode.x = stopX
            firstNode.y = stopY

            needsUpdate = true
        end
    end

    -- Update all existing nodes to be after the first node
    if needsUpdate then
        for i, node in ipairs(item.nodes) do
            if i ~= 1 then
                node.x = firstNode.x + 16 * i - 16
                node.y = firstNode.y
            end
        end
    end

    return needsUpdate
end

local placementUpdaters = {
    point = updatePointPlacement,
    rectangle = updateRectanglePlacement,
    line = updateLinePlacement
}

local function updatePlacementNodes()
    local room = state.room

    local item = placementTemplate.item
    local placementType = getCurrentPlacementType()
    local minimumNodes, maximumNodes = placementUtils.nodeLimits(room, tool.layer, item)

    if minimumNodes > 0 then
        -- Set up empty nodes table if needed
        -- Make the nodes table the correct type, makes it less tedious in plugins
        if item.nodes then
            for _, node in ipairs(item.nodes) do
                node.__type = nodeStruct.nodeTypeName
            end

        else
            item.nodes = nodeStruct.decodeNodes({})
        end

        item.nodes.__type = nodeStruct.nodesTypeName

        -- Add nodes until placement has minimum amount of nodes
        while #item.nodes < minimumNodes do
            local widthOffset = item.width or 0
            local nodeOffset = (#item.nodes + 1) * 16

            local node = {
                x = item.x + widthOffset + nodeOffset,
                y = item.y
            }

            table.insert(item.nodes, node)
        end

        -- Update node positions for point and rectangle placements
        if placementType ~= "line" then
            for i, node in ipairs(item.nodes) do
                local widthOffset = item.width or 0
                local nodeOffsetX = #item.nodes * 16

                node.x = item.x + widthOffset + nodeOffsetX
                node.y = item.y
            end
        end
    end
end

local function updatePlacement()
    if placementTemplate and placementTemplate.item then
        local placementType = getCurrentPlacementType()
        local placementUpdater = placementUpdaters[placementType]

        local itemX, itemY = getPlacementOffset()
        local item = placementTemplate.item

        local needsUpdate = placementUpdater and placementUpdater(placementTemplate, item, itemX, itemY)

        if needsUpdate then
            updatePlacementNodes()
            updatePlacementDrawable()
        end
    end
end

local function selectPlacement(name, index)
    for i, placement in ipairs(placementsAvailable) do
        if i == index or placement.displayName == name or placement.name == name then
            placementTemplate = {
                item = utils.deepcopy(placement.itemTemplate),
                placement = placement,
            }

            updatePlacementNodes()
            updatePlacementDrawable()

            toolUtils.sendMaterialEvent(tool, tool.layer, placement.displayName)

            return true
        end
    end

    return false
end

local function drawPlacementDrawable(room)
    if utils.typeof(placementTemplate.drawable) == "table" then
        for _, drawable in ipairs(placementTemplate.drawable) do
            if drawable.draw then
                drawable:draw()
            end
        end

    else
        if placementTemplate.drawable.draw then
            placementTemplate.drawable:draw()
        end
    end
end

local function drawPlacement(room)
    if room and placementTemplate and placementTemplate.drawable and placementTemplate.item then
        viewportHandler.drawRelativeTo(room.x, room.y, function()
            drawPlacementDrawable(room)
            selectionItemUtils.drawSelected(room, tool.layer, placementTemplate.item)
        end)
    end
end

function tool.setLayer(layer)
    if layer ~= tool.layer or not placementsAvailable then
        tool.layer = layer
        placementsAvailable = placementUtils.getPlacements(layer)

        selectPlacement(nil, 1)

        toolUtils.sendLayerEvent(tool, layer)
    end
end

function tool.setMaterial(material)
    if type(material) == "number" then
        selectPlacement(nil, material)

    else
        selectPlacement(material, nil)
    end
end

function tool.getMaterials()
    return placementsAvailable
end

function tool.mousepressed(x, y, button, istouch, presses)
    local actionButton = configs.editor.toolActionButton

    if button == actionButton then
        local px, py = toolUtils.getCursorPositionInRoom(x, y)

        if px and py then
            dragStarted(px, py)
        end
    end
end

function tool.mouseclicked(x, y, button, istouch, presses)
    local contextMenuButton = configs.editor.contextMenuButton

    if button == contextMenuButton then
        local cursorX, cursorY = toolUtils.getCursorPositionInRoom(x, y)

        if cursorX and cursorY then
            local room = state.getSelectedRoom()
            local contextTargets = selectionUtils.getContextSelections(room, tool.layer, cursorX, cursorY)

            selectionUtils.sendContextMenuEvent(contextTargets)
        end
    end
end

function tool.mousemoved(x, y, dx, dy, istouch)
    local actionButton = configs.editor.toolActionButton
    local px, py = toolUtils.getCursorPositionInRoom(x, y)

    mouseMoved(px, py)

    if not placementDragCompleted and love.mouse.isDown(actionButton) then
        if px and py and placementDragStartX and placementDragStartY then
            local width, height = px - placementDragStartX, py - placementDragStartY

            dragChanged(placementDragStartX, placementDragStartY, width, height)
        end
    end
end

function tool.mousereleased(x, y, button, istouch, presses)
    local actionButton = configs.editor.toolActionButton

    if button == actionButton then
        dragFinished()
        placePointPlacement()
    end
end

function tool.keypressed(key, scancode, isrepeat)
    local room = state.getSelectedRoom()
end

function tool.update(dt)
    updatePlacement()
end

function tool.draw()
    local room = state.getSelectedRoom()

    if room then
        drawPlacement(room)
    end
end

return tool