-- lua/keymap/tex.lua
local opts = { buffer = true, noremap = true, silent = true }
local keymap = vim.keymap.set

-- 视觉模式包裹选中内容（支持单行和多行）
local function wrap_visual(wrapper)
  -- 保存视图模式和位置
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  -- 确保 start_pos < end_pos
  if (start_pos[2] > end_pos[2]) or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
    start_pos, end_pos = end_pos, start_pos
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2]-1, end_pos[2], false)
  if #lines == 0 then return end

  if #lines == 1 then
    local line = lines[1]
    local s_col = start_pos[3]
    local e_col = end_pos[3]

    local before = line:sub(1, s_col - 1)
    local inside = line:sub(s_col, e_col)
    local after = line:sub(e_col + 1)

    local new_line = before .. "\\" .. wrapper .. "{" .. inside .. "}" .. after
    vim.api.nvim_buf_set_lines(0, start_pos[2]-1, end_pos[2], false, {new_line})

    -- 光标移动到包裹内容后面
    vim.api.nvim_win_set_cursor(0, {start_pos[2], #before + #wrapper + #inside + 3})
  else
    -- 多行选中处理
    -- 第一行插入 \wrapper{
    lines[1] = lines[1]:sub(1, start_pos[3] - 1) .. "\\" .. wrapper .. "{" .. lines[1]:sub(start_pos[3])
    -- 最后一行末尾加 }
    lines[#lines] = lines[#lines] .. "}"
    vim.api.nvim_buf_set_lines(0, start_pos[2]-1, end_pos[2], false, lines)

    -- 光标定位到最后一行末尾大括号前
    vim.api.nvim_win_set_cursor(0, {start_pos[2] + #lines - 1, #lines[#lines] - 1})
  end

  -- 退出视觉模式
  vim.cmd('normal! \\<Esc>')
end

local function insert_wrapper(wrapper)
  return function()
    local text = "\\" .. wrapper .. "{}"
    vim.api.nvim_put({ text }, 'c', true, true)
    vim.cmd("startinsert!")

    -- 光标移动到大括号中间，计算当前位置
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    -- 当前光标在插入文本末尾，往前移 1（到 '{'）再加 1 到大括号里面
    vim.api.nvim_win_set_cursor(0, {row, col - 1})
  end
end




-- 正式还是设置快捷键
vim.api.nvim_create_autocmd("FileType", {
  pattern = "tex",
  callback = function()
    -- 这个函数里面添加我的快捷键  
    vim.keymap.set("i", "<C-e>", "$<Left>", { buffer = true })
    vim.keymap.set("i", "<C-f>", "\\frac{}{}<Left><Left>", { buffer = true })
    

     -- 视觉模式快捷键
    -- keymap("v", "<C-b>", function() wrap_visual("textbf") end, opts)
    -- keymap("v", "<C-h>", function() wrap_visual("hlr") end, opts)
    -- keymap("v", "<C-i>", function() wrap_visual("textit") end, opts)
    -- keymap("v", "<C-x>", function() wrap_visual("sout") end, opts)

    -- 插入模式快捷键
    keymap("i", "<C-j>", insert_wrapper("textbf"), opts)
    keymap("i", "<C-h>", insert_wrapper("hlr"), opts)
    keymap("i", "<C-k>", insert_wrapper("textit"), opts)
    keymap("i", "<C-g>", insert_wrapper("sout"), opts)
    keymap("i", "<C-r>", insert_wrapper("cref"), opts)
    keymap("i", "<C-l>", insert_wrapper("label"), opts)

    -- 插入模式特殊命令 \tensor{}{}
    keymap("i", "<C-ts>", function()
      local line = "\\tensor{}{}"
      vim.api.nvim_put({ line }, 'c', true, true)
      vim.cmd("startinsert!")
      vim.cmd("normal! 0f{l") -- 光标定位第一个大括号内
    end, opts)
  end,
})

