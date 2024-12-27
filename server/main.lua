Core = {
    Functions = {},
    Players = {},
    Stats = {},
    Shared = Shared
}

exports('GetCore', function() return Core end) -- kekw

-- WE CAN DO  Core = exports["kCore"]:GetCore() (for now, exports will be prio but i've not got round to add every one yet.)
-- To use all the framework functions/getters in other resources. 

function Core.Functions.GetCharacterSlots(identifier, cb)
    MySQL.Async.fetchAll('SELECT id, char_slot, citizenid, first_name, last_name, money, job, position, stats, appearance FROM characters WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(results)
        local slots = {}
        for i = 1, Config.MaxCharacterSlots do
            slots[i] = nil
        end
        
        for _, char in ipairs(results) do 
            slots[char.char_slot] = {
                id = char.id,
                citizenid = char.citizenid,
                Name = {
                    first_name = char.first_name,
                    last_name = char.last_name
                },
                Stats = json.decode(char.stats),
                Appearance = json.decode(char.appearance),
                Money = json.decode(char.money),
                Job = json.decode(char.job),
                position = json.decode(char.position)
            }
        end

        cb({
            characters = slots,
            maxSlots = Config.MaxCharacterSlots
        })
    end)
end exports('GetCharacterSlots', Core.Functions.GetCharacterSlots)



function Core.Functions.CreateCharacter(identifier, slot, data, source, cb)
    local citizenid = Core.Functions.GenerateUID()
    local defaultAppearance = {
        model = data.sex == 'male' and "mp_m_freemode_01" or "mp_f_freemode_01",
        clothing = {},
        genetics = {
            mother = 21,
            father = 0,
            shapeMix = 0.5,
            skinMix = 0.5
        },
        faceFeatures = {},
        headOverlays = {}
    }

    local defaultInventory = {
        maxWeight = 100,
        rows = 10,
        columns = 10,
        items = {}
    }

    local defaultJob = {
        name = "unemployed",
        grade = 0
    }

    MySQL.Async.execute([[
        INSERT INTO characters 
        (identifier, char_slot, citizenid, first_name, last_name, money, job, appearance, inventory) 
        VALUES (@identifier, @slot, @citizenid, @firstName, @lastName, @money, @job, @appearance, @inventory)
    ]], {
        ['@identifier'] = identifier,
        ['@slot'] = slot,
        ['@citizenid'] = citizenid,
        ['@firstName'] = data.firstName,
        ['@lastName'] = data.lastName,
        ['@money'] = json.encode({cash = Config.StartingMoney, bank = Config.StartingBank}),
        ['@job'] = json.encode(defaultJob),
        ['@appearance'] = json.encode(defaultAppearance),
        ['@inventory'] = json.encode(defaultInventory)
    }, function(rowsChanged)
        if rowsChanged > 0 then
            print('test')
            Core.Functions.LoadCharacter(source, citizenid, true)
            cb(true, citizenid)
        else
            cb(false)
        end
    end)
end exports('CreateCharacter', Core.Functions.CreateCharacter)



function Core.Functions.GetPlayer(source)
    if not source then 
        return nil 
    end
    
    source = tonumber(source)
    if not source then 
        return nil 
    end
    
    local player = Core.Players[source]
    return player
end


local function formatItemData(item, sharedItem)
    return {
        id = item.id,
        name = item.name,
        image = sharedItem.image,
        size = sharedItem.size or { width = 1, height = 1 },
        position = item.position,
        rotation = item.rotation or 0,
        rarity = sharedItem.rarity or "common",
        inventoryId = item.inventoryId,
        isUnique = sharedItem.unique,
        count = item.count or 1,
        maxStack = sharedItem.maxStack or 64,
        description = sharedItem.description,
        type = sharedItem.type or "item",
        shouldCloseInventory = sharedItem.shouldCloseInventory
    }
end


function Core.Functions.LoadCharacter(source, citizenid, isNewCharacter)
    if not source or not citizenid then 
        print("^1Error: Invalid source or citizenid in LoadCharacter^7")
        return false 
    end
    
    source = tonumber(source)
    if not source then 
        print("^1Error: Invalid source type in LoadCharacter^7")
        return false 
    end

    MySQL.Async.fetchAll('SELECT * FROM characters WHERE citizenid = @citizenid LIMIT 1', {
        ['@citizenid'] = citizenid
    }, function(result)
        if result and result[1] then
            local char = result[1]
            local self = {}
            
            print('[debug] loading character money '..char.money)
            self.source = source
            self.citizenid = citizenid
            self.Money = json.decode(char.money) or {
                cash = 0,
                bank = 0
            }
            self.Job = json.decode(char.job) or { -- fallback
                name = "unemployed",
                grade = 0
            }
            if isNewCharacter then
                self.position = Config.StartingPosition
            else
                self.position = json.decode(char.position) or Config.StartingPosition
            end
            self.Name = {
                first_name = char.first_name,
                last_name = char.last_name
            }
            self.Stats = json.decode(char.stats) or {
                hunger = 100,
                thirst = 100
            }
            self.Appearance = json.decode(char.appearance) or { -- fallback
                model = "mp_m_freemode_01",
                clothing = {},
                genetics = {},
                faceFeatures = {},
                headOverlays = {}
            }
            self.Inventory = json.decode(char.inventory) or { -- fallback
                maxWeight = 100, -- set to config later
                rows = 10, -- set to config later
                columns = 10, -- set to config later
                items = {}
            }

    
            self.Functions = {
                Save = function()
                    SavePlayerData(self.source)
                end,
                
                UpdateMoney = function(moneytype, amount)
                    if moneytype == "cash" then
                        self.Money.cash = amount
                    elseif moneytype == "bank" then
                        self.Money.bank = amount
                    end
                    self.Functions.Save()
                end,

                UpdateJob = function(job)
                    self.Job = job
                    self.Functions.Save()
                end,
                
                UpdateAppearance = function(AppearanceData)
                    local safeAppearance = {
                        model = AppearanceData.model or self.Appearance.model,
                        clothing = AppearanceData.clothing or {},
                        genetics = AppearanceData.genetics or {},
                        faceFeatures = AppearanceData.faceFeatures or {},
                        headOverlays = AppearanceData.headOverlays or {}
                    }
                    self.Appearance = safeAppearance
                    self.Functions.Save()
                    return true
                end,
                
                GetAppearance = function()
                    return self.Appearance
                end,
                
                UpdateInventory = function(inventory)
                    print('[' .. self.citizenid .. '] Updating inventory', inventory)                    


                    self.Inventory = inventory
                    MySQL.Async.execute([[
                        UPDATE characters 
                        SET inventory = @inventory
                        WHERE citizenid = @citizenid
                    ]], {
                        ['@inventory'] = json.encode(inventory),
                        ['@citizenid'] = self.citizenid
                    }, function(rowsChanged)
                        if rowsChanged == 0 then
                            print("^1Failed to update inventory for player " .. self.citizenid .. "^7")
                        else
                            print("^2Successfully saved inventory to database^7")
                        end
                    end)
                    print(self.source)
                    TriggerClientEvent('kCore:refreshInventory', self.source, {
                        id = 'player',
                        name = 'Player Inventory',
                        rows = self.Inventory.rows,
                        columns = self.Inventory.columns,
                        items = self.Inventory.items
                    })
                    return true
                end,
                
                
            }
 
            Core.Players[source] = self
            
            print("^2Loaded character^7")
            print("Source:", self.source)
            print("CitizenID:", self.citizenid)
            
            TriggerClientEvent('kCore:loadPlayer', source, self, isNewCharacter)
            return true
        else
            print('^1Error: No character found for citizenid^7:', citizenid)
            return false
        end
    end)
end


function SavePlayerData(source)  -- rework eventually 
    local Player = Core.Functions.GetPlayer(source)
    if Player then
        local ped = GetPlayerPed(source)
        print(GetEntityCoords(ped), ped)
        local pos = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        

        local position = { -- fallback incase something goes weird
            x = pos.x or Config.StartingPosition.x,
            y = pos.y or Config.StartingPosition.y,
            z = pos.z or Config.StartingPosition.z,
            heading = heading or Config.StartingPosition.heading
        }

        print(json.encode(position), source, ' INFO')

        local saveData = {
            money = json.encode(Player.Money),
            position = json.encode(position),
            stats = json.encode(Player.Stats),
            inventory = json.encode(Player.Inventory),
            job = json.encode(Player.Job),  
            citizenid = Player.citizenid
        }

        MySQL.Async.execute([[
            UPDATE characters 
            SET money = @money, 
                position = @position, 
                stats = @stats,
                job = @job,
                inventory = @inventory,
                last_updated = CURRENT_TIMESTAMP 
            WHERE citizenid = @citizenid
        ]], saveData, function(rowsChanged)
            if rowsChanged == 0 then
                print("^1Failed to update database for player " .. source .. " (CitizenID: " .. Player.citizenid .. ")^7")
            else
                print("^2Successfully saved player data to database^7")
            end
        end)

        return true
    end
    return false
end

function Core.Functions.SelectCharacter(id, slot, source, cb) 
    local identifier = GetPlayerIdentifier(source)
    
    if not identifier then 
        print("^1Error: No identifier found for source^7:", source)
        return 
    end
    
    print("^2Processing character selection^7")
    print("Source:", source)
    print("Identifier:", identifier)
    print("Slot:", slot)
    
    MySQL.Async.fetchAll('SELECT citizenid FROM characters WHERE identifier = @identifier AND char_slot = @slot', {
        ['@identifier'] = identifier,
        ['@slot'] = slot
    }, function(result)
        if result and result[1] then
            print("^2Loading existing character^7")
            Core.Functions.LoadCharacter(source, result[1].citizenid, false)
        end
    end)
end exports('SelectCharacter', Core.Functions.SelectCharacter)


function Core.Functions.UpdatePlayerAppearance(source, AppearanceData)
    local Player = Core.Functions.GetPlayer(source)
    if Player then
        return Player.Functions.UpdateAppearance(AppearanceData)
    end
    return false
end


AddEventHandler('playerDropped', function()
    local source = source
    if Core.Players[source] then
        Core.Players[source].Functions.Save()
        Core.Players[source] = nil
    end
end)
function Core.Functions.IsPlayerInitialized(source)
    return Core.Players[source] ~= nil
end



