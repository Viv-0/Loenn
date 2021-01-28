local utils = require("utils")
local tasks = require("task")

local toolHandler = {}

toolHandler.tools = {}
toolHandler.currentTool = nil
toolHandler.currentToolName = nil

function toolHandler.selectTool(name)
    local handler = toolHandler.tools[name]

    if handler then
        toolHandler.currentTool = handler
        toolHandler.currentToolName = name
    end

    return handler ~= nil
end

function toolHandler.loadTool(filename)
    local pathNoExt = utils.stripExtension(filename)
    local filenameNoExt = utils.filename(pathNoExt, "/")

    local handler = utils.rerequire(pathNoExt)
    local name = handler.name or filenameNoExt

    print("! Loaded tool '" .. name ..  "'")

    toolHandler.tools[name] = handler

    if not toolHandler.currentTool then
        toolHandler.selectTool(name)
    end

    return name
end

local function getHandler(name)
    name = name or toolHandler.currentToolName

    return toolHandler.tools[name]
end

function toolHandler.getMaterials(name, layer)
    local handler = getHandler(name)

    if handler and handler.getMaterials then
        return handler.getMaterials(layer)
    end

    return {}
end

function toolHandler.setMaterial(material, name)
    local handler = getHandler(name)

    if handler then
        local oldMaterial = toolHandler.getMaterial(name)

        if handler.setMaterial then
            return handler.setMaterial(material, oldMaterial)
        end
    end

    return false
end

function toolHandler.getMaterial(name)
    local handler = getHandler(name)

    if handler then
        if handler.getMaterial then
            return handler.getMaterial()

        else
            return handler.material
        end
    end

    return false
end

function toolHandler.getLayers(name)
    local handler = getHandler(name)

    if handler then
        if handler.getLayers then
            return handler.getLayers()

        else
            return handler.validLayers
        end
    end

    return {}
end

function toolHandler.setLayer(layer, name)
    local handler = getHandler(name)

    if handler then
        local oldLayer = toolHandler.getLayer(name)

        if handler.setLayer then
            return handler.setLayer(layer, oldLayer)

        elseif handler.layer then
            handler.layer = layer
        end
    end

    return false
end

function toolHandler.getLayer(name)
    local handler = getHandler(name)

    if handler then
        if handler.getLayer then
            return handler.getLayer()

        else
            return handler.layer
        end
    end

    return false
end

function toolHandler.loadInternalTools(path)
    path = path or "tools"

    for i, file <- love.filesystem.getDirectoryItems(path) do
        -- Always use Linux paths here
        toolHandler.loadTool(utils.joinpath(path, file):gsub("\\", "/"))

        tasks.yield()
    end

    tasks.update(toolHandler.tools)
end

return toolHandler