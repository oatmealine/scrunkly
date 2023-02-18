describe('scrunkly', function()
  local scrunkly = require 'scrunkly'

  scrunkly.logger = nil

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

  ---@generic T
  ---@generic F
  ---@param t table<T>
  ---@param f fun(a: T, idx: number): F
  ---@return table<F>
  function map(t, f)
    local result = {}
    for i = 1, #t do
      local v = f(t[i], i)
      if v ~= nil then
        table.insert(result, v)
      end
    end
    return result
  end

  describe('parsing and building', function()
    it('should ignore comments', function()
      assert.has_no.errors(function()
        scrunkly.build([=[
          -- [invalid] label

          -- invalid command kajshg "

          say "test" -- more invalid syntax ' 3
        ]=])
      end)
    end)
    it('should compile labels', function()
      assert.has_no.errors(function()
        scrunkly.build([=[
          [main]

          [test1]

          [test2]

          [test3]
        ]=])
      end)
    end)
    it('should compile commands', function()
      assert.has_no.errors(function()
        scrunkly.build([=[
          say "test"
          randomsay "test1" "test2" "test3"
          call testFunction
          character "character"
          showcharacter "character"
          hidecharacter "character"
          expression "character" "expression"
          goto "label_name"
          goto "other_file.scrunkly"
          --var "varName" "value"
          meta "metaName" true
        ]=])
      end)
    end)
    it('should compile conditionals', function()
      assert.has_no.errors(function()
        scrunkly.build([=[
          if flagName say "flagName is true"
          if !flagName say "flagName is false"
        ]=])
      end)
    end)
    it('should compile choices', function()
      assert.has_no.errors(function()
        scrunkly.build([=[
          say "choose one"
          "option 1" -> "test1"
          "option 2" -> "test2"
          "exit out" ->
          say "exiting out"
        ]=])
      end)
    end)
    describe('strings', function()
      it('should compile template strings', function()
        assert.has_no.errors(function()
          scrunkly.build([=[
            say "value 'test' is '%{test}'"
          ]=])
        end)
      end)
      it('should compile double quote and single quotes correctly', function()
        assert.has_no.errors(function()
          scrunkly.build([=[
            say "this is 'one string'"
            say 'this is still "one string"'
            say 'don\'t get "confused'
          ]=])
        end)
      end)
      it('should complain about escaping non-escapable characters', function()
        assert.has.errors(function()
          scrunkly.build([=[
            say "\e\s\c\a\p\i\n\g \w\e\r\i\d \c\h\a\r\s"
          ]=])
        end)
      end)
    end)
  end)

  describe('executing', function()
    local function dialogQueueHandler(queue)
      return function(text, meta, choices, callback)
        for i, line in ipairs(text) do
          if i == #text then
            table.insert(queue, {line, meta, choices})
          else
            table.insert(queue, {line, meta, nil})
          end
        end
        callback(1)
      end
    end

    local function queueRunner(code, opts, callback)
      local queue = {}
      scrunkly.build(code)(merge(opts or {}, {
        openDialog = dialogQueueHandler(queue)
      }), function(vars)
        if callback then callback(queue, vars) end
      end)
    end

    it('should relay basic lines correctly', function()
      queueRunner([[
        say "one"
        say "two"
        say "three"
      ]], {}, function(queue)
        assert.are.same({'one', 'two', 'three'}, map(queue, function(t) return t[1] end))
      end)
    end)

    describe('string interpolation', function()
      it('should interpolate basic strings together', function()
        queueRunner([[
          say "%{'test1'} %{'test2'} %{'test3'}"
        ]], {}, function(queue)
          assert.are.same('test1 test2 test3', queue[1][1])
        end)
      end)

      it('should interpolate numbers and other types correctly', function()
        queueRunner([[
          say "%{2} + %{2} = %{2 + 2}"
          say "%{true} and %{false}"
        ]], {}, function(queue)
          assert.are.same('2 + 2 = 4', queue[1][1])
          assert.are.same('true and false', queue[2][1])
        end)
      end)

      it('should understand variables in interpolated strings', function()
        queueRunner([[
          say "%{testValue}. %{testValue2}"
        ]], {
          variables = {
            testValue = 'hewwo',
            testValue2 = 'hewwo!!'
          }
        }, function(queue)
          assert.are.same('hewwo. hewwo!!', queue[1][1])
        end)
      end)

      it('should let interpolated strings access to basic standard library functions', function()
        queueRunner([[
          say "%{n} floored is %{math.floor(n)}"
        ]], {
          variables = {
            n = 0.5
          }
        }, function(queue)
          assert.are.same('0.5 floored is 0', queue[1][1])
        end)
      end)

      it('should not let interpolated strings access to os by default', function()
        queueRunner([[
          say "%{os}"
        ]], {}, function(queue)
          assert.are.same('nil', queue[1][1])
        end)
      end)
    end)

    describe('labels', function()
      it('should follow labels correctly', function()
        queueRunner([[
          say "going"
          goto "back"
          
          [and]
          say "and"
          goto "forth"

          [back]
          say "back"
          goto "and"

          [forth]
          say "forth"
        ]], {}, function(queue)
          assert.are.same({'going', 'back', 'and', 'forth'}, map(queue, function(t) return t[1] end))
        end)
      end)

      it('should provide an error on invalid label', function()
        assert.has_error(function()
          queueRunner([[
            goto "what"
          ]])
        end, 'label \'what\' does not exist')
      end)

      it('should infloop if told to do so (lol?)', function()
        assert.has_error(function()
          queueRunner([[
            goto "main"
          ]])
        end, 'stack overflow')
      end)
    end)

    describe('external functions', function()
      it('should call functions correctly', function()
        local mark = 0
        queueRunner([[
          call mark
          call mark
          call mark
        ]], {
          variables = {
            mark = function()
              mark = mark + 1
            end
          }
        }, function(queue)
          assert.are.same(mark, 3)
        end)
      end)

      it('should call functions with the correct variables', function()
        local correct = false
        queueRunner([[
          call test
        ]], {
          variables = {
            test = function(vars)
              correct = vars.n == 2
            end,
            n = 2
          }
        }, function(queue)
          assert.is_true(correct)
        end)
      end)

      it('should call functions with the up-to-date variables', function()
        local correct = true
        queueRunner([[
          call testNot
          var n "correct"
          call test
        ]], {
          variables = {
            testNot = function(vars)
              correct = correct and (vars.n == 'incorrect')
            end,
            test = function(vars)
              correct = correct and (vars.n == 'correct')
            end,
            n = 'incorrect'
          }
        }, function(queue)
          assert.is_true(correct)
        end)
      end)
    end)
  end)
end)