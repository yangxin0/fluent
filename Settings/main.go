// Fluent's Settings app (Fluent.app): one window of plain HTML pages that
// set up the input method and edit its config file, hosted with Wails the
// way magpie hosts its own. It shares no code with the input method
// (Fluent-Input.app, in Sources/); the two meet only in the files and the
// notification docs/config.md describes.
package main

import (
	"embed"
	"io/fs"
	"log"
	"os"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

//go:embed assets
var assets embed.FS

//go:embed assets/icon.png
var icon []byte

// version is set by the Makefile (-X main.version=…).
var version = "dev"

const (
	defaultWidth, defaultHeight = 780, 620
	minWidth, minHeight         = 640, 480
)

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatal(err)
	}
	pages, _ := fs.Sub(assets, "assets")
	h := newHost(home, version)
	app := application.New(application.Options{
		Name:        "Fluent",
		Description: "Settings for the Fluent input method",
		Icon:        icon,
		Assets:      application.AssetOptions{Handler: h.handler(pages)},
		Mac: application.MacOptions{
			ActivationPolicy: application.ActivationPolicyRegular,
			ApplicationShouldTerminateAfterLastWindowClosed: true,
		},
		ErrorHandler: func(err error) { log.Println("fluent:", err) },
	})

	// Wails' default menus (Edit gives the text fields ⌘C and ⌘V); Help
	// opens the repository in the browser instead of a page in the window.
	menu := application.DefaultApplicationMenu()
	if help := menu.FindByRole(application.HelpMenu); help != nil {
		help.GetSubmenu().Clear()
		help.GetSubmenu().Add("Fluent on GitHub").OnClick(func(*application.Context) {
			app.Browser.OpenURL(repository)
		})
	}
	app.Menu.Set(menu)

	saved := h.prefs.load()
	width, height := defaultWidth, defaultHeight
	if saved.Width >= minWidth && saved.Height >= minHeight {
		width, height = saved.Width, saved.Height
	}
	// The window's colour before the pages paint, so a dark Mac sees no
	// white flash: the pages' --bg.
	background := application.NewRGB(0xf4, 0xf4, 0xf6)
	if darkMode() {
		background = application.NewRGB(0x1a, 0x1a, 0x1e)
	}
	window := app.Window.NewWithOptions(application.WebviewWindowOptions{
		Name:             "main",
		Title:            "Fluent",
		URL:              "/",
		Width:            width,
		Height:           height,
		MinWidth:         minWidth,
		MinHeight:        minHeight,
		BackgroundColour: background,
		// The pages draw the header the traffic lights sit in, and say
		// which parts of it drag the window (--wails-draggable).
		Mac: application.MacWindow{TitleBar: application.MacTitleBarHiddenInset},
	})
	h.window = window

	// The size is kept once a resize settles, and the window opens at it.
	var settle *time.Timer
	window.OnWindowEvent(events.Common.WindowDidResize, func(*application.WindowEvent) {
		if settle != nil {
			settle.Stop()
		}
		settle = time.AfterFunc(500*time.Millisecond, func() {
			if window.IsFullscreen() || window.IsMinimised() {
				return
			}
			w, ht := window.Size()
			if w >= minWidth && ht >= minHeight {
				h.prefs.update(func(p *prefs) { p.Width, p.Height = w, ht })
			}
		})
	})

	if err := app.Run(); err != nil {
		log.Fatal(err)
	}
}
