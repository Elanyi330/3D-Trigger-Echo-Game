# test/unit/test_input_actions.gd
# M1 任务0 审查修复：输入动作注册 + macOS 数字键物理码校验
# 背景（真实事件实测，2026-08-06，Godot 4.7.1 + macOS）：
#   - 顶排数字键 1-4（kVK 18-21）→ physical_keycode = KEY_1..4（49-52）
#   - 数字键盘 1-4（kVK 83-86）  → physical_keycode = KEY_KP_1..4（4194439-4194442）
#   因此每动作双绑定两个物理码（OR 语义，同 move_forward 多事件模式），缺一不可。
extends GutTest

func test_m1_input_actions_all_registered() -> void:
    var actions: Array[String] = ["fire", "reload", "aim", "weapon_1", "weapon_2", "weapon_3", "weapon_4", "next_weapon"]
    for action in actions:
        assert_true(InputMap.has_action(action), "动作 %s 已注册" % action)

func test_weapon_slot_keys_use_both_macos_physical_keycode_paths() -> void:
    # 顶排 49-52（实测）与数字键盘 4194439-42 双绑定；仅断言其一（如仅 KEY_1=49）会假绿
    var expected: Dictionary = {
        "weapon_1": [KEY_1, KEY_KP_1],
        "weapon_2": [KEY_2, KEY_KP_2],
        "weapon_3": [KEY_3, KEY_KP_3],
        "weapon_4": [KEY_4, KEY_KP_4],
    }
    for action in expected:
        var events := InputMap.action_get_events(action)
        assert_eq(events.size(), 2, "%s 绑定 2 个事件（顶排 + 数字键盘）" % action)
        var codes: Array[int] = []
        for ev in events:
            var key := ev as InputEventKey
            assert_not_null(key, "%s 绑定为按键事件" % action)
            if key != null:
                assert_eq(key.device, -1, "%s device = -1（任意设备）" % action)
                codes.append(key.physical_keycode)
        for code in expected[action]:
            assert_true(codes.has(code), "%s 含物理码 %d" % [action, code])

func test_other_m1_actions_bindings() -> void:
    var mouse: Dictionary = {
        "fire": MOUSE_BUTTON_LEFT,
        "aim": MOUSE_BUTTON_RIGHT,
        "next_weapon": MOUSE_BUTTON_WHEEL_UP,
    }
    for action in mouse:
        var events := InputMap.action_get_events(action)
        assert_eq(events.size(), 1, "%s 绑定 1 个事件" % action)
        var btn := events[0] as InputEventMouseButton
        assert_not_null(btn, "%s 绑定为鼠标事件" % action)
        if btn != null:
            assert_eq(btn.button_index, mouse[action], "%s 鼠标键位正确" % action)
            assert_eq(btn.device, -1, "%s device = -1（任意设备）" % action)

    var reload_events := InputMap.action_get_events("reload")
    assert_eq(reload_events.size(), 1, "reload 绑定 1 个事件")
    var reload_key := reload_events[0] as InputEventKey
    assert_not_null(reload_key, "reload 绑定为按键事件")
    if reload_key != null:
        assert_eq(reload_key.physical_keycode, KEY_R, "reload = R（82）")
        assert_eq(reload_key.device, -1, "reload device = -1（任意设备）")
