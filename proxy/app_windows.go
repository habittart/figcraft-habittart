package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

const (
	createNoWindow        = 0x08000000
	detachedProcess       = 0x00000008
	createNewProcessGroup = 0x00000200
)

func hidden(c *exec.Cmd) *exec.Cmd {
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
	return c
}

func defaultApp(dir string) string {
	if p := filepath.Join(dir, "figcraft.exe"); fileExists(p) {
		return p
	}
	if l := os.Getenv("LOCALAPPDATA"); l != "" {
		return filepath.Join(l, "FigCraft-Habittart", "figcraft.exe")
	}
	return "figcraft.exe"
}

func fileExists(p string) bool { st, err := os.Stat(p); return err == nil && !st.IsDir() }

func appRunning() bool {
	out, err := hidden(exec.Command("tasklist", "/FI", "IMAGENAME eq figcraft.exe", "/NH")).Output()
	return err == nil && strings.Contains(strings.ToLower(string(out)), "figcraft.exe")
}

// quitApp asks FigCraft's windows to close (like clicking X), so it can offer to save.
func quitApp() {
	hidden(exec.Command("taskkill", "/IM", "figcraft.exe")).Run()
}

func launchApp() error {
	c := exec.Command(*appPath, "--control", fmt.Sprint(*port))
	c.Dir = filepath.Dir(*appPath)
	c.SysProcAttr = &syscall.SysProcAttr{CreationFlags: detachedProcess | createNewProcessGroup}
	if err := c.Start(); err != nil {
		return err
	}
	return c.Process.Release()
}
