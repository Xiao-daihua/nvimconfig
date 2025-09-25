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
local fonts = { "m", "bb", "rm", "sf", "scr" }
local font_cmd = {
  m = "\\mathcal{",
  bb = "\\mathbb{",
  rm = "\\mathrm{",
  sf = "\\mathsf{",
  scr = "\\mathscr{",
}

for _, prefix in ipairs(fonts) do
  for c = string.byte("A"), string.byte("Z") do
    local letter = string.char(c)
    table.insert(math_font_snippets,
      s({ trig = prefix .. letter, wordTrig = true, condition = in_math }, {
        t(font_cmd[prefix]), t(letter), t("}")
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

  -- aligned 环境
  s("ali", {
    t("\\begin{aligned}"),
    t({"", "  "}), i(1),
    t({"", "\\end{aligned}"}), i(0)
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

  -- 希腊字母
    -- 小写希腊字母
  s("ga", { t("\\alpha") }),
  s("gb", { t("\\beta") }),
  s("gg", { t("\\gamma") }),
  s("gd", { t("\\delta") }),
  s("ge", { t("\\epsilon") }),
  s("gz", { t("\\zeta") }),
  s("ge", { t("\\eta") }),
  s("gth", { t("\\theta") }),
  s("gi", { t("\\iota") }),
  s("gk", { t("\\kappa") }),
  s("gl", { t("\\lambda") }),
  s("gm", { t("\\mu") }),
  s("gn", { t("\\nu") }),
  s("gx", { t("\\xi") }),
  s("go", { t("\\omicron") }),
  s("gp", { t("\\pi") }),
  s("gr", { t("\\rho") }),
  s("gs", { t("\\sigma") }),
  s("gt", { t("\\tau") }),
  s("gu", { t("\\upsilon") }),
  s("gf", { t("\\phi") }),
  s("gc", { t("\\chi") }),
  s("gpsi", { t("\\psi") }),
  s("go", { t("\\omega") }),

  -- 大写希腊字母
  s("gG", { t("\\Gamma") }),
  s("gD", { t("\\Delta") }),
  s("gTh", { t("\\Theta") }),
  s("gL", { t("\\Lambda") }),
  s("gX", { t("\\Xi") }),
  s("gP", { t("\\Pi") }),
  s("gS", { t("\\Sigma") }),
  s("gU", { t("\\Upsilon") }),
  s("gF", { t("\\Phi") }),
  s("gPs", { t("\\Psi") }),
  s("gO", { t("\\Omega") }),

  -- \subsubsection{}
  s("sssec", { t("\\subsubsection{"), i(1), t("}") }),


}

ls.add_snippets("tex", math_font_snippets)
ls.add_snippets("tex", env_snippets)

