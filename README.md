# scrunkly

<center>

![](https://bestanimations.com/Site/Construction/under-construction-animated-gif-8.gif)

</center>

**`scrunkly` is still in beta. While usable, you will be offered very little support and APIs will, very definitely, frequently shift around.** "Beta" does not mean "designed and currently being tested", "beta" means "mostly functioning"!

`scrunkly` is a visual novel, dialog and overall sequential text processing engine, utilizing a custom script-like language:

```lua
-- comments start with --, like in lua

say "%{name} is very cool" -- references a variable named `name`
say "what do you think?"

"it's cool" -> "cool"
"it SUCKS" -> "sucks"
"i dunno" ->

randomsay "understandable, have a    day" "you can come back later if you find out!" "no pressure!"

-- if a label has no more code, it will exit out

[cool]
say "hell yeah. %{name} is the best"
goto "end"

[sucks]
say "what????? i will delete you immediately"
call deleteUserImmediately -- calls a variable named `deleteUserImmediately`
say "if you're still here, what are you doing?"
say "regardless..."
goto "end"

[end]
say "hope you have a good rest of your day!"
```

Interfacing with `scrunkly` is a little unintuitive, but learnable:

```lua
local scrunkly = require 'scrunkly'

local built = scrunkly.build(...)

built({
  -- this function is called each time scrunkly is ready to give you lines
  openDialog = function(text, meta, choices, callback)
    -- text is a table of all texts you should display
    -- meta will have some meta values, like the current character speaking and their expression
    -- choices, if not nil, gives you the names of the options you're given

    for _, str in ipairs(text) do
      print((meta.character and meta.character.name or '???') .. ': ' .. str)
    end

    -- once you're ready to continue, you can call the callback with the index of your choice
    if #choices > 0 then
      for i, choice in ipairs(choices) do
        print(i .. '. ' .. choice)
      end
      local choice = io.read('*n')
      callback(choice)
    else
      callback()
    end
  end
}, function(vars)
  print('finished!')
end)
```

The above is actually all you need to build a CLI runner for `.scrunkly` files!

## Used by

- [Cathy Ray's Tubular Training](https://oatmealine.itch.io/cathy-rays-tubular-training) (2023, Love2D)
- [████████████](https://yugoslavia.best/c/) (????, NotITG)