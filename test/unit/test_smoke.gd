# test/unit/test_smoke.gd
# GUT 冒烟测试：验证测试框架可运行、测试被收集、断言生效
extends GutTest

func test_smoke() -> void:
    assert_eq(2 + 2, 4, "GUT 冒烟：基础断言可运行")
