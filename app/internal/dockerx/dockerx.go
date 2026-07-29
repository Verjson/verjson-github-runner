// Package dockerx wraps the docker CLI for building runner images and managing the
// gha-* runner containers (run / list / stats / logs / remove).
package dockerx

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Prefix is prepended to every managed container name so they're easy to find.
const Prefix = "gha-"

// ErrNotInstalled is returned when the docker binary is missing.
var ErrNotInstalled = errors.New("docker is not installed or not on PATH")

// EnsureReady checks docker is installed and the daemon is reachable.
func EnsureReady() error {
	if _, err := exec.LookPath("docker"); err != nil {
		return ErrNotInstalled
	}
	if err := exec.Command("docker", "info").Run(); err != nil {
		return errors.New("cannot talk to the docker daemon (is it running / do you have permission?)")
	}
	return nil
}

// Build builds an image from a Dockerfile. It streams output to the given writer so the
// wizard can show progress. baseImage, when non-empty, is passed as the BASE_IMAGE build-arg.
func Build(dockerfile, tag, baseImage string, out *os.File) error {
	args := []string{"build", "-f", dockerfile, "-t", tag}
	if baseImage != "" {
		args = append(args, "--build-arg", "BASE_IMAGE="+baseImage)
	}
	args = append(args, ".")
	cmd := exec.Command("docker", args...)
	cmd.Stdout = out
	cmd.Stderr = out
	return cmd.Run()
}

// RunSpec describes one runner container to launch.
type RunSpec struct {
	Name      string // logical runner name; container becomes gha-<Name>
	Image     string // image tag to run
	URL       string // GITHUB_URL
	Token     string // gh OAuth token, delivered through a one-use host FIFO
	Labels    string // comma-separated
	Group     string // runner group (org only)
	Workdir   string // _work by default
	Ephemeral bool
	MountSock bool   // mount the host docker socket (dangerous; opt-in)
	Proxy     string // optional HTTP(S) proxy URL for locked-down networks
	NoProxy   string // optional comma-separated no-proxy hosts
}

// Container is the container name for a spec.
func (s RunSpec) Container() string { return Prefix + s.Name }

// Run (re)creates and starts a runner container detached, returning the container id.
func Run(s RunSpec) (string, error) {
	_ = exec.Command("docker", "rm", "-f", s.Container()).Run() // replace if it exists

	transportDir, err := os.MkdirTemp("", "gha-pat-*")
	if err != nil {
		return "", fmt.Errorf("create PAT transport: %w", err)
	}
	defer os.RemoveAll(transportDir)
	if err := os.Chmod(transportDir, 0700); err != nil {
		return "", fmt.Errorf("secure PAT transport: %w", err)
	}
	fifo := filepath.Join(transportDir, "github-pat")
	if err := makePATFIFO(fifo); err != nil {
		return "", err
	}
	args := runArgsWithFIFO(s, transportDir)

	out, err := exec.Command("docker", args...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("docker run %s: %w: %s", s.Container(), err, strings.TrimSpace(string(out)))
	}
	if err := deliverPAT(fifo, s.Token); err != nil {
		_ = exec.Command("docker", "rm", "-f", s.Container()).Run()
		return "", fmt.Errorf("deliver PAT to %s: %w", s.Container(), err)
	}
	return strings.TrimSpace(string(out)), nil
}

func runArgs(s RunSpec) []string {
	return runArgsWithFIFO(s, "/tmp/gha-pat")
}

func runArgsWithFIFO(s RunSpec, transportDir string) []string {
	args := []string{
		"run", "-d",
		"--name", s.Container(),
		"--restart", "no",
		"--label", "gha.managed=true",
		"--label", "gha.kind=" + kindFromImage(s.Image),
		"-e", "GITHUB_URL=" + s.URL,
		"--mount", "type=bind,src=" + transportDir + ",dst=/run/gha-secrets",
		"-e", "GITHUB_PAT_FIFO=/run/gha-secrets/github-pat",
		"-e", "RUNNER_NAME=" + s.Name,
		"-e", "RUNNER_LABELS=" + s.Labels,
		"-e", "RUNNER_GROUP=" + s.Group,
		"-e", "RUNNER_WORKDIR=" + s.Workdir,
	}
	if s.Ephemeral {
		// The long-lived container is a credential-holding host controller only;
		// workflow code executes in a new --rm child container for every job.
		// Root + the Docker socket are confined to this supervisor. The child
		// receives the socket only when MountSock is explicitly selected.
		args = append(args,
			"--user", "0:0",
			"--label", "gha.mode=ephemeral-supervisor",
			"-v", "/var/run/docker.sock:/var/run/docker.sock",
			"-e", "RUNNER_EPHEMERAL=1",
			"-e", "RUNNER_IMAGE="+s.Image,
		)
		if s.MountSock {
			args = append(args, "-e", "RUNNER_CHILD_MOUNT_SOCK=1")
		}
	}
	if s.Proxy != "" {
		// Set both upper- and lower-case variants; the runner, git, and curl differ on which they read.
		for _, k := range []string{"HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"} {
			args = append(args, "-e", k+"="+s.Proxy)
		}
	}
	if s.NoProxy != "" {
		args = append(args, "-e", "NO_PROXY="+s.NoProxy, "-e", "no_proxy="+s.NoProxy)
	}
	if s.MountSock && !s.Ephemeral {
		args = append(args, "-v", "/var/run/docker.sock:/var/run/docker.sock")
	}
	args = append(args, s.Image)
	if s.Ephemeral {
		args = append(args, "supervise")
	}
	return args
}

func makePATFIFO(path string) error {
	if err := syscall.Mkfifo(path, 0600); err != nil {
		return fmt.Errorf("create PAT FIFO: %w", err)
	}
	return nil
}

func deliverPAT(path, token string) error {
	deadline := time.Now().Add(10 * time.Second)
	for {
		fd, err := syscall.Open(path, syscall.O_WRONLY|syscall.O_NONBLOCK, 0)
		if err == nil {
			file := os.NewFile(uintptr(fd), path)
			_, writeErr := fmt.Fprintln(file, token)
			closeErr := file.Close()
			if writeErr != nil {
				return writeErr
			}
			return closeErr
		}
		if !errors.Is(err, syscall.ENXIO) || time.Now().After(deadline) {
			return err
		}
		time.Sleep(25 * time.Millisecond)
	}
}

// Runner is one managed container's live snapshot.
type Runner struct {
	Name   string // logical name (container without the gha- prefix)
	Kind   string // gha.kind label
	State  string // running / exited / restarting ...
	Status string // docker's human status string, e.g. "Up 3 minutes"
	CPU    string // from docker stats, e.g. "0.15%"
	Mem    string // from docker stats, e.g. "80MiB / 15GiB"
	Job    string // parsed from recent logs: Idle / Running job / Registering ...
}

// List returns all managed runner containers (running or not).
func List() ([]Runner, error) {
	out, err := exec.Command("docker", "ps", "-a",
		"--filter", "label=gha.managed=true",
		"--format", "{{.Names}}\t{{.State}}\t{{.Status}}\t{{.Label \"gha.kind\"}}").Output()
	if err != nil {
		return nil, err
	}
	var runners []Runner
	sc := bufio.NewScanner(strings.NewReader(string(out)))
	for sc.Scan() {
		f := strings.Split(sc.Text(), "\t")
		if len(f) < 4 {
			continue
		}
		runners = append(runners, Runner{
			Name:   strings.TrimPrefix(f[0], Prefix),
			State:  f[1],
			Status: f[2],
			Kind:   f[3],
		})
	}
	return runners, nil
}

// stat holds one row of `docker stats` output.
type stat struct{ CPU, Mem string }

// Stats returns a map keyed by container name of CPU/mem usage (single snapshot).
func Stats() (map[string]stat, error) {
	out, err := exec.Command("docker", "stats", "--no-stream",
		"--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}").Output()
	if err != nil {
		return nil, err
	}
	m := map[string]stat{}
	sc := bufio.NewScanner(strings.NewReader(string(out)))
	for sc.Scan() {
		f := strings.Split(sc.Text(), "\t")
		if len(f) < 3 {
			continue
		}
		m[f[0]] = stat{CPU: f[1], Mem: f[2]}
	}
	return m, nil
}

// Snapshot combines List + Stats + log parsing into a single enriched slice.
func Snapshot() ([]Runner, error) {
	runners, err := List()
	if err != nil {
		return nil, err
	}
	stats, _ := Stats() // best-effort; stats only exist for running containers
	for i := range runners {
		c := Prefix + runners[i].Name
		if s, ok := stats[c]; ok {
			runners[i].CPU, runners[i].Mem = s.CPU, s.Mem
		}
		runners[i].Job = parseJob(runners[i].State, tailLogs(c, 40))
	}
	return runners, nil
}

// tailLogs returns the last n lines of a container's logs (best-effort).
func tailLogs(container string, n int) string {
	out, _ := exec.Command("docker", "logs", "--tail", fmt.Sprint(n), container).CombinedOutput()
	return string(out)
}

// Logs returns the last n lines for display.
func Logs(name string, n int) string { return tailLogs(Prefix+name, n) }

// parseJob derives a friendly job/status string from recent log lines.
func parseJob(state, logs string) string {
	if state != "running" {
		return strings.Title(state)
	}
	lines := strings.Split(strings.TrimRight(logs, "\n"), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		l := lines[i]
		switch {
		case strings.Contains(l, "Running job:"):
			if idx := strings.Index(l, "Running job:"); idx >= 0 {
				return "▶ " + strings.TrimSpace(l[idx+len("Running job:"):])
			}
		case strings.Contains(l, "Job") && strings.Contains(l, "completed with result"):
			return "Idle"
		case strings.Contains(l, "Listening for Jobs"):
			return "Idle"
		case strings.Contains(l, "Runner reconnect") || strings.Contains(l, "Runner connect"):
			return "Idle"
		case strings.Contains(l, "Authentication") || strings.Contains(l, "Registering"):
			return "Registering…"
		}
	}
	return "Starting…"
}

// Remove force-removes a runner container (the container's SIGTERM trap de-registers it).
func Remove(name string) error {
	return exec.Command("docker", "rm", "-f", Prefix+name).Run()
}

// Restart is intentionally unavailable for one-use PAT transports. Relaunching creates
// a fresh FIFO and preserves the renewable-credential lifecycle.
func Restart(name string) error {
	return errors.New("runner restart requires relaunch through gha so a fresh PAT transport can be created")
}

// kindFromImage extracts the tag suffix (rust/node/...) from gha-runner:<kind>.
func kindFromImage(image string) string {
	if i := strings.LastIndex(image, ":"); i >= 0 {
		return image[i+1:]
	}
	return image
}
