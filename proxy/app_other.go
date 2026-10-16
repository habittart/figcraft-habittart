//go:build !darwin && !windows

package main

import (
	"fmt"
	"os/exec"
)

func defaultApp(string) string { return "figcraft" }

func appRunning() bool { return exec.Command("pgrep", "-x", "figcraft").Run() == nil }

func quitApp() { exec.Command("pkill", "-x", "figcraft").Run() }

func launchApp() error {
	c := exec.Command(*appPath, "--control", fmt.Sprint(*port))
	if err := c.Start(); err != nil {
		return err
	}
	return c.Process.Release()
}
