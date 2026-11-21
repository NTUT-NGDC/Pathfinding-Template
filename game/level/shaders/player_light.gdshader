// 玩家視野圈：玩家周圍看得到，外面變暗，邊緣柔和。
// 數字由 player_light.gd 每一幀傳進來（單位是畫面上的像素）。
shader_type canvas_item;

uniform vec2 center = vec2(640.0, 360.0);   // 玩家在畫面上的位置
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float radius = 200.0;               // 看得到的半徑
uniform float softness = 80.0;              // 邊緣漸層的寬度
uniform float darkness = 0.92;              // 外面有多暗（1＝全黑）

void fragment() {
	float d = distance(UV * rect_size, center);
	float a = smoothstep(radius - softness, radius, d) * darkness;
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
