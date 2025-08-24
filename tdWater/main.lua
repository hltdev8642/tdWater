-- Improved Water Emitter Code

function createWaterEmitter()
    local emitter = {}  -- Create the emitter table

    -- Set properties
    emitter.flowRate = 1.0  -- Default flow rate
    emitter.color = {0, 0, 1, 1}  -- Blue color for water

    -- Function to emit water
    function emitter:emit()
        print("Emitting water...")
        -- Logic for emitting water
    end

    return emitter
end

-- Example usage
local waterEmitter = createWaterEmitter()
waterEmitter:emit()