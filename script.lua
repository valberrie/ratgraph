params = {window_x = 800, window_y = 600, scale = 1.4}

local a = 10
local v = {val = 10}
local checked = false;

local str = getStruct()
for k,v in pairs(str) do
    print(k,v)
end

printStack()
giveData( 32, {name = "fuck", num = 112})

function docrap ()
    beginV()
        button("fuck")
        if button("CLICK ME AND I WILL print;") then
            print("hello")
        end
        button("fuck")
        checked = checkbox("ficking", checked)
        label("Hello") button("fuck")
        pushHeight(400);
        beginV()
            slider(v)
        endV()
    endV()
end
