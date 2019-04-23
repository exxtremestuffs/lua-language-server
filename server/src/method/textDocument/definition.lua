local core = require 'core'

local function findResult(lsp, params)
    local uri = params.textDocument.uri
    local vm, lines = lsp:loadVM(uri)
    if not vm then
        return nil
    end

    -- lua是从1开始的，因此都要+1
    local position = lines:positionAsChar(params.position.line + 1, params.position.character)
    local source = core.findSource(vm, position)
    if not source then
        return nil
    end

    local positions, isGlobal = core.definition(vm, position, 'definition')
    if not positions then
        return nil, isGlobal
    end

    local locations = {}
    for i, position in ipairs(positions) do
        local start, finish, valueUri = position[1], position[2], (position[3] or uri)
        local _, valueLines = lsp:loadVM(valueUri)
        if valueLines then
            local start_row,  start_col  = valueLines:rowcol(start)
            local finish_row, finish_col = valueLines:rowcol(finish)
            locations[#locations+1] = {
                uri =  valueUri,
                range = {
                    start = {
                        line = start_row - 1,
                        character = start_col - 1,
                    },
                    ['end'] = {
                        line = finish_row - 1,
                        -- 这里不用-1，因为前端期待的是匹配完成后的位置
                        character = finish_col,
                    },
                }
            }
        else
            locations[#locations+1] = {
                uri =  valueUri,
                range = {
                    start = {
                        line = 0,
                        character = 0,
                    },
                    ['end'] = {
                        line = 0,
                        character = 0,
                    },
                }
            }
        end
    end

    if #locations == 0 then
        return nil, isGlobal
    end

    return locations, isGlobal
end

local LastTask

return function (lsp, params)
    if LastTask then
        LastTask:remove()
        LastTask = nil
    end
    return function (response)
        local clock = os.clock()
        LastTask = ac.loop(0.1, function ()
            local result, isGlobal = findResult(lsp, params)
            if isGlobal and lsp:isWaitingCompile() and os.clock() - clock < 1 then
                return
            end
            response(result)
            LastTask:remove()
            LastTask = nil
        end)
        LastTask:onTimer()
    end
end
