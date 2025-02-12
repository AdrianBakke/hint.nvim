![hint.nvim Header](hint.png)

### hint.nvim
Free yourself, brothers and sisters

https://github.com/user-attachments/assets/b54f11d5-8197-4294-a745-7c4524a62447

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
* create a demo showcasing how to use []
