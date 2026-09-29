class_name HudTheme
extends RefCounted
## Phase 11 — shared UI theme factory (plan: docs/plans/phase-11-ui.md D2).
## One alpine-night palette + StyleBoxFlat builders consumed by RaceHUD and
## Garage. Default engine font on purpose (assets/fonts/ is empty — a real
## font file can drop in here later without touching any caller).

# --- palette -----------------------------------------------------------------

const INK := Color(0.07, 0.09, 0.12, 0.82)  # card glass — dark slate
const INK_SOFT := Color(0.10, 0.13, 0.17, 0.68)  # chips — lighter, fainter
const STROKE := Color(0.16, 0.22, 0.28, 0.9)  # hairline borders
const GOLD := Color(1.0, 0.85, 0.3)  # accents — matches the Phase 6 gold
const GOLD_DIM := Color(0.85, 0.72, 0.28)
const WHITE := Color(0.96, 0.97, 0.98)
const MUTED := Color(0.62, 0.68, 0.74)
const CYAN := Color(0.55, 0.85, 1.0)  # info accents (gate/next)
const RED := Color(1.0, 0.28, 0.22)  # wrong way / danger
const GREEN := Color(0.45, 0.9, 0.5)  # confirmations

const CORNER := 10.0  # px — one radius everywhere


# --- style boxes ---------------------------------------------------------------


static func panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK
	sb.border_color = STROKE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(CORNER)
	sb.set_content_margin_all(12)
	return sb


static func chip() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK_SOFT
	sb.border_color = STROKE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(CORNER * 0.8)
	sb.content_margin_left = Config.HUD_CHIP_PAD_X
	sb.content_margin_right = Config.HUD_CHIP_PAD_X
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func button() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.17, 0.22, 0.92)
	sb.border_color = Color(0.30, 0.38, 0.46, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func button_hot() -> StyleBoxFlat:
	## Primary-action variant (RACE AGAIN, RESUME): gold fill, dark text.
	var sb := button()
	sb.bg_color = GOLD
	sb.border_color = GOLD_DIM
	return sb


# --- widget helpers -------------------------------------------------------------


static func styled_button(text: String, hot := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", button_hot() if hot else button())
	b.add_theme_stylebox_override("hover", button_hot() if hot else _hover())
	b.add_theme_stylebox_override("pressed", button_hot() if hot else _hover())
	b.add_theme_stylebox_override("disabled", _disabled())
	b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12) if hot else WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.12) if hot else WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.12) if hot else WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED * 0.6)
	b.add_theme_font_size_override("font_size", 17)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func chip_label(caption: String, col: Color) -> VBoxContainer:
	## Two-line chip content: tiny caption over the value (value set by caller).
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap := label(caption, 11, col * 0.8)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	return box


static func backdropped(panel: PanelContainer) -> void:
	## Applies the card style to a panel (call after composition, not instead of).
	panel.add_theme_stylebox_override("panel", panel())


static func _hover() -> StyleBoxFlat:
	var sb := button()
	sb.bg_color = Color(0.18, 0.24, 0.31, 0.95)
	sb.border_color = CYAN * 0.7
	return sb


static func _disabled() -> StyleBoxFlat:
	var sb := button()
	sb.bg_color = Color(0.10, 0.12, 0.14, 0.7)
	sb.border_color = Color(0.16, 0.18, 0.20, 0.8)
	return sb
