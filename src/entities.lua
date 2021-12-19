local utils = require("utils")
local pluginLoader = require("plugin_loader")
local modHandler = require("mods")
local configs = require("configs")
local drawing = require("utils.drawing")
local nodeStruct = require("structs.node")
local logging = require("logging")

local languageRegistry = require("language_registry")

local drawableSprite = require("structs.drawable_sprite")
local drawableFunction = require("structs.drawable_function")
local drawableRectangle = require("structs.drawable_rectangle")

local missingTextureName = modHandler.internalModContent .. "/missing_image"

local colors = require("consts.colors")

local entities = {}

local missingEntityHandler = require("defaults.viewer.undefined_entity")
local erroringEntityHandler = require("defaults.viewer.erroring_entity")

local entityRegisteryMT = {
    __index = function() return missingEntityHandler end
}

entities.registeredEntities = nil

local seenEntityErrors = {}

local function logEntityDefinitionError(definitionName, message, room, entity)
    -- Only log errors once per entity instance per definition (rendering, selection, etc)
    -- This should be safe enough for more uses
    local seenKey = string.format("%s-%p-%s", entity._name, entity, definitionName)

    if not seenEntityErrors[seenKey] then
        -- TODO - Event for UI
        local entityInformation = string.format("Erroring entity definition for '%s' in room '%s' at (%d, %d) when %s", entity._name, room.name, entity.x, entity.y, definitionName)

        logging.warning(entityInformation)
        logging.warning(debug.traceback(message))

        seenEntityErrors[seenKey] = true
    end
end

function entities.initLogging()
    seenEntityErrors = {}
end

-- Sets the registry to the given table (or empty one) and sets the missing entity metatable
function entities.initDefaultRegistry(t)
    entities.registeredEntities = setmetatable(t or {}, entityRegisteryMT)
end

local function addHandler(handler, registerAt, filenameNoExt, filename, verbose)
    local name = handler.name or filenameNoExt

    registerAt[name] = handler

    if verbose then
        logging.info("Registered entity '" .. name .. "' from '" .. filename .."'")
    end
end

function entities.registerEntity(filename, registerAt, verbose)
    -- Use verbose flag or default to logPluginLoading from config
    verbose = verbose or verbose == nil and configs.debug.logPluginLoading
    registerAt = registerAt or entities.registeredEntities

    local pathNoExt = utils.stripExtension(filename)
    local filenameNoExt = utils.filename(pathNoExt, "/")

    local handler = utils.rerequire(pathNoExt)

    utils.callIterateFirstIfTable(addHandler, handler, registerAt, filenameNoExt, filename, verbose)
end

function entities.loadEntities(path, registerAt)
    pluginLoader.loadPlugins(path, registerAt, entities.registerEntity)
end

function entities.loadInternalEntities(registerAt)
    return entities.loadEntities("entities", registerAt)
end

function entities.loadExternalEntities(registerAt)
    local filenames = modHandler.findPlugins("entities")

    return entities.loadEntities(filenames, registerAt)
end

local function addAutomaticDrawableFields(handler, drawable, room, entity, isNode)
    local justificationKey = isNode and "nodeJustification" or "justification"
    local scaleKey = isNode and "nodeScale" or "scale"
    local offsetKey = isNode and "nodeOffset" or "offset"
    local rotationKey = isNode and "nodeRotation" or "rotation"
    local colorKey = isNode and "nodeColor" or "color"
    local depthKey = isNode and "nodeDepth" or "depth"

    if handler[justificationKey] then
        if type(handler[justificationKey]) == "function" then
            drawable:setJustification(handler[justificationKey](room, entity))

        else
            drawable:setJustification(unpack(handler[justificationKey]))
        end
    end

    if handler[scaleKey] then
        if type(handler[scaleKey]) == "function" then
            drawable:setScale(handler[scaleKey](room, entity))

        else
            drawable:setScale(unpack(handler[scaleKey]))
        end
    end

    if handler[offsetKey] then
        if type(handler[offsetKey]) == "function" then
            drawable:setOffset(handler[offsetKey](room, entity))

        else
            drawable:setOffset(unpack(handler[offsetKey]))
        end
    end

    if handler[rotationKey] then
        drawable.rotation = utils.callIfFunction(handler[rotationKey], room, entity)
    end

    if handler[colorKey] then
        drawable.color = utils.callIfFunction(handler[colorKey], room, entity)
    end

    if handler[depthKey] then
        drawable.depth = utils.callIfFunction(handler[depthKey], room, entity)
    end
end

-- Returns drawable, depth
function entities.getEntityDrawable(name, handler, room, entity, viewport)
    handler = handler or entities.registeredEntities[name]

    local defaultDepth = utils.callIfFunction(handler.depth, room, entity, viewport)

    if handler.sprite then
        local sprites = handler.sprite(room, entity, viewport)

        if sprites then
            if #sprites == 0 and utils.typeof(sprites) == "drawableSprite" then
                return sprites, sprites.depth or defaultDepth

            else
                return sprites, defaultDepth
            end
        end

    elseif handler.texture then
        local texture = utils.callIfFunction(handler.texture, room, entity)
        local position = {
            x = entity.x,
            y = entity.y
        }
        local drawable = drawableSprite.fromTexture(texture, position)

        if drawable then
            addAutomaticDrawableFields(handler, drawable, room, entity, false)

        else
            drawable = drawableSprite.fromTexture(missingTextureName, entity)

            if configs.editor.warnOnMissingTexture then
                logging.warning(string.format("Could not find texture '%s' for entity '%s' in room '%s'", texture, entity._name, room.name))
            end
        end

        return drawable

    elseif handler.draw then
        return drawableFunction.fromFunction(handler.draw, room, entity, viewport)

    elseif handler.rectangle or entity.width and entity.height then
        local rectangle
        local drawableSprites

        if handler.rectangle then
            rectangle = handler.rectangle(room, entity, viewport)

        else
            rectangle = utils.rectangle(entity.x, entity.y, entity.width, entity.height)
        end

        -- If both fillColor and borderColor is specified then make a rectangle with these
        if handler.fillColor and handler.borderColor then
            local fillColor = utils.callIfFunction(handler.fillColor, room, entity)
            local borderColor = utils.callIfFunction(handler.borderColor, room, entity)

            drawableSprites = drawableRectangle.fromRectangle("bordered", rectangle, fillColor, borderColor):getDrawableSprite()

        else
            local color = utils.callIfFunction(handler.color, room, entity)

            drawableSprites = drawableRectangle.fromRectangle(handler.mode or "fill", rectangle, color or colors.default)
        end

        -- Add depth to sprite(s)
        if drawableSprites then
            if utils.typeof(drawableSprites) == "table" then
                for _, sprite in ipairs(drawableSprites) do
                    sprite.depth = defaultDepth
                end
            end

        else
            drawableSprites.defaultDepth = defaultDepth
        end

        return drawableSprites
    end
end

function entities.getNodeDrawable(name, handler, room, entity, node, nodeIndex, viewport)
    handler = handler or entities.registeredEntities[name]

    local defaultDepth = utils.callIfFunction(handler.nodeDepth, room, entity, node, nodeIndex, viewport)

    if handler.nodeSprite then
        local sprites = handler.nodeSprite(room, entity, node, nodeIndex, viewport)

        if sprites then
            if #sprites == 0 and utils.typeof(sprites) == "drawableSprite" then
                return sprites, sprites.depth or defaultDepth, false

            else
                return sprites, defaultDepth, false
            end
        end

    elseif handler.nodeTexture then
        local texture = utils.callIfFunction(handler.nodeTexture, room, entity, node, nodeIndex, viewport)
        local drawable = drawableSprite.fromTexture(texture, node)

        addAutomaticDrawableFields(handler, drawable, room, entity, true)

        return drawable, defaultDepth, false

    elseif handler.nodeDraw then
        return drawableFunction.fromFunction(handler.nodeDraw, room, entity, node, nodeIndex, viewport)

    else
        -- Make a copy of entity and change the position to the node
        -- This makes it correctly render and select at the node rather than main entity

        local entityCopy = table.shallowcopy(entity)

        entityCopy.x = node.x
        entityCopy.y = node.y

        return entities.getEntityDrawable(name, handler, room, entityCopy, viewport), nil, true
    end
end

-- Gets entity drawables
-- Does not check for errors
function entities.getDrawableUnsafe(name, handler, room, entity, viewport)
    handler = handler or entities.registeredEntities[name]

    local nodeVisibility = entities.nodeVisibility("entities", entity)
    local entityDrawable, depth = entities.getEntityDrawable(name, handler, room, entity, viewport)

    -- Add node drawable(s) if the entity asks for it
    if entity.nodes and nodeVisibility == "always" then
        if utils.typeof(entityDrawable) ~= "table" then
            entityDrawable = {entityDrawable}
        end

        for i, node in ipairs(entity.nodes) do
            local nodeDrawable = entities.getNodeDrawable(name, handler, room, entity, node, i, viewport)

            if nodeDrawable then
                if utils.typeof(nodeDrawable) == "table" then
                    for _, drawable in ipairs(nodeDrawable) do
                        table.insert(entityDrawable, drawable)
                    end

                else
                    table.insert(entityDrawable, nodeDrawable)
                end
            end
        end
    end

    return entityDrawable, depth
end

-- Get drawable with pcall, return drawables from the erroring entity handler if not successful
function entities.getDrawable(name, handler, room, entity, viewport)
    local success, drawable, depth = pcall(entities.getDrawableUnsafe, name, handler, room, entity, viewport)

    if success then
        return drawable, depth

    else
        logEntityDefinitionError("rendering", drawable, room, entity)

        return entities.getDrawable(name, erroringEntityHandler, room, entity, viewport)
    end
end

function entities.getDrawableRectangle(drawables)
    if #drawables == 0 and drawables.getRectangle then
        return drawables:getRectangle()
    end

    -- TODO - Inline coverRectangles?
    -- Check if this is expensive enough in larger rooms

    local rectangles = {}

    for i, drawable in ipairs(drawables) do
        if drawable.getRectangle then
            rectangles[i] = drawable:getRectangle()

            if drawable.ignoreRest then
                break
            end
        end
    end

    local x, y, width, height = utils.coverRectangles(rectangles)

    return utils.rectangle(x, y, width, height)
end

function entities.getNodeRectangles(room, entity, viewport)
    local name = entity._name
    local handler = entities.registeredEntities[name]
    local nodes = entity.nodes

    if not nodes then
        return nil
    end

    local rectangles = {}

    local x, y = entity.x or 0, entity.y or 0

    for i, node in ipairs(nodes) do
        if handler.nodeRectangle then
            rectangles[i] = handler.nodeRectangle(room, entity, node, i)

        else
            local nodeDrawable, nodeDepth, usedMainEntityDrawable = entities.getNodeDrawable(name, handler, room, entity, node, i, viewport)
            local nodeRectangle

            if nodeDrawable then
                -- Some extra logic if the drawable is from the entity rather than node functions
                if usedMainEntityDrawable then
                    if handler.rectangle then
                        nodeRectangle = handler.rectangle(room, entity)

                        -- Offset to node position rather than entity
                        nodeRectangle.x += node.x - x
                        nodeRectangle.y += node.y - y

                    elseif entity.width and entity.height then
                        nodeRectangle = utils.rectangle(node.x or 0, node.y or 0, entity.width, entity.height)
                    end
                end

                if not nodeRectangle then
                    nodeRectangle = entities.getDrawableRectangle(nodeDrawable)
                end

                table.insert(rectangles, utils.deepcopy(nodeRectangle))
            end
        end
    end

    return rectangles
end

-- Returns main entity selection rectangle, then table of node rectangles
-- Does not check for errors
function entities.getSelectionUnsafe(room, entity, viewport, handlerOverride)
    local name = entity._name
    local handler = handlerOverride or entities.registeredEntities[name]

    if handler.selection then
        return handler.selection(room, entity)

    elseif handler.rectangle then
        return handler.rectangle(room, entity), entities.getNodeRectangles(room, entity)

    elseif entity.width and entity.height then
        return utils.rectangle(entity.x or 0, entity.y or 0, entity.width, entity.height), entities.getNodeRectangles(room, entity)

    else
        local drawable = entities.getEntityDrawable(name, handler, room, entity)
        local nodeRectangles = entities.getNodeRectangles(room, entity)

        if drawable then
            return entities.getDrawableRectangle(drawable), nodeRectangles
        end
    end
end

-- Get selection with pcall, return selections from the erroring entity handler if not successful
function entities.getSelection(room, entity, viewport, handlerOverride)
    local success, rectangle, nodeRectangles = pcall(entities.getSelectionUnsafe, room, entity, viewport, handlerOverride)

    if success then
        return rectangle, nodeRectangles

    else
        logEntityDefinitionError("selecting", rectangle, room, entity)

        return entities.getSelection(room, entity, viewport, erroringEntityHandler)
    end
end

-- TODO - Implement in more performant way?
function entities.drawSelected(room, layer, entity, color)
    color = color or colors.selectionCompleteNodeLineColor

    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler.drawSelected then
        return handler.drawSelected(room, layer, entity, color)

    else
        local x, y = entity.x or 0, entity.y or 0
        local halfWidth, halfHeight = (entity.width or 0) / 2, (entity.height or 0) / 2
        local nodes = entity.nodes

        if nodes and #nodes > 0 then
            local nodeVisibility = entities.nodeVisibility(layer, entity)
            local nodeLineRenderType = entities.nodeLineRenderType(layer, entity)

            local entityRenderX, entityRenderY = x + halfWidth, y + halfHeight
            local previousX, previousY = entityRenderX, entityRenderY

            for i, node in ipairs(nodes) do
                local nodeDrawable = entities.getNodeDrawable(name, handler, room, entity, node, i)

                if nodeDrawable then
                    if nodeLineRenderType then
                        local nodeX, nodeY = node.x or 0, node.y or 0
                        local nodeRenderX, nodeRenderY = nodeX + halfWidth, nodeY + halfHeight

                        drawing.callKeepOriginalColor(function()
                            love.graphics.setColor(color)

                            if nodeLineRenderType == "line" then
                                love.graphics.line(previousX, previousY, nodeRenderX, nodeRenderY)

                            elseif nodeLineRenderType == "fan" then
                                love.graphics.line(entityRenderX, entityRenderY, nodeRenderX, nodeRenderY)

                            elseif nodeLineRenderType == "circle" then
                                local distance = math.sqrt((nodeRenderX - entityRenderX)^2 + (nodeRenderY - entityRenderY)^2)

                                love.graphics.circle("line", nodeRenderX, nodeRenderY, distance)
                            end
                        end)

                        previousX = nodeRenderX
                        previousY = nodeRenderY
                    end

                    if nodeVisibility == "selected" then
                        if #nodeDrawable > 0 then
                            for _, drawable in ipairs(nodeDrawable) do
                                if drawable.x and drawable.y then
                                    drawable:draw()
                                end
                            end

                        else
                            if nodeDrawable.x and nodeDrawable.y then
                                nodeDrawable:draw()
                            end
                        end
                    end
                end
            end
        end
    end
end

function entities.moveSelection(room, layer, selection, offsetX, offsetY)
    local entity, node = selection.item, selection.node
    local name = entity._name
    local handler = entities.registeredEntities[name]

    -- Notify movement
    if handler.onMove then
        handler.onMove(room, entity, node, offsetX, offsetY)
    end

    -- Custom entity movement
    if handler.move then
        handler.move(room, entity, node, offsetX, offsetY)

    else
        if node == 0 then
            entity.x += offsetX
            entity.y += offsetY

        else
            local nodes = entity.nodes

            if nodes and node <= #nodes then
                local target = nodes[node]

                target.x += offsetX
                target.y += offsetY
            end
        end
    end

    -- Custom selection movement if needed after custom move
    if handler.updateMoveSelection then
        handler.updateMoveSelection(room, entity, node, selection, offsetX, offsetY)

    else
        selection.x += offsetX
        selection.y += offsetY
    end

    return true
end

-- Negative offsets means we are growing up/left, should move the selection as well as changing size
function entities.resizeSelection(room, layer, selection, offsetX, offsetY, directionX, directionY)
    local entity, node = selection.item, selection.node
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if node ~= 0 or offsetX == 0 and offsetY == 0 then
        return false
    end

    -- Notify resize
    if handler.onResize then
        handler.onResize(room, entity, offsetX, offsetY, directionX, directionY)
    end

    local entityOffsetX = 0
    local entityOffsetY = 0
    local madeChanges = false

    if handler.resize then
        madeChanges = handler.resize(room, entity, offsetX, offsetY, directionX, directionY)

    else
        local canHorizontal, canVertical = entities.canResize(room, layer, entity)
        local minimumWidth, minimumHeight = entities.minimumSize(room, layer, entity)
        local maximumWidth, maximumHeight = entities.maximumSize(room, layer, entity)

        local oldWidth, oldHeight = entity.width or 0, entity.height or 0
        local newWidth, newHeight = oldWidth, oldHeight

        if offsetX ~= 0 and canHorizontal then
            newWidth += offsetX * math.abs(directionX)

            if minimumWidth <= newWidth and newWidth <= maximumWidth then
                entity.width = newWidth

                if directionX < 0 then
                    entityOffsetX = -offsetX
                    entity.x -= offsetX
                end

                madeChanges = true
            end
        end

        if offsetY ~= 0 and canVertical then
            newHeight += offsetY * math.abs(directionY)

            if minimumHeight <= newHeight and newHeight <= maximumHeight then
                entity.height = newHeight

                if directionY < 0 then
                    entityOffsetY = -offsetY
                    entity.y -= offsetY
                end

                madeChanges = true
            end
        end
    end

    -- Custom selection resize if needed after custom resize
    if handler.updateResizeSelection then
        handler.updateResizeSelection(room, entity, node, selection, offsetX, offsetY, directionX, directionY)

    else
        selection.x += entityOffsetX
        selection.y += entityOffsetY

        selection.width = entity.width or selection.width
        selection.height = entity.height or selection.height
    end

    return madeChanges
end

function entities.deleteSelection(room, layer, selection)
    local targets = entities.getRoomItems(room, layer)
    local target, node = selection.item, selection.node
    local name = target._name
    local handler = entities.registeredEntities[name]
    local minimumNodes, maximumNodes = entities.nodeLimits(room, layer, target)

    for i, entity in ipairs(targets) do
        if entity == target then
            local nodes = entity.nodes

            -- Delete entity if deleting a node gives it too few nodes
            -- Set node to 0 to move deletion target from node to entity itself
            if nodes and node > 0 then
                local nodeCount = #nodes

                if minimumNodes and minimumNodes ~= -1 and nodeCount - 1 < minimumNodes then
                    node = 0
                end
            end

            -- Notify deletion
            if handler.onDelete then
                handler.onDelete(room, entity, node)
            end

            -- Custom deletion
            if handler.delete then
                return handler.delete(room, entity, node)

            else
                if node == 0 then
                    table.remove(targets, i)

                else
                    if nodes then
                        table.remove(nodes, node)
                    end
                end

                return true
            end
        end
    end

    return false
end

function entities.addNodeToSelection(room, layer, selection)
    local targets = entities.getRoomItems(room, layer)
    local target, node = selection.item, selection.node
    local name = target._name
    local handler = entities.registeredEntities[name]
    local minimumNodes, maximumNodes = entities.nodeLimits(room, layer, target)

    for i, entity in ipairs(targets) do
        if entity == target then
            local nodes = entity.nodes or nodeStruct.decodeNodes({})

            -- Make sure we don't add more nodes than supported
            if #nodes >= maximumNodes and maximumNodes ~= -1 then
                return false
            end

            if not entity.nodes then
                entity.nodes = nodes
            end

            -- Notify addition
            if handler.onNodeAdded then
                handler.onNodeAdded(room, entity, node)
            end

            -- Custom node adding
            if handler.nodeAdded then
                return handler.nodeAdded(room, entity, node)

            else
                if node == 0 then
                    local nodeX = entity.x + (entity.width or 0) + 8
                    local nodeY = entity.y

                    table.insert(nodes, 1, {x = nodeX, y = nodeY})

                else
                    local nodeX = nodes[node].x + (entity.width or 0) + 8
                    local nodeY = nodes[node].y

                    table.insert(nodes, node + 1, {x = nodeX, y = nodeY})
                end

                return true
            end
        end
    end

    return false
end

local function guessPlacementType(name, handler, placement)
    if placement and placement.data then
        if placement.data.width or placement.data.height then
            return "rectangle"
        end

        if placement.data.nodes then
            return "line"
        end
    end

    local fakeEntity = {_name = name}
    local minimumNodes, maximumNodes = entities.nodeLimits(nil, nil, fakeEntity)

    if minimumNodes == 1 and maximumNodes == 1 then
        return "line"
    end

    return "point"
end

local function getPlacements(handler)
    return utils.callIfFunction(handler.placements)
end

local function getDefaultPlacement(handler, placements)
    return placements.default
end

local function getPlacement(placementInfo, defaultPlacement, name, handler, language)
    local placementType = placementInfo.placementType or guessPlacementType(name, handler, placementInfo)
    local modPrefix = modHandler.getEntityModPrefix(name)
    local simpleName = string.format("%s#%s", name, placementInfo.name)
    local displayName = placementInfo.name
    local tooltipText
    local displayNameLanguage = language.entities[name].placements.name[placementInfo.name]
    local tooltipTextLanguage = language.entities[name].placements.description[placementInfo.name]

    if displayNameLanguage._exists then
        displayName = tostring(displayNameLanguage)
    end

    if tooltipTextLanguage._exists then
        tooltipText = tostring(tooltipTextLanguage)
    end

    if modPrefix then
        local modPrefixLanguage = language.mods[modPrefix].name

        if modPrefixLanguage._exists then
            displayName = string.format("%s [%s]", displayName, modPrefixLanguage)
        end
    end

    local itemTemplate = {
        _name = name,
        _id = 0
    }

    if defaultPlacement and defaultPlacement.data then
        for k, v in pairs(defaultPlacement.data) do
            itemTemplate[k] = v
        end
    end

    if placementInfo.data then
        for k, v in pairs(placementInfo.data) do
            itemTemplate[k] = v
        end
    end

    itemTemplate.x = itemTemplate.x or 0
    itemTemplate.y = itemTemplate.y or 0

    local placement = {
        name = simpleName,
        displayName = displayName,
        tooltipText = tooltipText,
        layer = "entities",
        placementType = placementType,
        itemTemplate = itemTemplate
    }

    return placement
end

local function addPlacement(placementInfo, defaultPlacement, res, name, handler, language)
    table.insert(res, getPlacement(placementInfo, defaultPlacement, name, handler, language))
end

-- TODO - Make more sophisticated? Works for now
local function guessPlacementFromData(item, name, handler)
    local placements = utils.callIfFunction(handler.placements)

    if placements then
        if #placements > 0 then
            return placements[1]

        else
            return placements
        end
    end
end

function entities.getPlacements(layer)
    local res = {}
    local language = languageRegistry.getLanguage()

    if entities.registeredEntities then
        for name, handler in pairs(entities.registeredEntities) do
            local placements = getPlacements(handler)

            if placements then
                local defaultPlacement = getDefaultPlacement(handler, placements)

                utils.callIterateFirstIfTable(addPlacement, placements, defaultPlacement, res, name, handler, language)
            end
        end
    end

    return res
end

-- We don't know which placement this is from, but getPlacement does most of the job for us
function entities.cloneItem(room, layer, item)
    local name = item._name
    local handler = entities.registeredEntities[name]
    local language = languageRegistry.getLanguage()

    if handler.cloneItem then
        return handler.cloneItem(room, layer, item)
    end

    local placements = utils.callIfFunction(handler.placements)
    local defaultPlacement = getDefaultPlacement(handler, placements)
    local guessedPlacement = guessPlacementFromData(item, name, handler) or {}
    local placement = getPlacement(guessedPlacement, defaultPlacement, name, handler, language)

    placement.itemTemplate = utils.deepcopy(item)

    return placement
end

function entities.placeItem(room, layer, item)
    local items = entities.getRoomItems(room, layer)

    table.insert(items, item)

    return true
end

function entities.canResize(room, layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler.canResize then
        if type(handler.canResize) == "function" then
            return handler.canResize(room, entity)

        else
            return unpack(handler.canResize)
        end

    else
        return entity.width ~= nil, entity.height ~= nil
    end
end

function entities.minimumSize(room, layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler.minimumSize then
        if type(handler.minimumSize) == "function" then
            return handler.minimumSize(room, entity)

        else
            return unpack(handler.minimumSize)
        end
    end

    return 8, 8
end

function entities.maximumSize(room, layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler.maximumSize then
        if type(handler.maximumSize) == "function" then
            return handler.maximumSize(room, entity)

        else
            return unpack(handler.maximumSize)
        end
    end

    return math.huge, math.huge
end

function entities.nodeLimits(room, layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler and handler.nodeLimits then
        if type(handler.nodeLimits) == "function" then
            return handler.nodeLimits(room, entity)

        else
            return unpack(handler.nodeLimits)
        end

    else
        return 0, 0
    end
end

function entities.nodeLineRenderType(layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler and handler.nodeLineRenderType then
        return utils.callIfFunction(handler.nodeLineRenderType, entity)

    else
        return false
    end
end

function entities.nodeVisibility(layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler and handler.nodeVisibility then
        return utils.callIfFunction(handler.nodeVisibility, entity)

    else
        return "selected"
    end
end

function entities.ignoredFields(layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler and handler.ignoredFields then
        return utils.callIfFunction(handler.ignoredFields, entity)

    else
        return {"_name", "_id", "originX", "originY"}
    end
end

function entities.fieldOrder(layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler and handler.fieldOrder then
        return utils.callIfFunction(handler.fieldOrder, entity)

    else
        local fields = {"x", "y"}

        if entity.width ~= nil then
            table.insert(fields, "width")
        end

        if entity.height ~= nil then
            table.insert(fields, "height")
        end

        return fields
    end
end

function entities.fieldInformation(layer, entity)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    local fieldInfo = {
        x = {
            fieldType = "integer",
        },
        y = {
            fieldType = "integer",
        },

        width = {
            fieldType = "integer"
        },
        height = {
            fieldType = "integer"
        }
    }

    if handler and handler.fieldInformation then
        local customFieldInformation = utils.callIfFunction(handler.fieldInformation, entity)

        for k, v in pairs(customFieldInformation) do
            fieldInfo[k] = v
        end
    end

    return fieldInfo
end

function entities.languageData(layer, entity, language)
    local name = entity._name
    local handler = entities.registeredEntities[name]

    if handler and handler.languageData then
        return handler.languageData(entity)

    else
        return language.entities[name], language.entities.default
    end
end

-- Returns all entities of room
function entities.getRoomItems(room, layer)
    return room.entities
end

entities.initDefaultRegistry()

return entities