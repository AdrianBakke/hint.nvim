![hint.nvim Header](hint.png)
<!--<img src="https://github.com/yacineMTB/dingllm.nvim/assets/10282244/d03ef83d-a5ee-4ddb-928f-742172f3c80c" alt="wordart (6)" style="width:200px;height:100px;">-->

### hint.nvim
Yacine's no frills LLM nvim scripts. free yourself, brothers and sisters

This is a really light config. I *will* be pushing breaking changes. I recommend reading the code and copying it over - it's really simple.

<!--https://github.com/yacineMTB/dingllm.nvim/assets/10282244/07cf5ace-7e01-46e3-bd2f-5bec3bb019cc-->


### Credits
This extension woudln't exist if it weren't for https://github.com/melbaldove/llm.nvim
and https://github.com/yacineMTB/dingllm.nvim

I diff'd on a fork of it until it was basically a rewrite. Thanks @yacineMTB!

The main difference is that this streams the llm output into a floating window, istead of directly in the editor.
You can open and close the window as you like and you don`t have to deal with the clutter of having the stream come directly into your code file.

```lua
return {
  {
    'AdrianBakke/hint.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local dingllm = require 'hint'
      vim.keymap.set({ 'n', 'v' }, '<leader>o', dingllm.openai_chat_completion, { desc = 'OpenAI Chat Completion' })
      vim.keymap.set({ 'n', 'v' }, '<leader>k', dingllm.deepseek_chat_completion, { desc = 'DeepSeek Chat Completion' })
      vim.keymap.set({ 'n', 'v' }, '<leader>h', dingllm.open_window, { desc = 'Open HINT Window' })
    end,
  },
}
```

### Documentation

read the code dummy

### TODO
* make creating prompt with text selected with ctrl-v work []
* make it possible to stop llm output with <leader>q []
* possible syntax highlighting inside floating window? <leader>q []
