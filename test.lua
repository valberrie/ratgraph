setBgColor("Black")

local tex1 = loadTexture("icon.png")
local posx =  0;
local posy = 0;
function loop()
    local wdim = getScreenSize()
    rectTex({x = posx, y = posy + 100, w = 100,h = 100}, tex1)

    if keydown("A") then posx = posx - 10 end
    if keydown("D") then posx = posx + 10 end
    if keydown("S") then posy = posy + 10 end
    if keydown("W") then posy = posy - 10 end

    rect(0,0,0,0)
    text(mousePos(), "cras",22)
end
