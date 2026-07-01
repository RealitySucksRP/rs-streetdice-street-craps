-- rs-streetdice item install file
--
-- Grant/Cfx scanners may parse every .lua file as a standalone Lua chunk.
-- That means this file must be a valid Lua file by itself.
--
-- For qb-core/shared/items.lua, copy ONLY the inner streetdice entry into QBShared.Items.

return {
    streetdice = {
        name = 'streetdice',
        label = 'Street Dice',
        weight = 100,
        type = 'item',
        image = 'streetdice.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'A pair of dice used to start a street craps game.'
    }
}
