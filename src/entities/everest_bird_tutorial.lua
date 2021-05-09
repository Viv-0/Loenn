local birdTutorial = {}

birdTutorial.name = "everest/customBirdTutorial"
birdTutorial.depth = -1000000
birdTutorial.nodeLineRenderType = "line"
birdTutorial.justification = {0.5, 1.0}
birdTutorial.texture = "characters/bird/crow00"
birdTutorial.nodeLimits = {0, -1}
birdTutorial.placements = {
    name = "bird",
    data = {
        faceLeft = true,
        birdId = "",
        onlyOnce = false,
        caw = true,
        info = "TUTORIAL_DREAMJUMP",
        controls = "DownRight,+,Dash,tinyarrow,Jump"
    }
}

function birdTutorial.scale(room, entity)
    return entity.faceLeft and -1 or 1, 1
end

return birdTutorial