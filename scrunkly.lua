-- scrunkly 2 - the dialog interpreter you never wanted
-- rewritten with Better Code Practices

local M = {
  VERSION = "2.0.0-beta.1",
}

-- temporary
require 'src.lib.util'

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
---@field openDialog fun(text: table, meta: table<string, any>, choices: table<string, any>, callback: fun(choice: number)): nil

---@class scrunklyCharacter
---@field name string
---@field sprites table<string, love.Image>

local function executeString(str, state)
  if not str[2] then -- variable reference
    return state.variables[str]
  else -- string
    local res = {}
    for _, chunk in ipairs(str[1]) do
      if type(chunk) == 'string' then
        table.insert(res, chunk)
      else
        table.insert(res, chunk())
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

function commandRunners.goto(state, data, opts, iter, label, idx)
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
        flushSay(state, opts, iter, label, idx)
        if callback then callback(state.variables) end
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
  for full, plain, _, arg, plain2 in string.gmatch(str, '(([^%%]*)(%%{(.-)}))(([^%%]*))') do
    idx = idx + #full
    if plain ~= '' then table.insert(args, plain) end
    local chunk, err = load('return (' .. arg .. ')')
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
      if escaping and not (char == '"' or char == '\'' or char == '\\') then
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
  if args[2][1] ~= 'true' or args[2][1] ~= 'false' then error('expected true or false, got ' .. args[2][1], 2) end
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
---@return fun(options: scrunklyOptions?, onFinish: fun(flags: table<string, boolean>)?)
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

    if string.sub(line, 1, 2) == '--' then
      -- do nothing
    elseif string.sub(line, 1, 1) == '[' and string.sub(line, -1, -1) == ']' then
      local labelName = string.sub(line, 2, -2)
      currentLabel = labelName
    else
      labels[currentLabel] = labels[currentLabel] or {}
      local commands = labels[currentLabel]

      local command, args = string.match(line, '^([^%s]+)(.*)')
      if command then
        local parsed = parseArguments(args)

        local commandParser = commandParsers[command]

        if parsed[1] and parsed[1][1] == '->' and not parsed[1][2] then
          table.remove(parsed, 1)
          table.insert(parsed, 1, parseArguments(command)[1]) -- todo: don't ignore rest of output? somehow? this feels like an extreme edge case
          commandParser = commandParsers.choice
          command = 'choice'
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
          err(lineNumber, 'unknown command \'' .. command .. '\'', 2)
        end
      end
    end
  end

  return bytecodeToFunction(labels)
end

math.randomseed(os.time())

local examples = {
  [[
    say "hewwo"
    say "i've got a question for you..."
    goto "%{'prompt'}"
    
    [prompt]
    say "how many cheese? hint: it's %{math.random(1, 10)}"
    "one" -> "prompt1"
    "two" -> "prompt2"
    "more" ->
    -- it kinda "falls back" if nothing is provided as the result of a choice
    say ":D correct"
    -- upon reaching the end itll exit out
    
    [prompt1]
    call externalFunction
    say "mm. not enough"
    goto "prompt"
    
    [prompt2]
    say "getting there..."
    goto "prompt"
  ]],
  [[
    expression "cheese" "default"
    character "cheese"
    say "Let's restart and try again!"
    say "Here's a useful tip I should've probably told you earlier:"
    goto "tip%{math.floor(math.random() * 5) + 1}"

    [tip1]
    say "As fun as it is to use your [bomb] to get a bunch of score, it might be wiser to save it for when you're overwhelmed!"

    [tip2]
    say "Your hitbox will show up for a moment when you're [grazing]. Make sure to get a feel for how big it is!"

    [tip3]
    say "Remember that enemy spawns will always be the same between games - if a strategy works once, it'll always work!"

    [tip4]
    say "You get a [bomb] once every **20,000** score points. Make sure to use that to your advantage!"

    [tip5]
    say "Most enemies will only become an issue if you let them live for long enough - make sure to get rid of them as soon as possible to avoid getting overwhelmed!"
  ]]
}

M.build(examples[2])({
  openDialog = function(text, meta, choices, callback)
    print('> ' .. fullDump(text), fullDump(choices), fullDump(meta))
    callback(math.random(1, 3))
  end,
  variables = {
    externalFunction = function(vars)
      print('EXTERN FUNC: ', fullDump(vars))
    end
  },
  characters = {
    cheese = {
      name = 'Cheese',
      sprites = {
        default = {}
      }
    }
  }
})

return M