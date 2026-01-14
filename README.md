![hint.nvim Header](hint.png)

### hint.nvim
Inline LLM prompt + bottom-right status HUD for code edits.

https://github.com/user-attachments/assets/b54f11d5-8197-4294-a745-7c4524a62447

### Credits
This extension woudln't exist if it weren't for https://github.com/melbaldove/llm.nvim
and https://github.com/yacineMTB/dingllm.nvim

I diff'd on a fork of it until it was basically a rewrite. Thanks @yacineMTB!

The main difference is that this runs from an inline prompt and applies patches directly, while a tiny status window shows progress.

```lua
return {
  {
    'AdrianBakke/hint.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('hint').setup {
        model = 'codex-mini-latest',
        models = { 'codex-mini-latest', 'gpt-4.1-mini', 'o4-mini' },
        keymaps = {
          prompt = '<C-h>',
          run_comment = '<leader>hr',
          show_last = '<leader>hs',
          model_1 = '<leader>1',
          model_2 = '<leader>2',
          model_3 = '<leader>3',
        },
      }
    end,
  },
}
```

### Documentation

Usage:
- `Ctrl-h` opens an inline prompt at the cursor (visual selection supported).
- `:HintRun` executes the nearest `# HINT:` comment.
- `:HintShow` opens the last response if no patch was applied.
- `:HintRollback` reverts the last applied patch.
- `:HintStatus` opens the full status log in a split.
- `:HintDiff` reopens the last diff view.
- `:HintTools` shows the last tool output if the loop stops.
- `:HintDebug` shows the last prompt/response/tool trace.
- The model must return apply_patch diffs; the diff view shows them and lets you apply/revert hunks.
- The status window auto-closes after each run.
- Set `OPENAI_API_KEY` for the Responses API.
- Tool loop: model can request `HINT_TOOL: rg <query>`, `HINT_TOOL: read <path>`, `HINT_TOOL: ls <path>`.

### TODO
* add richer context controls []
* support unified diff output []
