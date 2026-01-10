local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

-- 判断数学模式
local function in_math()
  return vim.fn["vimtex#syntax#in_mathzone"]() == 1
end

-- ##########################
-- 数学字体类命令（数学模式下）
-- ##########################
local math_font_snippets = {}

-- 自动生成 mA-mZ、bbA-bbZ、rmA-rmZ、sfA-sfZ、scrA-scrZ
local fonts = { "m", "bb", "rm", "sf", "scr","bf" }
local font_cmd = {
  m = "\\mathcal{",
  bb = "\\mathbb{",
  rm = "\\mathrm{",
  sf = "\\mathsf{",
  scr = "\\mathscr{",
  bf = "\\mathbf{",
}

-- for _, prefix in ipairs(fonts) do
--   for c = string.byte("A"), string.byte("Z") do
--     local letter = string.char(c)
--     table.insert(math_font_snippets,
--       s({ trig = prefix .. letter, wordTrig = true, condition = in_math }, {
--         t(font_cmd[prefix]), t(letter), t("}")
--       })
--     )
--   end
-- end
for _, prefix in ipairs(fonts) do
  for c = string.byte("A"), string.byte("Z") do
    local upper = string.char(c)
    local lower = string.char(c + 32) -- ASCII 差 32 得到小写
    -- 大写字母
    table.insert(math_font_snippets,
      s({ trig = prefix .. upper, wordTrig = true, condition = in_math }, {
        t(font_cmd[prefix]), t(upper), t("}")
      })
    )
    -- 小写字母
    table.insert(math_font_snippets,
      s({ trig = prefix .. lower, wordTrig = true, condition = in_math }, {
        t(font_cmd[prefix]), t(lower), t("}")
      })
    )
  end
end

-- ##########################
-- LaTeX 环境命令
-- ##########################
local env_snippets = {
  -- remark 环境
  s("rmk", { t("\\rmk{"), i(1), t("}") }),

  -- 横线
  s("line", { t("\\line") }),

  -- eq: 展开 align 环境（数学环境）
  s({ trig = "eq", wordTrig = true }, {
    t({ "\\begin{align}", "\t" }), i(1),
    t({ "", "\\end{align}" }),
  }),


  -- 各种 theorem/definition 等
  s("defi", { t("\\defi{"), i(1), t("}") }),
  s("thm", { t("\\thm{"), i(1), t("}") }),
  s("axm", { t("\\axm{"), i(1), t("}") }),
  s("lmm", { t("\\lmm{"), i(1), t("}") }),

  -- 盒子类
  s("imp", { t("\\imp{"), i(1), t("}{"), i(2), t("}") }),
  s("think", { t("\\think{"), i(1), t("}") }),
  s("idea", { t("\\idea{"), i(1), t("}{"), i(2), t("}") }),
  s("tar", { t("\\tar{"), i(1), t("}") }),
  s("ques", { t("\\ques{"), i(1), t("}{"), i(2), t("}") }),
  s("tip", { t("\\tip{"), i(1), t("}{"), i(2), t("}") }),
  s("conc", { t("\\conclusion{"), i(1), t("}{"), i(2), t("}") }),
  s("attn", { t("\\attention{"), i(1), t("}{"), i(2), t("}") }),

  -- 广相常用
  s("ten", { t("\\tensor{"), i(1), t("}{"), i(2), t("}") }),
  s("pd",  { t("\\partial_{"), i(1), t("}"), i(0) }),

  -- \question{}
  s("qs", { t("\\question{"), i(1), t("}") }),
  s("bs", { t("\\bigskip") }),

  -- \item
  s("ii", { t("\\item ") }),

    -- 小写希腊字母
  s("alp", { t("\\alpha") }),
  s("bet", { t("\\beta") }),
  s("gam", { t("\\gamma") }),
  s("del", { t("\\delta") }),
  s("eps", { t("\\epsilon") }),
  s("zet", { t("\\zeta") }),
  s("eta", { t("\\eta") }),
  s("the", { t("\\theta") }),
  s("iot", { t("\\iota") }),
  s("kap", { t("\\kappa") }),
  s("lam", { t("\\lambda") }),
  s("mu",  { t("\\mu") }),
  s("nu",  { t("\\nu") }),
  s("xi",  { t("\\xi") }),
  s("omi", { t("\\omicron") }),
  s("pi",  { t("\\pi") }),
  s("rho", { t("\\rho") }),
  s("sig", { t("\\sigma") }),
  s("tau", { t("\\tau") }),
  s("ups", { t("\\upsilon") }),
  s("phi", { t("\\phi") }),
  s("chi", { t("\\chi") }),
  s("psi", { t("\\psi") }),
  s("ome", { t("\\omega") }),

  -- 大写希腊字母（首字母大写）
  s("Gam", { t("\\Gamma") }),
  s("Del", { t("\\Delta") }),
  s("The", { t("\\Theta") }),
  s("Lam", { t("\\Lambda") }),
  s("Xi",  { t("\\Xi") }),
  s("Pi",  { t("\\Pi") }),
  s("Sig", { t("\\Sigma") }),
  s("Ups", { t("\\Upsilon") }),
  s("Phi", { t("\\Phi") }),
  s("Psi", { t("\\Psi") }),
  s("Ome", { t("\\Omega") }),

}

ls.add_snippets("tex", math_font_snippets)
ls.add_snippets("tex", env_snippets)

