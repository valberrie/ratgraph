params = {window_x = 1920, window_y = 1080, scale = 2}

local a = 10
local v = {val = 10}
local checked = false;

function docrap ()
    beginV()
        button("test")
        if button("click me and i will print;") then
            print("hello")
        end
        button("test2")
        checked = checkbox("check box", checked)
        if checked then
            button("this is the next")
        end
        label("Hello") button("another button")
        pushHeight(400);
        beginV()
            slider(v)
        endV()
    endV()
end

