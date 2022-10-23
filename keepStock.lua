-- config --

-- cpuName should be used when crafting fluid drops
-- since ae2fc internally clear `finalOutput` of cpu when start crafting fluid
-- and the `isDone` callback from `reqeuest` will instantly be true
local itemList = {
    {
        -- drop of Perditio Gas
        databaseSlot = 1,
        stockTarget = 3200000,
        cpuName = "1",
    },
    {
        -- drop of Venenum Gas
        databaseSlot = 2,
        stockTarget = 2800000,
        cpuName = "2",
    },
    {
        -- drop of Mortuus Gas
        databaseSlot = 3,
        stockTarget = 2800000,
        cpuName = "3",
    },
    {
        -- drop of Vitium Gas
        databaseSlot = 4,
        stockTarget = 127000000,
        cpuName = "4",
    }
}

-- if you want to use this function, give a standby signal when your processing machine is on standby
-- when standbySignalSide is nil or not set, then use as many redundant cpus as possible
local standbySignalSide = "down"
-- !TODO implement redundant pool for non-cpuspecific scenarios
local redundantCpuPool = { "5", "6" }

local emitRedstoneSignal = true
local redstoneEmitSide = "up"

-- calculated config, don't change
local hasAnySpecificCpu = false
for _, item in ipairs(itemList) do
    if item.cpuName then
        hasAnySpecificCpu = true
        break
    end
end

-- import --
local component = require("component")
local sides = require("sides")
local redstone
if emitRedstoneSignal then
    redstone = component.redstone
end
local meInterface = component.me_interface
local db = component.database

-- global variables --
local craftables
local itemTable = {}

local function getRSInput(side)
    return redstone.getInput(sides[side])
end

local function setRSOutput(side, value)
    redstone.setOutput(sides[side], value)
end

local function initialize()
    craftables = meInterface.getCraftables()
    -- construct a new table that contains request function, item label and stockTarget
    -- if the item in the itemList doesn't exist in craftables, then don't include it in the table
    for _, item in ipairs(itemList) do
        local itemStack = db.get(item.databaseSlot)
        if itemStack then
            for _, craftable in ipairs(craftables) do
                if craftable.getItemStack().label == itemStack.label then
                    table.insert(itemTable, {
                        request = craftable.request,
                        label = itemStack.label,
                        craftSize = craftable.getItemStack().size,
                        stockTarget = item.stockTarget,
                        -- if specified cpuName, when crafting, craftingStatus is true, else nil
                        -- if not specified cpuName, when crafting, craftingStatus is the userdata callback, else nil
                        craftingStatus = nil,
                        cpuName = item.cpuName,
                    })
                    break
                end
            end
        end
    end
end

local function getItemInNetwork(itemLabel)
    return meInterface.getItemsInNetwork({ label = itemLabel })[1]
end

local function getBusyNamedCpus()
    local busyCpus = {}
    for _, cpu in ipairs(meInterface.getCpus()) do
        if cpu.name ~= "" and cpu.busy then
            busyCpus[cpu.name] = true
        end
    end
    return busyCpus
end

-- this function will reqeust item if the item is not enough in the network
-- it returns the userdata returned by `request` function if request succeeded, else false
local function tryRequest(request, label, stockTarget, amount, cpuName)
    local itemInNetwork = getItemInNetwork(label)
    if itemInNetwork.size < stockTarget then
        local result
        if amount then
            if cpuName then
                result = request(amount, false, cpuName)
            else
                result = request(amount)
            end
        else
            result = request()
        end
        if not result.isCanceled() then
            return {
                isDone = result.isDone,
                isCanceled = result.isCanceled,
                itemInNetworkSize = itemInNetwork.size,
            }
        end
    end

    return false
end

local function tick()
    local hasItemCrafting = false
    local busyCpus
    if hasAnySpecificCpu then
        busyCpus = getBusyNamedCpus()
    end
    for _, item in ipairs(itemTable) do
        -- when specified cpuName, we only check if the cpu is available
        if item.cpuName then
            if busyCpus[item.cpuName] then
                -- if the main cpu is busy but standby signal is present
                -- then we try to use the redundant cpus
                if not standbySignalSide or getRSInput(standbySignalSide) > 0 then
                    for _, redundantCpuName in ipairs(redundantCpuPool) do
                        if not busyCpus[redundantCpuName] then
                            local result = tryRequest(item.request, item.label, item.stockTarget, 1, redundantCpuName)
                            if result then
                                busyCpus[redundantCpuName] = true
                                print(string.format("Requesting %s, current: %d, with redundant cpu %s", item.label,
                                    result.itemInNetworkSize, redundantCpuName))
                            end
                        end
                    end
                end
            else
                local result = tryRequest(item.request, item.label, item.stockTarget, 1, item.cpuName)
                if result then
                    print(string.format("Requesting %s, current: %d", item.label, result.itemInNetworkSize))
                    item.craftingStatus = true
                else
                    item.craftingStatus = nil
                end
            end
            -- else we check if the crafting is done through the callback
        elseif item.craftingStatus == nil or item.craftingStatus.isDone() or item.craftingStatus.isCanceled() then
            local result = tryRequest(item.request, item.label, item.stockTarget)
            if result then
                print(string.format("Requesting %s, current: %d", item.label, result.itemInNetworkSize))
                item.craftingStatus = result
            else
                item.craftingStatus = nil
            end
        end

        if item.craftingStatus then
            hasItemCrafting = true
        end
    end

    if emitRedstoneSignal then
        -- check if there is any redundant cpu busy
        for _, redundantCpuName in ipairs(redundantCpuPool) do
            if busyCpus[redundantCpuName] then
                hasItemCrafting = true
                break
            end
        end

        -- we assume if the standby signal not present, then we should emit signal
        if standbySignalSide and getRSInput(standbySignalSide) == 0 then
            hasItemCrafting = true
        end

        -- when there is any item crafting, emit redstone signal
        if hasItemCrafting then
            setRSOutput(redstoneEmitSide, 15)
        else
            setRSOutput(redstoneEmitSide, 0)
        end
    end
end

local function main()
    initialize()

    while true do
        tick()
    end
end

main()
