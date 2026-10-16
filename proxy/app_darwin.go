package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func defaultApp(string) string {
	if home, err := os.UserHomeDir(); err == nil {
		if _, err := os.Stat(filepath.Join(home, "Applications", "FigCraft.app")); err == nil {
			return filepath.Join(home, "Applications", "FigCraft.app")
		}
	}
	return "/Applications/FigCraft.app"
}

func appRunning() bool {
	return exec.Command("/usr/bin/pgrep", "-f", "FigCraft.app/Contents/MacOS/").Run() == nil
}

func quitApp() {
	exec.Command("/usr/bin/osascript", "-e", fmt.Sprintf(`tell application id %q to quit`, *bundleID)).Run()
}

func launchApp() error {
	return exec.Command("/usr/bin/open", "-n", "-a", *appPath, "--args", "--control", fmt.Sprint(*port)).Run()
}
