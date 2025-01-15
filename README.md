<img src="https://github.com/yacineMTB/dingllm.nvim/assets/10282244/d03ef83d-a5ee-4ddb-928f-742172f3c80c" alt="wordart (6)" style="width:200px;height:100px;">

### dingllm.nvim
Yacine's no frills LLM nvim scripts. free yourself, brothers and sisters

This is a really light config. I *will* be pushing breaking changes. I recommend reading the code and copying it over - it's really simple.

https://github.com/yacineMTB/dingllm.nvim/assets/10282244/07cf5ace-7e01-46e3-bd2f-5bec3bb019cc


### Credits
This extension woudln't exist if it weren't for https://github.com/melbaldove/llm.nvim

I diff'd on a fork of it until it was basically a rewrite. Thanks @melbaldove!

The main difference is that this uses events from plenary, rather than a timed async loop. I noticed that on some versions of nvim, melbaldove's extension would deadlock my editor. I suspected nio, so i just rewrote the extension. 

### lazy config
Add your API keys to your env (export it in zshrc or bashrc) 

```lua
  {
    'AdrianBakke/dingllm.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local dingllm = require 'dingllm'
      vim.keymap.set({ 'n', 'v' }, '<leader>o', dingllm.openai_chat_completion, { desc = 'OpenAI Chat Completion' })
    end,
  },

```

### Documentation

read the code dummy
