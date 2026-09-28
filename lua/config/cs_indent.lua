-- C# indentexpr: Neovim's bundled GetCSIndent (cindent-based), except inside
-- braces that open an expression rather than a statement block:
--
--   items.ForEach(x =>          var p = new Person       var s = n switch
--   {                           {                        {
--       Console.WriteLine(x);       Name = "a",              0 => "zero",
--   });                             Age = 3,                 _ => "some",
--                               };                       };
--
-- cindent mis-indents these (lambda bodies inside "(" land 8 columns deep;
-- initializer entries and switch arms align after the first word like a C
-- declaration list), so lines inside them are indented by brace depth.
local M = {}

local skipped = {
  comment = true,
  string_literal = true,
  verbatim_string_literal = true,
  raw_string_literal = true,
  interpolated_string_expression = true,
  character_literal = true,
}

-- searchpair() skip: true when the cursor is on a brace inside a string or comment.
local function in_string_or_comment()
  local pos = vim.api.nvim_win_get_cursor(0)
  local node = vim.treesitter.get_node({ pos = { pos[1] - 1, pos[2] }, ignore_injections = true })
  while node do
    if skipped[node:type()] then
      return true
    end
    node = node:parent()
  end
  return false
end

-- Line number of the "{" enclosing the start of lnum, or 0.
local function enclosing_open(lnum)
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  return vim.fn.searchpair("{", "", "}", "bnW", in_string_or_comment)
end

-- Whether a "{" on the line after `prev` opens an expression: a lambda body,
-- a switch expression, or an object/collection initializer.
local function precedes_expression_brace(prev)
  return prev:match("=>%s*$") ~= nil
    or prev:match("%f[%w_]switch%s*$") ~= nil
    or (prev:match("%f[%w_]new%f[^%w_]") ~= nil and not prev:match("[;{}]%s*$"))
end

local function prev_line(lnum)
  return vim.fn.getline(vim.fn.prevnonblank(lnum - 1))
end

local function opens_expression_brace(lnum)
  return vim.fn.getline(lnum):match("^%s*{") ~= nil and precedes_expression_brace(prev_line(lnum))
end

function M.get(lnum)
  local ok, parser = pcall(vim.treesitter.get_parser, 0, "c_sharp")
  if ok and parser then
    parser:parse()
  end
  local line = vim.fn.getline(lnum)
  -- The "{" itself sits level with the line before it. This also covers the
  -- line while it is still empty (or holds only the ")" autopairs pushed
  -- down), since autopairs inserts "{" via a mapping, which doesn't trigger
  -- the 0{ re-indent.
  if precedes_expression_brace(prev_line(lnum)) and (line:match("^%s*$") or line:match("^%s*[{)]")) then
    return vim.fn.indent(vim.fn.prevnonblank(lnum - 1))
  end

  local inner = enclosing_open(lnum)
  -- A "}" lines up with the line holding its "{". Done here for every block,
  -- since cindent's own matching is thrown off by a "}" in a comment inside
  -- a lambda.
  if inner > 0 and line:match("^%s*}") then
    return vim.fn.indent(inner)
  end

  local open = inner
  while open > 0 and not opens_expression_brace(open) do
    open = enclosing_open(open)
  end
  if open == 0 then
    return vim.fn.GetCSIndent(lnum)
  end

  if line:match("^%s*{") then
    return vim.fn.indent(vim.fn.prevnonblank(lnum - 1))
  end
  return vim.fn.indent(inner) + vim.fn.shiftwidth()
end

return M
