# scrunkly

<center>

![](https://bestanimations.com/Site/Construction/under-construction-animated-gif-8.gif)

</center>

> **Warning**
> 
> **`scrunkly` is still in beta. While usable, you will be offered very little support and APIs will, very definitely, frequently shift around.** "Beta" does not mean "designed and currently being tested", "beta" means "mostly functioning"!

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

## Compatibility

| Version        | Base | Sandboxing | [CI](https://github.com/oatmealine/scrunkly/actions/workflows/busted.yml) |
| ----------     | ---- | ---------- | -- |
| LuaJIT         | ✔️    | ✔️          | ✔️ |
| Lua 5.1        | ✔️    | ✔️          | ✔️ |
| Lua 5.2        | ✔️    | ✔️[^2]      | ✔️ |
| Lua 5.3        | ✔️    | ✔️[^2]      | ✔️ |
| Lua 5.4        | ✔️    | ✔️[^2]      | ✔️ |
| NotITG Lua[^1] | ✔️    | ✔️          | ❌ |

[^1]: NotITG Lua is 5.0.3 with some syntax and features ported over from 5.1, preserving backwards compatibility. Notably, `#`, `%`, long strings (`[=[ ... ]=]`) and some [5.0 bugfixes](https://www.lua.org/bugs.html#5.0.3). If true, pure 5.0 support is ever required, I do not mind doing so.

[^2]: `setfenv`, required for sandboxing, is missing in 5.2+. [An alternative](https://leafo.net/guides/setfenv-in-lua52-and-above.html) that is implemented with `debug` is used instead on those versions; this means you may not have access to it in your environment.

`scrunkly` does not require much from your environment - `io`, `debug` and other potentially insecure modules which many Lua environments disable are never used, and it's up to you to utilize them if necessary.

## Language

Typically, `scrunkly` scripts are stored in `.scrunkly` files, optionally alongside `.lua` files in the same folders that define default values for options:

- `test.scrunkly`
  ```lua
  say "hello %{name}!"
  call externFunc
  ```
- `test.lua`
  ```lua
  return {
    variables = {
      name = 'oatmealine',
      externFunc = function()
        print('something happened!')
      end
    }
  }
  ```

You are free to structure them however you want to, however - `scrunkly` gives you the power to define your setup however you wish to, adapting to whichever sandboxing limitations the program you're running it in might impose upon you.

> **Note**
> 
> A good example of this is in NotITG - files cannot be conventionally accessed through the API, but you can still utilize all of `scrunkly`'s features by manually passing in code and options without following the standard convention.

## Used by

- [Cathy Ray's Tubular Training](https://oatmealine.itch.io/cathy-rays-tubular-training) (2023, Love2D)
- [Egg Related Videogame](https://maggiemagius.itch.io/egg-related-videogame) (2024, Love2D)
- [████████████](https://yugoslavia.best/c/) (????, NotITG)
