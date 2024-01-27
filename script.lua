params = {window_x = 1920, window_y = 1080, scale = 2}

local a = 10
local v = {val = 10}
local checked = false;

function docrap ()
    beginV()
        button("fuck")
        if button("CLICK ME AND I WILL print;") then
            print("hello")
        end
        button("fuck")
        checked = checkbox("ficking", checked)
        if checked then
            button("this is the next")
        end
        label("Hello") button("fuck")
        pushHeight(400);
        beginV()
            slider(v)
        endV()
    endV()
end

