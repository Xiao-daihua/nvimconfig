local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local sn = ls.snippet_node

ls.add_snippets("markdown", {

	-- ── 已有：块级公式 ────────────────────────────────────────────
	s("eq", {
		t("$$"),
		t({ "", "" }),
		i(1),
		t({ "", "$$" }),
	}),

	-- ── 行内公式 ──────────────────────────────────────────────────
	s("il", {
		t("$"),
		i(1),
		t("$"),
	}),

	-- ── 对齐方程组（aligned）─────────────────────────────────────
	s("eqa", {
		t({ "$$", "\\begin{aligned}", "" }),
		i(1),
		t({ "", "\\end{aligned}", "$$" }),
	}),

	-- ── 分段函数（cases）─────────────────────────────────────────
	s("cases", {
		t("$$"),
		t({ "", "" }),
		i(1),
		t(" = \\begin{cases}"),
		t({ "", "  " }),
		i(2),
		t(" & \\text{if } "),
		i(3),
		t({ " \\\\", "  " }),
		i(4),
		t(" & \\text{otherwise}"),
		t({ "", "\\end{cases}", "$$" }),
	}),

	-- ── 分数 ──────────────────────────────────────────────────────
	s("ff", {
		t("\\frac{"),
		i(1),
		t("}{"),
		i(2),
		t("}"),
	}),

	-- ── 偏微分分数 ────────────────────────────────────────────────
	s("pdd", {
		t("\\frac{\\partial "),
		i(1),
		t("}{\\partial "),
		i(2),
		t("}"),
	}),

	-- ── 常微分分数 ────────────────────────────────────────────────
	s("ddd", {
		t("\\frac{\\mathrm{d}"),
		i(1),
		t("}{\\mathrm{d}"),
		i(2),
		t("}"),
	}),

	-- ── 求和 ──────────────────────────────────────────────────────
	s("sum", {
		t("\\sum_{"),
		i(1, "n=0"),
		t("}^{"),
		i(2, "\\infty"),
		t("} "),
		i(3),
	}),

	-- ── 积分 ──────────────────────────────────────────────────────
	s("int", {
		t("\\int_{"),
		i(1),
		t("}^{"),
		i(2),
		t("} "),
		i(3),
		t(" \\, \\mathrm{d}"),
		i(4, "x"),
	}),

	-- ── 二重积分 ──────────────────────────────────────────────────
	s("iint", {
		t("\\iint_{"),
		i(1),
		t("} "),
		i(2),
		t(" \\, \\mathrm{d}"),
		i(3, "x"),
		t(" \\, \\mathrm{d}"),
		i(4, "y"),
	}),

	-- ── 极限 ──────────────────────────────────────────────────────
	s("lim", {
		t("\\lim_{"),
		i(1, "n \\to \\infty"),
		t("} "),
		i(2),
	}),

	-- ── 矩阵（pmatrix 圆括号）────────────────────────────────────
	s("mat", {
		t("\\begin{pmatrix}"),
		t({ "", "  " }),
		i(1),
		t({ "", "\\end{pmatrix}" }),
	}),

	-- ── 行列式（vmatrix 竖线）────────────────────────────────────
	s("det", {
		t("\\begin{vmatrix}"),
		t({ "", "  " }),
		i(1),
		t({ "", "\\end{vmatrix}" }),
	}),

	-- ── 向量（粗体）──────────────────────────────────────────────
	s("vv", {
		t("\\mathbf{"),
		i(1),
		t("}"),
	}),

	-- ── 单位向量（hat）───────────────────────────────────────────
	s("uv", {
		t("\\hat{"),
		i(1),
		t("}"),
	}),

	-- ── 点乘 / 叉乘 ───────────────────────────────────────────────
	s("dot", { t("\\cdot") }),
	s("cross", { t("\\times") }),

	-- ── 梯度 / 散度 / 旋度 ────────────────────────────────────────
	s("grad", { t("\\nabla ") }),
	s("div", { t("\\nabla \\cdot ") }),
	s("curl", { t("\\nabla \\times ") }),
	s("lapl", { t("\\nabla^2 ") }),

	-- ── 物理：bra-ket ─────────────────────────────────────────────
	s("ket", {
		t("\\left| "),
		i(1),
		t(" \\right\\rangle"),
	}),
	s("bra", {
		t("\\left\\langle "),
		i(1),
		t(" \\right|"),
	}),
	s("braket", {
		t("\\left\\langle "),
		i(1),
		t(" \\middle| "),
		i(2),
		t(" \\right\\rangle"),
	}),
	s("expval", {
		t("\\left\\langle "),
		i(1),
		t(" \\right\\rangle"),
	}),

	-- ── 物理：常用算符 ────────────────────────────────────────────
	s("ham", { t("\\hat{H}") }),
	s("comm", {
		t("\\left[ "),
		i(1),
		t(", "),
		i(2),
		t(" \\right]"),
	}),

	-- ── 上下标快捷 ────────────────────────────────────────────────
	s("sq", {
		t("^{2}"),
	}),
	s("cb", {
		t("^{3}"),
	}),
	s("inv", {
		t("^{-1}"),
	}),
	s("sr", {
		t("\\sqrt{"),
		i(1),
		t("}"),
	}),

	-- ── 常用字母 ──────────────────────────────────────────────────
	s("alpha", { t("\\alpha") }),
	s("beta", { t("\\beta") }),
	s("gamma", { t("\\gamma") }),
	s("delta", { t("\\delta") }),
	s("eps", { t("\\epsilon") }),
	s("veps", { t("\\varepsilon") }),
	s("theta", { t("\\theta") }),
	s("lambda", { t("\\lambda") }),
	s("mu", { t("\\mu") }),
	s("nu", { t("\\nu") }),
	s("pi", { t("\\pi") }),
	s("sigma", { t("\\sigma") }),
	s("omega", { t("\\omega") }),
	s("Omega", { t("\\Omega") }),
	s("phi", { t("\\phi") }),
	s("varphi", { t("\\varphi") }),
	s("psi", { t("\\psi") }),
	s("Psi", { t("\\Psi") }),
	s("xi", { t("\\xi") }),
	s("eta", { t("\\eta") }),
	s("rho", { t("\\rho") }),
	s("tau", { t("\\tau") }),
	s("hbar", { t("\\hbar") }),
	s("infty", { t("\\infty") }),

	-- ── 常用符号 ──────────────────────────────────────────────────
	s("to", { t("\\to") }),
	s("Rto", { t("\\Rightarrow") }),
	s("Lto", { t("\\Leftarrow") }),
	s("lto", { t("\\leftrightarrow") }),
	s("pm", { t("\\pm") }),
	s("mp", { t("\\mp") }),
	s("neq", { t("\\neq") }),
	s("leq", { t("\\leq") }),
	s("geq", { t("\\geq") }),
	s("approx", { t("\\approx") }),
	s("propto", { t("\\propto") }),
	s("sim", { t("\\sim") }),
	s("cdots", { t("\\cdots") }),
	s("ldots", { t("\\ldots") }),
	s("forall", { t("\\forall") }),
	s("exists", { t("\\exists") }),
	s("in", { t("\\in") }),
	s("notin", { t("\\notin") }),
	s("sub", { t("\\subset") }),
	s("cup", { t("\\cup") }),
	s("cap", { t("\\cap") }),
	s("empty", { t("\\emptyset") }),
	s("Re", { t("\\mathrm{Re}") }),
	s("Im", { t("\\mathrm{Im}") }),
})
