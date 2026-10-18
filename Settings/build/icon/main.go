// Command icon draws Fluent's app icon: a text caret with a sparkle beside
// it ("your typing, improved") in white on an indigo tile.
//
//	go run ./build/icon app N out.png    the whole icon, N pixels square
//	go run ./build/icon glyph N out.png  the caret and sparkle alone, white on
//	                                     clear, as big as on the tile: the
//	                                     layer of build/darwin/AppIcon.icon,
//	                                     which macOS 26 lays on a tile of its
//	                                     own, light or dark
//
// `make settings-icon` runs it for every size the app needs.
package main

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: icon app|glyph N out.png")
		os.Exit(2)
	}
	n, err := strconv.Atoi(os.Args[2])
	if err != nil || n < 16 {
		fmt.Fprintln(os.Stderr, "icon: N is a size in pixels, 16 or more")
		os.Exit(2)
	}
	var img image.Image
	switch os.Args[1] {
	case "app":
		img = app(n)
	case "glyph":
		img = glyph(n)
	default:
		fmt.Fprintln(os.Stderr, "icon: app or glyph")
		os.Exit(2)
	}
	f, err := os.Create(os.Args[3])
	if err == nil {
		err = png.Encode(f, img)
		if cerr := f.Close(); err == nil {
			err = cerr
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "icon:", err)
		os.Exit(1)
	}
}

// inGlyph: whether a point of the tile (0–1 across, y down) is in the
// caret or a sparkle.
func inGlyph(x, y float64) bool {
	const caretX, top, bottom = 0.39, 0.255, 0.745
	// the stem's round ends stay inside the serifs
	return capsule(x, y, caretX, top+0.006, caretX, bottom-0.006, 0.034) || // stem
		capsule(x, y, caretX-0.105, top, caretX+0.105, top, 0.036) || // serifs
		capsule(x, y, caretX-0.105, bottom, caretX+0.105, bottom, 0.036) ||
		sparkle(x, y, 0.665, 0.37, 0.19) ||
		sparkle(x, y, 0.735, 0.645, 0.085)
}

// capsule: within r of the segment from (ax, ay) to (bx, by).
func capsule(x, y, ax, ay, bx, by, r float64) bool {
	dx, dy := bx-ax, by-ay
	t := 0.0
	if l := dx*dx + dy*dy; l > 0 {
		t = math.Max(0, math.Min(1, ((x-ax)*dx+(y-ay)*dy)/l))
	}
	px, py := ax+t*dx-x, ay+t*dy-y
	return px*px+py*py <= r*r
}

// sparkle: a four-pointed star with curved sides, r from its centre to a
// point.
func sparkle(x, y, cx, cy, r float64) bool {
	return math.Sqrt(math.Abs(x-cx)/r)+math.Sqrt(math.Abs(y-cy)/r) <= 1
}

// inTile: whether (x, y), in pixels of a side-pixel tile at (0, 0), is in
// its rounded square.
func inTile(x, y, side float64) bool {
	r := side * 0.225
	qx := math.Max(math.Abs(x-side/2)-(side/2-r), 0)
	qy := math.Max(math.Abs(y-side/2)-(side/2-r), 0)
	return qx*qx+qy*qy <= r*r
}

// samples per pixel side: more for small icons, where an edge is most of
// a pixel
func samples(n int) int {
	if n <= 64 {
		return 8
	}
	return 4
}

// glyph is the caret and sparkle, white on clear, the tile filling the
// canvas.
func glyph(n int) image.Image {
	img := image.NewNRGBA(image.Rect(0, 0, n, n))
	ss := samples(n)
	S := float64(n)
	for py := 0; py < n; py++ {
		for px := 0; px < n; px++ {
			in := 0
			for sy := 0; sy < ss; sy++ {
				for sx := 0; sx < ss; sx++ {
					x := (float64(px) + (float64(sx)+0.5)/float64(ss)) / S
					y := (float64(py) + (float64(sy)+0.5)/float64(ss)) / S
					if inGlyph(x, y) {
						in++
					}
				}
			}
			a := float64(in) / float64(ss*ss)
			img.SetNRGBA(px, py, color.NRGBA{255, 255, 255, uint8(a*255 + 0.5)})
		}
	}
	return img
}

// The tile shades from the top colour to the bottom one.
var top, bottom = [3]float64{0x6d, 0x65, 0xf6}, [3]float64{0x43, 0x38, 0xca}

// app is the whole icon on Apple's grid: the tile is 80% of the canvas,
// with a soft shadow under it.
func app(n int) image.Image {
	img := image.NewNRGBA(image.Rect(0, 0, n, n))
	ss := samples(n)
	S := float64(n)
	inset, side := S*0.1, S*0.8
	for py := 0; py < n; py++ {
		for px := 0; px < n; px++ {
			var tile, mark float64
			for sy := 0; sy < ss; sy++ {
				for sx := 0; sx < ss; sx++ {
					x := float64(px) + (float64(sx)+0.5)/float64(ss) - inset
					y := float64(py) + (float64(sy)+0.5)/float64(ss) - inset
					if inTile(x, y, side) {
						tile++
						if inGlyph(x/side, y/side) {
							mark++
						}
					}
				}
			}
			k := float64(ss * ss)
			tile, mark = tile/k, mark/k
			t := math.Max(0, math.Min(1, (float64(py)+0.5-inset)/side))
			var c [3]float64
			for i := range c {
				c[i] = top[i] + (bottom[i]-top[i])*t
				// white over the tile where the glyph is
				if tile > 0 {
					c[i] = c[i]*(1-mark/tile) + 255*(mark/tile)
				}
			}
			// The shadow shows where the tile doesn't cover the pixel.
			sh := shadow(float64(px)+0.5-inset, float64(py)+0.5-inset, side)
			alpha := tile + sh*(1-tile)
			if alpha == 0 {
				continue
			}
			// premultiplied: the tile's colour, then black for the shadow
			for i := range c {
				c[i] = c[i] * tile / alpha
			}
			img.SetNRGBA(px, py, color.NRGBA{uint8(c[0] + 0.5), uint8(c[1] + 0.5), uint8(c[2] + 0.5), uint8(alpha*255 + 0.5)})
		}
	}
	return img
}

// shadow is the opacity of the tile's shadow at (x, y): the tile's shape
// moved down a little and blurred by distance.
func shadow(x, y, side float64) float64 {
	r := side * 0.225
	y -= side * 0.01
	qx := math.Max(math.Abs(x-side/2)-(side/2-r), 0)
	qy := math.Max(math.Abs(y-side/2)-(side/2-r), 0)
	d := math.Hypot(qx, qy) - r // outside the tile when positive
	blur := side * 0.022
	if d <= 0 {
		return 0.2
	}
	return 0.2 * math.Exp(-d*d/(2*blur*blur))
}
