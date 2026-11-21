// 接近警告：畫面邊緣變紅，中間透明。strength 0～1 由 hud.gd 設定，會跟著心跳一閃一閃。
shader_type canvas_item;

uniform float strength = 0.0;

void fragment() {
	vec2 from_center = abs(UV - vec2(0.5)) * 2.0;          // 中間 0、邊緣 1
	float edge = smoothstep(0.55, 1.0, max(from_center.x, from_center.y));
	float beat = 0.75 + 0.25 * sin(TIME * (4.0 + strength * 6.0));
	COLOR = vec4(0.8, 0.0, 0.0, edge * strength * beat * 0.7);
}
