local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node


ls.add_snippets("markdown", {
  s("topic", {
    t({"---",
        "layout: topic",
       "title: "}),
    f(function()
      return vim.fn.input("Title: ")
    end),
    t({"",
       "tags: ["}),
    f(function()
      return vim.fn.input("Tags (comma separated): ")
    end),
    t({"]",
       "---",
       "",
       "# "}),
    f(function()
      return vim.fn.input("H1 Title: ")
    end),
    t({"", ""}),
  }),
})

ls.add_snippets("markdown", {
  s("paper", {
    t({"---",
       "layout: paper",
       "title: "}),
    f(function()
      return vim.fn.input("Title: ")
    end),
    t({"",
       "tags: ["}),
    f(function()
      return vim.fn.input("Tags (comma separated): ")
    end),
    t({"]",
       "---",
       }),
  }),
})


ls.add_snippets("markdown", {
  s("eq", {
    t("$$"),
    t({"", ""}),
    i(1),
    t({"", "$$"}),
  }),
})


