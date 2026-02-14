local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep

return {
	-- ==================== 基本数学环境 ====================
	s("dm", fmt("$ {} $", { i(1) })),
	s("mm", { t("$"), i(1), t(" $"), i(0) }),

	-- ==================== 分数和根号 ====================
	s("//", { t("frac("), i(1), t(", "), i(2), t(")"), i(0) }),
	s("frac", { t("frac("), i(1), t(", "), i(2), t(")"), i(0) }),
	s("sq", { t("sqrt("), i(1), t(")"), i(0) }),
	s("sqrt", { t("sqrt("), i(1), t(")"), i(0) }),

	-- ==================== 上下标 ====================
	s("sr", { t("^{"), i(1), t("}"), i(0) }),
	s("sb", { t("_{"), i(1), t("}"), i(0) }),

	-- ==================== 向量和张量 ====================
	s("vv", { t("bold("), i(1), t(")"), i(0) }),
	s("vec", { t("arrow("), i(1), t(")"), i(0) }),
	s("hhat", { t("hat(bold("), i(1), t("))"), i(0) }),
	s("uvec", { t("hat(bold("), i(1), t("))"), i(0) }),
	s("tensor", { t("bold(sans("), i(1), t("))"), i(0) }),

	-- ==================== 导数 ====================
	s("ddt", { t("(dif "), i(1), t(")/(dif t)"), i(0) }),
	s("ddx", { t("(dif "), i(1), t(")/(dif x)"), i(0) }),
	s("dv", { t("(dif "), i(1), t(")/(dif "), i(2), t(")"), i(0) }),
	s("dvn", { t("(dif^"), i(1, "n"), t(" "), i(2), t(")/(dif "), i(3), t("^"), rep(1), t(")"), i(0) }),

	-- 偏导数
	s("pdv", { t("(diff "), i(1), t(")/(diff "), i(2), t(")"), i(0) }),
	s("pddx", { t("(diff "), i(1), t(")/(diff x)"), i(0) }),
	s("pddy", { t("(diff "), i(1), t(")/(diff y)"), i(0) }),
	s("pddz", { t("(diff "), i(1), t(")/(diff z)"), i(0) }),
	s("pddt", { t("(diff "), i(1), t(")/(diff t)"), i(0) }),
	s("pvn", { t("(diff^"), i(1, "n"), t(" "), i(2), t(")/(diff "), i(3), t("^"), rep(1), t(")"), i(0) }),

	-- 全导数
	s("totald", { t("(upright(d) "), i(1), t(")/(upright(d) "), i(2), t(")"), i(0) }),

	-- ==================== 积分 ====================
	s("int", { t("integral_("), i(1, "a"), t(")^("), i(2, "b"), t(") "), i(3), t(" dif "), i(4, "x"), i(0) }),
	s("iint", { t("integral integral "), i(1), t(" dif A"), i(0) }),
	s("iiint", { t("integral integral integral "), i(1), t(" dif V"), i(0) }),
	s("oint", { t("integral.cont_("), i(1, "C"), t(") "), i(2), t(" dif "), i(3, "l"), i(0) }),
	s("dif", { t("dif "), i(1, "x"), i(0) }),

	-- ==================== 求和与乘积 ====================
	s("sum", { t("sum_("), i(1, "i=1"), t(")^("), i(2, "n"), t(") "), i(0) }),
	s("prod", { t("product_("), i(1, "i=1"), t(")^("), i(2, "n"), t(") "), i(0) }),

	-- ==================== 极限 ====================
	s("lim", { t("lim_("), i(1, "x"), t(" -> "), i(2, "infinity"), t(") "), i(0) }),
	s("limsup", { t('limits(upright("lim sup"))_('), i(1, "n"), t(" -> "), i(2, "infinity"), t(") "), i(0) }),
	s("liminf", { t('limits(upright("lim inf"))_('), i(1, "n"), t(" -> "), i(2, "infinity"), t(") "), i(0) }),

	-- ==================== 微分算符 ====================
	s("nabla", t("nabla")),
	s("grad", { t("nabla "), i(0) }),
	s("div", { t("nabla dot "), i(0) }),
	s("curl", { t("nabla times "), i(0) }),
	s("laplacian", { t("nabla^2 "), i(0) }),
	s("dalembertian", { t("square "), i(0) }),

	-- ==================== 向量运算 ====================
	s("dot", { i(1), t(" dot "), i(2), i(0) }),
	s("cross", { i(1), t(" times "), i(2), i(0) }),
	s("cdot", { i(1), t(" dot "), i(2), i(0) }),
	s("times", { i(1), t(" times "), i(2), i(0) }),

	-- ==================== 括号 ====================
	s("lr(", { t("lr(("), i(1), t("))"), i(0) }),
	s("lr[", { t("lr(["), i(1), t("])"), i(0) }),
	s("lr{", { t("lr({"), i(1), t("})"), i(0) }),
	s("avg", { t("angle.l "), i(1), t(" angle.r"), i(0) }),
	s("bra", { t("angle.l "), i(1), t("|"), i(0) }),
	s("ket", { t("|"), i(1), t(" angle.r"), i(0) }),
	s("braket", { t("angle.l "), i(1), t(" | "), i(2), t(" angle.r"), i(0) }),
	s("expval", { t("angle.l "), i(1), t(" angle.r"), i(0) }),

	-- ==================== 常用物理符号 ====================
	s("hbar", t("planck.reduce")),
	s("hslash", t("planck.reduce")),
	s("dag", t("dagger")),
	s("dagger", t("dagger")),
	s("partial", t("diff")),
	s("infty", t("infinity")),
	s("oo", t("infinity")),

	-- ==================== 希腊字母 ====================
	s("alpha", t("alpha")),
	s("beta", t("beta")),
	s("gamma", t("gamma")),
	s("delta", t("delta")),
	s("epsilon", t("epsilon")),
	s("varepsilon", t("epsilon.alt")),
	s("zeta", t("zeta")),
	s("eta", t("eta")),
	s("theta", t("theta")),
	s("vartheta", t("theta.alt")),
	s("kappa", t("kappa")),
	s("lambda", t("lambda")),
	s("mu", t("mu")),
	s("nu", t("nu")),
	s("xi", t("xi")),
	s("pi", t("pi")),
	s("rho", t("rho")),
	s("sigma", t("sigma")),
	s("tau", t("tau")),
	s("upsilon", t("upsilon")),
	s("phi", t("phi")),
	s("varphi", t("phi.alt")),
	s("chi", t("chi")),
	s("psi", t("psi")),
	s("omega", t("omega")),

	-- 大写希腊字母
	s("Gamma", t("Gamma")),
	s("Delta", t("Delta")),
	s("Theta", t("Theta")),
	s("Lambda", t("Lambda")),
	s("Xi", t("Xi")),
	s("Pi", t("Pi")),
	s("Sigma", t("Sigma")),
	s("Upsilon", t("Upsilon")),
	s("Phi", t("Phi")),
	s("Psi", t("Psi")),
	s("Omega", t("Omega")),

	-- ==================== 常用函数 ====================
	s("sin", t("sin")),
	s("cos", t("cos")),
	s("tan", t("tan")),
	s("cot", t("cot")),
	s("sec", t("sec")),
	s("csc", t("csc")),
	s("sinh", t("sinh")),
	s("cosh", t("cosh")),
	s("tanh", t("tanh")),
	s("arcsin", t("arcsin")),
	s("arccos", t("arccos")),
	s("arctan", t("arctan")),
	s("log", t("log")),
	s("ln", t("ln")),
	s("exp", t("exp")),

	-- ==================== 常用装饰 ====================
	s("bar", { t("overline("), i(1), t(")"), i(0) }),
	s("hat", { t("hat("), i(1), t(")"), i(0) }),
	s("tilde", { t("tilde("), i(1), t(")"), i(0) }),
	s("dot", { t("dot("), i(1), t(")"), i(0) }),
	s("ddot", { t("dot.double("), i(1), t(")"), i(0) }),
	s("prime", { i(1), t("'"), i(0) }),

	-- ==================== 物理常用记号 ====================
	s("abs", { t("lr(|"), i(1), t("|)"), i(0) }),
	s("norm", { t("lr(||"), i(1), t("||)"), i(0) }),
	s("eval", { t("lr("), i(1), t(")_("), i(2), t(")"), i(0) }),

	-- ==================== 关系符号 ====================
	s("approx", t("approx")),
	s("sim", t("tilde")),
	s("propto", t("prop")),
	s("equiv", t("equiv")),
	s("neq", t("eq.not")),
	s("!=", t("eq.not")),
	s("leq", t("lt.eq")),
	s("geq", t("gt.eq")),
	s("<<", t("lt.double")),
	s(">>", t("gt.double")),

	-- ==================== 箭头 ====================
	s("->", t("arrow.r")),
	s("<-", t("arrow.l")),
	s("=>", t("arrow.r.double")),
	s("<=>", t("arrow.l.r.double")),
	s("implies", t("arrow.r.double")),
	s("iff", t("arrow.l.r.double")),

	-- ==================== 量子力学相关 ====================
	s("comm", { t("lr(["), i(1), t(", "), i(2), t("])"), i(0) }),
	s("acomm", { t("lr({"), i(1), t(", "), i(2), t("})"), i(0) }),
	s("op", { t("hat("), i(1), t(")"), i(0) }),
	s("oper", { t("hat("), i(1), t(")"), i(0) }),

	-- ==================== 特殊数集 ====================
	s("NN", t("NN")),
	s("ZZ", t("ZZ")),
	s("QQ", t("QQ")),
	s("RR", t("RR")),
	s("CC", t("CC")),

	-- ==================== 其他符号 ====================
	s("...", t("dots")),
	s("cdots", t("dots.h.c")),
	s("vdots", t("dots.v")),
	s("ddots", t("dots.down")),
	s("therefore", t("therefore")),
	s("because", t("because")),
	s("qed", t("qed")),

	-- ==================== 集合运算 ====================
	s("in", t("in")),
	s("notin", t("in.not")),
	s("subset", t("subset")),
	s("supset", t("supset")),
	s("subseteq", t("subset.eq")),
	s("supseteq", t("supset.eq")),
	s("union", t("union")),
	s("inter", t("sect")),
	s("cap", t("sect")),
	s("cup", t("union")),
	s("emptyset", t("emptyset")),

	-- ==================== 逻辑符号 ====================
	s("forall", t("forall")),
	s("exists", t("exists")),
	s("nexists", t("exists.not")),
	s("land", t("and")),
	s("lor", t("or")),
	s("lnot", t("not")),

	-- ==================== 物理单位相关 ====================
	s("unit", { t("upright("), i(1), t(")"), i(0) }),

	-- ==================== 特殊物理记号 ====================
	s("ell", t("ell")),
	s("wp", t("wp")),
	s("Re", t("Re")),
	s("Im", t("Im")),
	s("Tr", t('upright("Tr")')),
	s("tr", t('upright("tr")')),
	s("det", t('upright("det")')),
	s("rank", t('upright("rank")')),
	s("dim", t('upright("dim")')),
}
