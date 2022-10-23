local component = require("component")
local meInterface = component.me_interface

for _, craftable in ipairs(meInterface.getCraftables()) do
    print(craftable.getItemStack().label)
end
