-- scrunkly 2 - the dialog interpreter you never wanted
-- rewritten with Better Code Practices

local M = {
  VERSION = "2.0.0-beta.1",
}

M.logger = print

local function print(...)
  if M.logger then
    M.logger(...)
  end
end

local _setfenv = setfenv
local function setfenv(f, table)
  if _setfenv then
    return _setfenv(f, table)
  else
    -- https://leafo.net/guides/setfenv-in-lua52-and-above.html
    local i = 1
    while true do
      local name = debug.getupvalue(f, i)
      if name == "_ENV" then
        debug.upvaluejoin(f, i, (function()
          return table
        end), 1)
        break
      elseif not name then
        break
      end

      i = i + 1
    end

    return f
  end
end

--[=[
    parser
        impl

  - [x] [x] [[label]]

  - [x] [x] say [string]
  - [x] [x] randomsay [string...]
  - [x] [x] call [func]
  - [x] [x] character [char]
  - [x] [x] showcharacter [char]
  - [x] [x] hidecharacter [char]
  - [x] [x] expression [char] [expression]
  - [x] [x] goto [label]
  - [ ] [ ] goto [filename]
  - [ ] [ ] var [name] [value]
  - [x] [x] meta [name] [true | false]
  - [ ] [ ] if (!)(%)[cond] [expr]

  - [x] [x] [string] -> [label]
  - [x] [x] [string] ->

  https://www.lua.org/manual/5.1/manual.html#5.4
  https://gitspartv.github.io/lua-patterns/
]=]

---@class scrunklyOptions
---@field variables table<string, any>?
---@field characters scrunklyCharacter[]?
---@field meta table<string, any>?
---@field startLabel string?
---@field openDialog fun(text: table, meta: table<string, any>, choices: table<string, any>, callback: fun(choice: number?)): nil

---@class scrunklyCharacter
---@field name string
---@field sprites table<string, any>

---@generic T table<any>
---@param tab T
---@return T
local function shallowcopy(tab)
  local new = {}
  for k,v in pairs(tab) do
    new[k] = v
  end
  return new
end

---@generic T table<any>
---@param tab T
---@return T
local function deepcopy(tab)
  local new = {}
  for k, v in pairs(tab) do
    if type(v) == 'table' then
      new[k] = deepcopy(v)
    else
      new[k] = v
    end
  end
  return new
end

---@param o any
---@param r number?
---@return string
local function fullDump(o, r)
  if type(o) == 'table' and (not r or r > 0) then
    local s = '{'
    local first = true
    for k,v in pairs(o) do
      if not first then
        s = s .. ', '
      end
      local nr = nil
      if r then
        nr = r - 1
      end
      if type(k) ~= 'number' then
        s = s .. tostring(k) .. ' = ' .. fullDump(v, nr)
      else
        s = s .. fullDump(v, nr)
      end
      first = false
    end
    return s .. '}'
  elseif type(o) == 'string' then
    return '"' .. o .. '"'
  else
    return tostring(o)
  end
end

---@generic A table<any>
---@generic B table<any>
---@param tab1 A
---@param tab2 B
---@return B
local function merge(tab1, tab2)
  local tab = {}
  for k, v in pairs(tab1) do
    tab[k] = v
  end
  for k, v in pairs(tab2) do
    if type(v) == 'table' and type(tab[k]) == 'table' then
      tab[k] = merge(tab[k], v)
    elseif v ~= nil then
      tab[k] = v
    end
  end
  return tab
end

M.safeEnv = {
  coroutine = shallowcopy(coroutine),
  assert = assert,
  tostring = tostring,
  tonumber = tonumber,
  rawget = rawget,
  xpcall = xpcall,
  ipairs = ipairs,
  print = print,
  pcall = pcall,
  pairs = pairs,
  error = error,
  rawequal = rawequal,
  loadstring = loadstring,
  rawset = rawset,
  unpack = unpack,
  table = shallowcopy(table),
  next = next,
  math = shallowcopy(math),
  load = load,
  select = select,
  string = shallowcopy(string),
  type = type,
  getmetatable = getmetatable,
  setmetatable = setmetatable
}

local function executeString(str, state)
  if not str[2] then -- variable reference
    return state.variables[str]
  else -- string
    local res = {}
    for _, chunk in ipairs(str[1]) do
      if type(chunk) == 'string' then
        table.insert(res, chunk)
      else
        table.insert(res, tostring(setfenv(chunk, merge(M.safeEnv, state.variables))()))
      end
    end
    return table.concat(res, '')
  end
end

local function flushSay(state, opts, iter, label, idx)
  if #state.toSay == 0 then return false end

  local meta = deepcopy(state.meta or {})

  if state.currentCharacter then
    local char = opts.characters[state.currentCharacter]
    meta.character = char
    meta.characterName = state.currentCharacter
  end
  meta.characters = state.characters
  meta.expressions = state.expressions

  opts.openDialog(state.toSay, meta, (#state.choices == 0) and {} or state.choiceStrings, function(c)
    state.toSay = {}
    print('< ' .. tostring(c))
    if #state.choices == 0 then
      iter(label, idx)
    else
      local choiceLabel = state.choices[c]
      state.choices = {}
      state.choiceStrings = {}
      if choiceLabel == '' then
        iter(label, idx)
      elseif choiceLabel ~= nil then
        iter(choiceLabel, 1)
      else
        error('choice index ' .. c .. ' is out-of-bounds!', 2)
      end
    end
  end)

  return true
end

local commandRunners = {}

function commandRunners.say(state, data, opts, iter, label, idx)
  if #state.choices ~= 0 then
    flushSay(state, opts, iter, label, idx)
    return false
  end
  table.insert(state.toSay, executeString(data.str, state))
  return true
end

function commandRunners.randomsay(state, data, opts, iter, label, idx)
  if #state.choices ~= 0 then
    flushSay(state, opts, iter, label, idx)
    return false
  end
  table.insert(state.toSay, executeString(data.str[math.random(#data.str)], state))
  return true
end

commandRunners['goto'] = function(state, data, opts, iter, label, idx)
  local newLabel = executeString(data.target, state)
  assert(newLabel ~= nil)
  iter(newLabel, 1)
  return false
end

function commandRunners.choice(state, data, opts, iter, label, idx)
  table.insert(state.choices, data.label and executeString(data.label, state) or '')
  table.insert(state.choiceStrings, executeString(data.choiceString, state))
  return true
end

function commandRunners.call(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end
  state.variables[data.func](state.variables)
  return true
end

function commandRunners.character(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end
  local char = executeString(data.char, state)
  print(char)
  assert(char ~= nil)
  assert((opts.characters or {})[char] ~= nil, 'character \'' .. char .. '\' not found')
  state.currentCharacter = char
  return true
end

function commandRunners.meta(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end
  state.meta[data.name] = data.value
  return true
end

function commandRunners.expression(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end
  state.expressions[executeString(data.char, state)] = executeString(data.expression, state)
  return true
end

function commandRunners.showcharacter(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end

  table.insert(state.characters, data.char)

  return true
end

function commandRunners.hidecharacter(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end

  for i = #state.characters, 1, -1 do
    if state.characters[i] == data.char then
      table.remove(state.characters, i)
      break
    end
  end

  return true
end

function commandRunners.var(state, data, opts, iter, label, idx)
  if flushSay(state, opts, iter, label, idx) then
    return false
  end
  -- TODO
  error('NYI')
  return true
end

local function bytecodeToFunction(labels)
  print(fullDump(labels))

  ---@param opts scrunklyOptions?
  ---@param callback fun(variables: table<string, any>)?
  return function(opts, callback)
    opts = opts or {}

    local state = {
      meta = deepcopy(opts.meta or {}),
      variables = deepcopy(opts.variables or {}),
      characters = {},
      expressions = {},
      currentCharacter = nil,
      choices = {},
      choiceStrings = {},
      toSay = {},
    }

    local function iter(label, idx)
      print('  running: ', label, idx)

      assert(labels[label] ~= nil, 'label \'' .. label .. '\' does not exist')

      local command = labels[label][idx]
      if not command then
        if flushSay(state, opts, iter, label, idx) then
          if callback then callback(state.variables) end
        end
        return
      end

      local type = command.type

      local runner = commandRunners[type]
      assert(runner ~= nil, 'runner for command \'' .. type .. '\' not found')

      print('  ' .. fullDump(command))

      local conditionMet = true -- todo. BIG todo

      local res = runner(state, command.data, opts, iter, label, idx)
      if res then
        iter(label, idx + 1)
      end
    end

    iter(opts.startLabel or 'main', 1)
  end
end

local function parseString(str)
  local args = {}
  local idx = 0
  for full, plain, _, arg, plain2 in string.gmatch(str, '(([^%%]*)(%%{(.-)})(([^%%]*)))') do
    idx = idx + #full
    if plain ~= '' then table.insert(args, plain) end
    local chunk, err = (loadstring or load)('return (' .. arg .. ')')
    if err then error('error parsing expression: ' .. err, 2) end
    table.insert(args, chunk)
    if plain2 ~= '' then table.insert(args, plain2) end
  end
  local rest = string.sub(str, idx + 1)
  if rest ~= '' then table.insert(args, rest) end
  return args
end

local function parseArguments(str)
  local args = {}
  local arg = {}
  local isQuote = false
  local escaping = false
  local quoteChar
  for i = 1, #str do
    local char = string.sub(str, i, i)
    if not escaping and not isQuote and char == '"' or char == '\'' and #arg == 0 then
      quoteChar = char
      isQuote = true
      if #arg > 0 then table.insert(args, {table.concat(arg, ''), false}) end
      arg = {}
    elseif not escaping and isQuote and char == quoteChar then
      isQuote = false
      if #arg > 0 then table.insert(args, {parseString(table.concat(arg, '')), true}) end
      arg = {}
    elseif not escaping and not isQuote and char == ' ' then
      if #arg > 0 then table.insert(args, {table.concat(arg, ''), false}) end
      arg = {}
    elseif not escaping and char == '\\' then
      escaping = true
    else
      if escaping and not (char == '"' or char == '\'' or char == '\\' or char == '-') then
        error('invalid escaped character: \'\\' .. char .. '\'', 2)
      end
      escaping = false
      table.insert(arg, char)
    end
  end
  if isQuote then
    error('unclosed quote', 2)
  end
  if #arg > 0 then table.insert(args, {table.concat(arg, ''), false}) end
  arg = {}
  return args
end

local commandParsers = {}

function commandParsers.say(args)
  if #args ~= 1 then error('expected 1 argument, got ' .. #args, 2) end
  return {
    str = args[1]
  }
end

function commandParsers.randomsay(args)
  if #args == 0 then error('expected arguments', 2) end
  return {
    str = args
  }
end

function commandParsers.call(args)
  if #args ~= 1 then error('expected 1 argument, got ' .. #args, 2) end
  if args[1][2] then error('expected function, got string', 2) end
  return {
    func = args[1][1]
  }
end

function commandParsers.character(args)
  if #args ~= 1 then error('expected 1 argument, got ' .. #args, 2) end
  return {
    char = args[1]
  }
end

commandParsers.showcharacter = commandParsers.character
commandParsers.hidecharacter = commandParsers.character

function commandParsers.expression(args)
  if #args ~= 2 then error('expected 2 arguments, got ' .. #args, 2) end
  return {
    char = args[1],
    expression = args[2]
  }
end

commandParsers['goto'] = function(args)
  if #args ~= 1 then error('expected 1 argument, got ' .. #args, 2) end
  return {
    target = args[1]
  }
end

function commandParsers.meta(args)
  if #args ~= 2 then error('expected 2 arguments, got ' .. #args, 2) end
  if args[2][1] ~= 'true' and args[2][1] ~= 'false' then error('expected true or false, got ' .. args[2][1], 2) end
  if args[2][2] then error('expected boolean, got string', 2) end
  return {
    name = args[1],
    value = args[2][1] == 'true'
  }
end

function commandParsers.choice(args)
  if #args ~= 1 and #args ~= 2 then error('expected 1 to 2 arguments, got ' .. #args, 2) end
  return {
    choiceString = args[1],
    label = args[2]
  }
end

function commandParsers.var(args)
  if #args ~= 2 then error('expected 2 arguments, got ' .. #args, 2) end
  -- TODO
  error('NYI')
end


---@param code string
---@return fun(options: scrunklyOptions?, onFinish: fun(variables: table<string, any>)?)
function M.build(code)
  local calling = debug.getinfo(2, 'lS')
  local function err(lineNumber, msg)
    error('scrunkly: error while building <chunk>:' .. lineNumber .. ' (' .. calling.short_src .. ':' .. (lineNumber + calling.currentline) ..') - ' .. msg, 3)
  end

  local currentLabel = 'main'
  local labels = {}

  local lineNumber = 0
  for line in string.gmatch(code, '%s*([^\n\r]*)%s*[\n\r]?') do
    lineNumber = lineNumber + 1

    local _, _, lineStripped = string.find(line, '(.-)(%-%-.*)')
    if lineStripped then
      line = lineStripped
    end

    if string.sub(line, 1, 1) == '[' and string.sub(line, -1, -1) == ']' then
      local labelName = string.sub(line, 2, -2)
      currentLabel = labelName
    else
      labels[currentLabel] = labels[currentLabel] or {}
      local commands = labels[currentLabel]

      local ok, parsed = pcall(parseArguments, line)
      if not ok then
        err(lineNumber, parsed)
      end

      if parsed[1] then
        local command
        local commandParser

        if parsed[2] and parsed[2][1] == '->' and not parsed[2][2] then
          table.remove(parsed, 2)
          commandParser = commandParsers.choice
          command = 'choice'
        else
          local commandObj = table.remove(parsed, 1)
          if commandObj[2] then
            err(lineNumber, 'expected command name, got string')
          end
          command = commandObj[1]
          commandParser = commandParsers[command]
        end
        if commandParser then
          local ok, res = pcall(commandParser, parsed)
          if ok then
            table.insert(commands, {
              type = command,
              data = res
            })
          else
            err(lineNumber, command .. ': ' .. res)
          end
        else
          err(lineNumber, 'unknown command \'' .. command .. '\'')
        end
      end
    end
  end

  return bytecodeToFunction(labels)
end

return M