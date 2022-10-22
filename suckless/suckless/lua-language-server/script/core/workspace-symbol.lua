local files    = require 'files'
local guide    = require 'parser.guide'
local matchKey = require 'core.matchkey'
local define   = require 'proto.define'
local await    = require 'await'
local vm       = require 'vm'

local function buildSource(uri, source, key, results)
    if     source.type == 'local'
    or     source.type == 'setlocal'
    or     source.type == 'setglobal' then
        local name = source[1]
        if matchKey(key, name) then
            results[#results+1] = {
                name  = name,
                kind  = define.SymbolKind.Variable,
                uri   = uri,
                range = { source.start, source.finish },
            }
        end
    elseif source.type == 'setfield'
    or     source.type == 'tablefield' then
        local field = source.field
        local name  = field and field[1]
        if name and matchKey(key, name) then
            results[#results+1] = {
                name  = name,
                kind  = define.SymbolKind.Field,
                uri   = uri,
                range = { field.start, field.finish },
            }
        end
    elseif source.type == 'setmethod' then
        local method = source.method
        local name   = method and method[1]
        if name and matchKey(key, name) then
            results[#results+1] = {
                name  = name,
                kind  = define.SymbolKind.Method,
                uri   = uri,
                range = { method.start, method.finish },
            }
        end
    end
end

local function searchFile(uri, key, results)
    local ast = files.getState(uri)
    if not ast then
        return
    end

    guide.eachSource(ast.ast, function (source)
        buildSource(uri, source, key, results)
    end)
end

---@async
---@param key string
---@param results table[]
local function searchGlobalAndClass(key, results)
    for _, global in pairs(vm.getAllGlobals()) do
        local name = global:getCodeName()
        if matchKey(key, name) then
            for _, set in ipairs(global:getAllSets()) do
                local kind
                if set.type == 'doc.class' then
                    kind = define.SymbolKind.Class
                elseif set.type == 'doc.alias' then
                    kind = define.SymbolKind.Namespace
                else
                    kind = define.SymbolKind.Variable
                end
                results[#results+1] = {
                    name  = name,
                    kind  = kind,
                    uri   = guide.getUri(set),
                    range = { set.start, set.finish },
                }
            end
            await.delay()
        end
    end
end

---@async
---@param key string
---@param results table[]
local function searchClassField(key, results)
    local class, inField = key:match('^(.+)%.(.-)$')
    if not class then
        return
    end
    local global = vm.getGlobal('type', class)
    if not global then
        return
    end
    local set = global:getAllSets()[1]
    if not set then
        return
    end
    local suri = guide.getUri(set)
    vm.getClassFields(suri, global, nil, false, function (field, isMark)
        if field.type == 'generic' then
            return
        end
        ---@cast field -vm.generic
        local keyName = guide.getKeyName(field)
        if not keyName then
            return
        end
        if not matchKey(inField, keyName) then
            return
        end
        results[#results+1] = {
            name  = class .. '.' .. keyName,
            kind  = define.SymbolKind.Field,
            uri   = guide.getUri(field),
            range = { field.start, field.finish },
        }
    end)
end

---@async
---@param key string
---@param results table[]
local function searchWords(key, results)
    for uri in files.eachFile() do
        searchFile(uri, key, results)
        if #results > 1000 then
            break
        end
        await.delay()
    end
end

---@async
return function (key)
    local results = {}

    searchGlobalAndClass(key, results)
    searchClassField(key, results)
    searchWords(key, results)

    return results
end
