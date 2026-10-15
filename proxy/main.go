// figcraft-mcp: a resilient stdio MCP proxy in front of `figcraft-cli mcp --attach PORT`.
//
//   - Starts instantly: initialize / tools/list are answered by a headless figcraft-cli,
//     so the MCP shows "connected" even when FigCraft is closed.
//   - On the first call that needs the app, it makes sure FigCraft is running with its
//     control channel (relaunching it with --control PORT if needed) and attaches.
//   - If the app is closed or restarted later, the next call reconnects and is retried once.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

var (
	binPath  = new(string)
	port     = func() *int { p := 7979; return &p }()
	appPath  = new(string)
	bundleID = func() *string { s := "ai.storyteller.figcraft"; return &s }()
	logPath  = new(string)
)

type msg struct {
	JSONRPC string           `json:"jsonrpc,omitempty"`
	ID      *json.RawMessage `json:"id,omitempty"`
	Method  string           `json:"method,omitempty"`
	Params  json.RawMessage  `json:"params,omitempty"`
	Result  json.RawMessage  `json:"result,omitempty"`
	Error   json.RawMessage  `json:"error,omitempty"`
}

type backend struct {
	attached bool
	cmd      *exec.Cmd
	in       io.WriteCloser
	out      chan []byte // closed when the process's stdout ends
}

var (
	outMu     sync.Mutex
	stdout    = bufio.NewWriterSize(os.Stdout, 1<<16)
	initParam json.RawMessage
	cur       *backend
	idSeq     int
	connErrRe = regexp.MustCompile(`(?i)not connected to the app|control channel closed|can't reach the figcraft app|is not reachable|connection refused|broken pipe|connection reset|lost the connection`)
)

func send(line []byte) {
	outMu.Lock()
	stdout.Write(line)
	stdout.WriteByte('\n')
	stdout.Flush()
	outMu.Unlock()
}

func startBackend(attached bool) (*backend, error) {
	args := []string{"mcp"}
	if attached {
		args = append(args, "--attach", fmt.Sprint(*port))
	}
	cmd := exec.Command(*binPath, args...)
	cmd.Stderr = log.Writer()
	in, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	pr, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	b := &backend{attached: attached, cmd: cmd, in: in, out: make(chan []byte, 64)}
	go func() {
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 1<<20), 1<<30)
		for sc.Scan() {
			line := append([]byte(nil), sc.Bytes()...)
			b.out <- line
		}
		close(b.out)
		cmd.Wait()
	}()
	// handshake
	p := initParam
	if p == nil {
		p = json.RawMessage(`{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"figcraft-mcp-proxy","version":"1"}}`)
	}
	idSeq++
	id := json.RawMessage(fmt.Sprintf(`"__proxy_init_%d"`, idSeq))
	if _, err := b.call(&msg{JSONRPC: "2.0", ID: &id, Method: "initialize", Params: p}, 20*time.Second); err != nil {
		b.kill()
		return nil, err
	}
	b.write([]byte(`{"jsonrpc":"2.0","method":"notifications/initialized"}`))
	log.Printf("backend started (attached=%v pid=%d)", attached, cmd.Process.Pid)
	return b, nil
}

func (b *backend) write(line []byte) error {
	if _, err := b.in.Write(append(line, '\n')); err != nil {
		return err
	}
	return nil
}

func (b *backend) kill() {
	if b == nil || b.cmd.Process == nil {
		return
	}
	b.in.Close()
	b.cmd.Process.Kill()
}

// call sends a request and waits for the response with the same id, forwarding anything
// else the backend emits (notifications, server requests) to the client.
func (b *backend) call(m *msg, timeout time.Duration) (*msg, error) {
	line, _ := json.Marshal(m)
	if err := b.write(line); err != nil {
		return nil, err
	}
	want := string(*m.ID)
	var tch <-chan time.Time
	if timeout > 0 {
		tch = time.After(timeout)
	}
	for {
		select {
		case l, ok := <-b.out:
			if !ok {
				return nil, errors.New("backend exited")
			}
			var r msg
			if json.Unmarshal(l, &r) == nil && r.ID != nil && r.Method == "" && string(*r.ID) == want {
				return &r, nil
			}
			if !strings.Contains(string(l), "__proxy_init_") {
				send(l)
			}
		case <-tch:
			return nil, errors.New("timeout")
		}
	}
}

func portOpen() bool {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", *port), 400*time.Millisecond)
	if err != nil {
		return false
	}
	c.Close()
	return true
}

func ensureApp() error {
	if portOpen() {
		return nil
	}
	if appRunning() {
		log.Printf("FigCraft running without control channel: asking it to quit")
		quitApp()
		deadline := time.Now().Add(60 * time.Second)
		for appRunning() && time.Now().Before(deadline) {
			time.Sleep(300 * time.Millisecond)
		}
		if appRunning() {
			return errors.New("o FigCraft está aberto sem o canal de controle e não fechou (há algum diálogo de salvar aberto?). Feche o FigCraft e tente de novo")
		}
	}
	log.Printf("launching FigCraft (%s) with --control %d", *appPath, *port)
	if err := launchApp(); err != nil {
		return fmt.Errorf("não consegui abrir o FigCraft: %v", err)
	}
	deadline := time.Now().Add(45 * time.Second)
	for time.Now().Before(deadline) {
		if portOpen() {
			time.Sleep(300 * time.Millisecond)
			return nil
		}
		time.Sleep(250 * time.Millisecond)
	}
	return errors.New("o FigCraft abriu mas o canal de controle não respondeu")
}

func attach() error {
	if cur != nil && cur.attached {
		return nil
	}
	if err := ensureApp(); err != nil {
		return err
	}
	b, err := startBackend(true)
	if err != nil {
		return err
	}
	if cur != nil {
		cur.kill()
	}
	cur = b
	return nil
}

func reconnect() error {
	if cur != nil {
		cur.kill()
		cur = nil
	}
	return attach()
}

func needsApp(method string) bool {
	switch method {
	case "initialize", "ping", "tools/list", "prompts/list", "prompts/get",
		"resources/list", "resources/templates/list", "logging/setLevel", "completion/complete":
		return false
	}
	return true
}

func isConnError(r *msg) bool {
	if r == nil {
		return false
	}
	if len(r.Error) > 0 && connErrRe.Match(r.Error) {
		return true
	}
	if len(r.Result) > 0 && strings.Contains(string(r.Result), `"isError":true`) && connErrRe.Match(r.Result) {
		return true
	}
	return false
}

func errorReply(id *json.RawMessage, text string) {
	b, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": id,
		"result": map[string]any{"isError": true, "content": []map[string]string{{"type": "text", "text": text}}},
	})
	send(b)
}

func handle(m *msg, raw []byte) {
	if m.ID == nil || m.Method == "" { // notification or response from client
		if cur != nil {
			cur.write(raw)
		}
		return
	}
	if m.Method == "initialize" {
		initParam = m.Params
	}
	if needsApp(m.Method) {
		if err := attach(); err != nil {
			log.Printf("attach failed: %v", err)
			if m.Method == "tools/call" {
				errorReply(m.ID, "FigCraft: "+err.Error())
			} else {
				b, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": m.ID, "error": map[string]any{"code": -32000, "message": err.Error()}})
				send(b)
			}
			return
		}
	} else if cur == nil && portOpen() && attach() == nil {
		// app already listening: attach right away, no headless detour
	} else if cur == nil {
		b, err := startBackend(false)
		if err != nil {
			b2, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": m.ID, "error": map[string]any{"code": -32000, "message": err.Error()}})
			send(b2)
			return
		}
		cur = b
	}
	for attempt := 0; attempt < 2; attempt++ {
		r, err := cur.call(m, 0)
		if err == nil && !(cur.attached && isConnError(r)) {
			out, _ := json.Marshal(r)
			send(out)
			return
		}
		log.Printf("call %s failed (attempt %d): err=%v connErr=%v", m.Method, attempt+1, err, isConnError(r))
		if attempt == 0 {
			if rerr := reconnect(); rerr != nil {
				errorReply(m.ID, "FigCraft: "+rerr.Error())
				return
			}
			continue
		}
		if r != nil {
			out, _ := json.Marshal(r)
			send(out)
		} else {
			errorReply(m.ID, "FigCraft: a conexão com o app caiu ("+err.Error()+")")
		}
	}
}

func main() {
	args := os.Args[1:]
	self, _ := os.Executable()
	if r, err := filepath.EvalSymlinks(self); err == nil {
		self = r
	}
	dir := filepath.Dir(self)
	*binPath = envOr("FIGCRAFT_CLI_BIN", realCLI(dir, self))
	*appPath = envOr("FIGCRAFT_APP", defaultApp(dir))
	*logPath = envOr("FIGCRAFT_PROXY_LOG", filepath.Join(dir, "figcraft-mcp.log"))

	// Anything other than `mcp ...` goes straight to the real CLI (info, export, render, --version...).
	if len(args) == 0 || args[0] != "mcp" {
		cmd := exec.Command(*binPath, args...)
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			if ee, ok := err.(*exec.ExitError); ok {
				os.Exit(ee.ExitCode())
			}
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	for i := 0; i+1 < len(args); i++ {
		if args[i] == "--attach" {
			p := args[i+1]
			if j := strings.LastIndex(p, ":"); j >= 0 {
				p = p[j+1:]
			}
			fmt.Sscan(p, port)
		}
	}
	if st, err := os.Stat(*logPath); err == nil && st.Size() > 1<<20 {
		os.Remove(*logPath)
	}
	if f, err := os.OpenFile(*logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
		log.SetOutput(f)
	}
	log.Printf("proxy start (bin=%s port=%d)", *binPath, *port)

	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 1<<20), 1<<30)
	for sc.Scan() {
		raw := append([]byte(nil), sc.Bytes()...)
		if len(strings.TrimSpace(string(raw))) == 0 {
			continue
		}
		var m msg
		if err := json.Unmarshal(raw, &m); err != nil {
			log.Printf("bad json from client: %v", err)
			continue
		}
		handle(&m, raw)
	}
	if cur != nil {
		cur.kill()
	}
	log.Printf("proxy exit")
}

// realCLI is the official figcraft-cli next to this proxy: figcraft-cli-bin (macOS, where the
// proxy itself is installed as figcraft-cli) or figcraft-cli.exe (Windows, proxy = figcraft-mcp.exe).
func realCLI(dir, self string) string {
	for _, n := range []string{"figcraft-cli-bin", "figcraft-cli-bin.exe", "figcraft-cli.exe", "figcraft-cli"} {
		p := filepath.Join(dir, n)
		if st, err := os.Stat(p); err == nil && !st.IsDir() && !sameFile(p, self) {
			return p
		}
	}
	return filepath.Join(dir, "figcraft-cli-bin")
}

func sameFile(a, b string) bool {
	sa, err1 := os.Stat(a)
	sb, err2 := os.Stat(b)
	return err1 == nil && err2 == nil && os.SameFile(sa, sb)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
