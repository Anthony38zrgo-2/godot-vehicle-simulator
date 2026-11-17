// Francisco Cidade  |  https://fcidade.com  |  https://fcidade.itch.io
shader_type canvas_item;
// Pixel Dither: pixelate, dither and palette-swap any sprite or image.
// Godot 4.x, CanvasItem. CC0: use it, change it, sell it with your game.
// Note: the node's modulate is not applied (the shader outputs the final color).

// Size of each big pixel, measured in pixels of the source texture.
uniform int pixel_size : hint_range(1, 32, 1) = 4;

// Which colors to snap to. "Posterize" keeps the image colors but reduces them.
uniform int palette_mode : hint_enum("Posterize", "PICO-8", "Game Boy", "Sweetie 16", "Commodore 64", "Endesga 32", "CGA", "Resurrect 64", "1-bit") = 3;
// Posterize only: shades per color channel (2 = 8 colors, 4 = 64 colors).
uniform int levels : hint_range(2, 16, 1) = 4;

// Ordered dithering pattern. Bayer 8x8 is finer, Bayer 4x4 is chunkier.
uniform int dither_mode : hint_enum("Off", "Bayer 4x4", "Bayer 8x8") = 1;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

// Adjust the image before it is quantized (helps dark or washed-out sources).
uniform float brightness : hint_range(-0.5, 0.5, 0.01) = 0.0;
uniform float contrast : hint_range(0.5, 2.0, 0.01) = 1.0;

// Palettes as 0-255 RGB. PICO-8 (by Lexaloffle), Game Boy, Sweetie 16 (by GrafxKid), Commodore 64,
// Endesga 32 (by Endesga), CGA, Resurrect 64 (by Kerrie Lake) and 1-bit.
const vec3 PALETTE[154] = vec3[154](
	// PICO-8, indices 0..15
	vec3(0.0, 0.0, 0.0), vec3(29.0, 43.0, 83.0), vec3(126.0, 37.0, 83.0), vec3(0.0, 135.0, 81.0),
	vec3(171.0, 82.0, 54.0), vec3(95.0, 87.0, 79.0), vec3(194.0, 195.0, 199.0), vec3(255.0, 241.0, 232.0),
	vec3(255.0, 0.0, 77.0), vec3(255.0, 163.0, 0.0), vec3(255.0, 236.0, 39.0), vec3(0.0, 228.0, 54.0),
	vec3(41.0, 173.0, 255.0), vec3(131.0, 118.0, 156.0), vec3(255.0, 119.0, 168.0), vec3(255.0, 204.0, 170.0),
	// Game Boy, indices 16..19
	vec3(15.0, 56.0, 15.0), vec3(48.0, 98.0, 48.0), vec3(139.0, 172.0, 15.0), vec3(155.0, 188.0, 15.0),
	// Sweetie 16, indices 20..35
	vec3(26.0, 28.0, 44.0), vec3(93.0, 39.0, 93.0), vec3(177.0, 62.0, 83.0), vec3(239.0, 125.0, 87.0),
	vec3(255.0, 205.0, 117.0), vec3(167.0, 240.0, 112.0), vec3(56.0, 183.0, 100.0), vec3(37.0, 113.0, 121.0),
	vec3(41.0, 54.0, 111.0), vec3(59.0, 93.0, 201.0), vec3(65.0, 166.0, 246.0), vec3(115.0, 239.0, 247.0),
	vec3(244.0, 244.0, 244.0), vec3(148.0, 176.0, 194.0), vec3(86.0, 108.0, 134.0), vec3(51.0, 60.0, 87.0),
	// Commodore 64 (Pepto), indices 36..51
	vec3(0.0, 0.0, 0.0), vec3(255.0, 255.0, 255.0), vec3(104.0, 55.0, 43.0), vec3(112.0, 164.0, 178.0),
	vec3(111.0, 61.0, 134.0), vec3(88.0, 141.0, 67.0), vec3(53.0, 40.0, 121.0), vec3(184.0, 199.0, 111.0),
	vec3(111.0, 79.0, 37.0), vec3(67.0, 57.0, 0.0), vec3(154.0, 103.0, 89.0), vec3(68.0, 68.0, 68.0),
	vec3(108.0, 108.0, 108.0), vec3(154.0, 210.0, 132.0), vec3(108.0, 94.0, 181.0), vec3(149.0, 149.0, 149.0),
	// Endesga 32 (by Endesga), indices 52..83
	vec3(190.0, 74.0, 47.0), vec3(215.0, 118.0, 67.0), vec3(234.0, 212.0, 170.0), vec3(228.0, 166.0, 114.0),
	vec3(184.0, 111.0, 80.0), vec3(115.0, 62.0, 57.0), vec3(62.0, 39.0, 49.0), vec3(162.0, 38.0, 51.0),
	vec3(228.0, 59.0, 68.0), vec3(247.0, 118.0, 34.0), vec3(254.0, 174.0, 52.0), vec3(254.0, 231.0, 97.0),
	vec3(99.0, 199.0, 77.0), vec3(62.0, 137.0, 72.0), vec3(38.0, 92.0, 66.0), vec3(25.0, 60.0, 62.0),
	vec3(18.0, 78.0, 137.0), vec3(0.0, 153.0, 219.0), vec3(44.0, 232.0, 245.0), vec3(255.0, 255.0, 255.0),
	vec3(192.0, 203.0, 220.0), vec3(139.0, 155.0, 180.0), vec3(90.0, 105.0, 136.0), vec3(58.0, 68.0, 102.0),
	vec3(38.0, 43.0, 68.0), vec3(24.0, 20.0, 37.0), vec3(255.0, 0.0, 68.0), vec3(104.0, 56.0, 108.0),
	vec3(181.0, 80.0, 136.0), vec3(246.0, 117.0, 122.0), vec3(232.0, 183.0, 150.0), vec3(194.0, 133.0, 105.0),
	// CGA palette 1 high intensity, indices 84..87
	vec3(0.0, 0.0, 0.0), vec3(85.0, 255.0, 255.0), vec3(255.0, 85.0, 255.0), vec3(255.0, 255.0, 255.0),
	// Resurrect 64 (by Kerrie Lake), indices 88..151
	vec3(46.0, 34.0, 47.0), vec3(62.0, 53.0, 70.0), vec3(98.0, 85.0, 101.0), vec3(150.0, 108.0, 108.0),
	vec3(171.0, 148.0, 122.0), vec3(105.0, 79.0, 98.0), vec3(127.0, 112.0, 138.0), vec3(155.0, 171.0, 178.0),
	vec3(199.0, 220.0, 208.0), vec3(255.0, 255.0, 255.0), vec3(110.0, 39.0, 39.0), vec3(179.0, 56.0, 49.0),
	vec3(234.0, 79.0, 54.0), vec3(245.0, 125.0, 74.0), vec3(174.0, 35.0, 52.0), vec3(232.0, 59.0, 59.0),
	vec3(251.0, 107.0, 29.0), vec3(247.0, 150.0, 23.0), vec3(249.0, 194.0, 43.0), vec3(122.0, 48.0, 69.0),
	vec3(158.0, 69.0, 57.0), vec3(205.0, 104.0, 61.0), vec3(230.0, 144.0, 78.0), vec3(251.0, 185.0, 84.0),
	vec3(76.0, 62.0, 36.0), vec3(103.0, 102.0, 51.0), vec3(162.0, 169.0, 71.0), vec3(213.0, 224.0, 75.0),
	vec3(251.0, 255.0, 134.0), vec3(22.0, 90.0, 76.0), vec3(35.0, 144.0, 99.0), vec3(30.0, 188.0, 115.0),
	vec3(145.0, 219.0, 105.0), vec3(205.0, 223.0, 108.0), vec3(49.0, 54.0, 56.0), vec3(55.0, 78.0, 74.0),
	vec3(84.0, 126.0, 100.0), vec3(146.0, 169.0, 132.0), vec3(178.0, 186.0, 144.0), vec3(11.0, 94.0, 101.0),
	vec3(11.0, 138.0, 143.0), vec3(14.0, 175.0, 155.0), vec3(48.0, 225.0, 185.0), vec3(143.0, 248.0, 226.0),
	vec3(50.0, 51.0, 83.0), vec3(72.0, 74.0, 119.0), vec3(77.0, 101.0, 180.0), vec3(77.0, 155.0, 230.0),
	vec3(143.0, 211.0, 255.0), vec3(69.0, 41.0, 63.0), vec3(107.0, 62.0, 117.0), vec3(144.0, 94.0, 169.0),
	vec3(168.0, 132.0, 243.0), vec3(234.0, 173.0, 237.0), vec3(117.0, 60.0, 84.0), vec3(162.0, 75.0, 111.0),
	vec3(207.0, 101.0, 127.0), vec3(237.0, 128.0, 153.0), vec3(131.0, 28.0, 93.0), vec3(195.0, 36.0, 84.0),
	vec3(240.0, 79.0, 120.0), vec3(246.0, 129.0, 129.0), vec3(252.0, 167.0, 144.0), vec3(253.0, 203.0, 176.0),
	// 1-bit black and white, indices 152..153
	vec3(0.0, 0.0, 0.0), vec3(255.0, 255.0, 255.0)
);

const int BAYER4[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
const int BAYER2[4] = int[4](0, 2, 3, 1);

// Threshold in 0..1 for the dither cell at integer position p.
float bayer(ivec2 p, int mode) {
	int v4 = BAYER4[(p.y & 3) * 4 + (p.x & 3)];
	if (mode == 1) {
		return (float(v4) + 0.5) / 16.0;
	}
	int v8 = 4 * v4 + BAYER2[((p.y >> 2) & 1) * 2 + ((p.x >> 2) & 1)];
	return (float(v8) + 0.5) / 64.0;
}

vec3 nearest(vec3 c, int start, int count) {
	float best = 1e9;
	vec3 result = vec3(0.0);
	for (int i = 0; i < count; i++) {
		vec3 p = PALETTE[start + i] / 255.0;
		vec3 d = c - p;
		float dist = dot(d * d, vec3(0.3, 0.59, 0.11));
		if (dist < best) {
			best = dist;
			result = p;
		}
	}
	return result;
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	float ps = float(pixel_size);

	// Sample the middle of each big pixel.
	vec2 cell = floor(UV * size / ps);
	vec2 uv = clamp((cell + 0.5) * ps / size, vec2(0.0), vec2(1.0) - 0.5 / size);
	vec4 tex = texture(TEXTURE, uv);

	vec3 c = (tex.rgb - 0.5) * contrast + 0.5 + brightness;

	// Dither: push the color up or down a little before snapping, by an amount
	// that depends on how far apart the palette colors are.
	// Dither strength is scaled by how far apart the palette colors are: few colors need a
	// wide spread, many colors a narrow one.
	float spread = 0.2;
	if (palette_mode == 0) {
		spread = 1.0 / float(levels - 1);
	} else if (palette_mode == 2) {
		spread = 0.35;
	} else if (palette_mode == 5) {
		spread = 0.15;
	} else if (palette_mode == 6) {
		spread = 0.4;
	} else if (palette_mode == 7) {
		spread = 0.1;
	} else if (palette_mode == 8) {
		spread = 0.5;
	}
	if (dither_mode > 0) {
		c += (bayer(ivec2(cell), dither_mode) - 0.5) * dither_strength * spread;
	}
	c = clamp(c, 0.0, 1.0);

	vec3 result;
	if (palette_mode == 0) {
		float steps = float(levels - 1);
		result = floor(c * steps + 0.5) / steps;
	} else if (palette_mode == 1) {
		result = nearest(c, 0, 16);
	} else if (palette_mode == 2) {
		result = nearest(c, 16, 4);
	} else if (palette_mode == 3) {
		result = nearest(c, 20, 16);
	} else if (palette_mode == 4) {
		result = nearest(c, 36, 16);
	} else if (palette_mode == 5) {
		result = nearest(c, 52, 32);
	} else if (palette_mode == 6) {
		result = nearest(c, 84, 4);
	} else if (palette_mode == 7) {
		result = nearest(c, 88, 64);
	} else {
		result = nearest(c, 152, 2);
	}

	COLOR = vec4(result, tex.a);
}
