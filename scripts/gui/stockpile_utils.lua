function invert(tab)
    local result = {}
    for k,v in pairs(tab) do
        result[v]=k
    end
    return result
end

function processArgs(args, validArgs)
    --[[
    standardized argument processing for scripts
    -argName value
    -argName [list of values]
    -argName [list of [nested values] -that can be [whatever] format of matched square brackets]
    -arg1 \-arg3
        escape sequences
    --]]
    local result = {}
    local argName
    local bracketDepth = 0
    for i,arg in ipairs(args) do
        if argName then
            if arg == '[' then
                if bracketDepth > 0 then
                    table.insert(result[argName], arg)
                end
                bracketDepth = bracketDepth+1
            elseif arg == ']' then
                bracketDepth = bracketDepth-1
                if bracketDepth > 0 then
                    table.insert(result[argName], arg)
                else
                    argName = nil
                end
            elseif string.sub(arg,1,1) == '\\' then
                if bracketDepth == 0 then
                    result[argName] = string.sub(arg,2)
                    argName = nil
                else
                    table.insert(result[argName], string.sub(arg,2))
                end
            else
                if bracketDepth == 0 then
                    result[argName] = arg
                    argName = nil
                else
                    table.insert(result[argName], arg)
                end
            end
        elseif string.sub(arg,1,1) == '-' then
            argName = string.sub(arg,2)
            if validArgs and not validArgs[argName] then
                error('error: invalid arg: ' .. i .. ': ' .. argName)
            end
            if result[argName] then
                error('duplicate arg: ' .. i .. ': ' .. argName)
            end
            if i+1 > #args or string.sub(args[i+1],1,1) == '-' then
                result[argName] = ''
                argName = nil
            else
                result[argName] = {}
            end
        else
            error('error parsing arg ' .. i .. ': ' .. arg)
        end
    end
    return result
end


