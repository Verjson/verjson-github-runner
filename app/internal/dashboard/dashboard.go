// Package dashboard is the btop-style live monitor for managed runners. It polls docker
// on an interval and renders a table with per-runner state, CPU/mem, and current job,
// plus keybindings to stop / restart / view logs / quit.
package dashboard

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/Verjson/github-runner-docker-compose/app/internal/dockerx"
)

const refresh = 2 * time.Second

var (
	appTitle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7D56F4"))
	header   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("252")).Background(lipgloss.Color("236"))
	dim      = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	sel      = lipgloss.NewStyle().Foreground(lipgloss.Color("15")).Background(lipgloss.Color("#7D56F4")).Bold(true)
	green    = lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575"))
	yellow   = lipgloss.NewStyle().Foreground(lipgloss.Color("#E5C07B"))
	red      = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F87"))
	box      = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(0, 1)
)

type tickMsg time.Time
type dataMsg []dockerx.Runner

type model struct {
	runners  []dockerx.Runner
	cursor   int
	logs     string // populated when viewing logs
	logsFor  string // runner name the logs belong to
	viewLogs bool
	status   string // transient status line
	width    int
	height   int
}

// Run starts the dashboard event loop (blocks until the user quits).
func Run() error {
	p := tea.NewProgram(model{}, tea.WithAltScreen())
	_, err := p.Run()
	return err
}

func (m model) Init() tea.Cmd {
	return tea.Batch(fetch(), tick())
}

func fetch() tea.Cmd {
	return func() tea.Msg {
		rs, _ := dockerx.Snapshot()
		return dataMsg(rs)
	}
}

func tick() tea.Cmd {
	return tea.Tick(refresh, func(t time.Time) tea.Msg { return tickMsg(t) })
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case dataMsg:
		m.runners = msg
		if m.cursor >= len(m.runners) {
			m.cursor = max(0, len(m.runners)-1)
		}
		if m.viewLogs && m.logsFor != "" {
			m.logs = dockerx.Logs(m.logsFor, 200)
		}
	case tickMsg:
		return m, tea.Batch(fetch(), tick())
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.viewLogs {
		switch msg.String() {
		case "q", "esc", "l":
			m.viewLogs = false
		}
		return m, nil
	}
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.runners)-1 {
			m.cursor++
		}
	case "l", "enter":
		if r, ok := m.current(); ok {
			m.viewLogs = true
			m.logsFor = r.Name
			m.logs = dockerx.Logs(r.Name, 200)
		}
	case "r":
		if r, ok := m.current(); ok {
			m.status = "restarting " + r.Name + "…"
			return m, restart(r.Name)
		}
	case "s", "x", "delete":
		if r, ok := m.current(); ok {
			m.status = "stopping " + r.Name + "…"
			return m, remove(r.Name)
		}
	}
	return m, nil
}

func (m model) current() (dockerx.Runner, bool) {
	if m.cursor >= 0 && m.cursor < len(m.runners) {
		return m.runners[m.cursor], true
	}
	return dockerx.Runner{}, false
}

func restart(name string) tea.Cmd {
	return func() tea.Msg { _ = dockerx.Restart(name); return fetch()() }
}
func remove(name string) tea.Cmd {
	return func() tea.Msg { _ = dockerx.Remove(name); return fetch()() }
}

func (m model) View() string {
	if m.viewLogs {
		return m.logsView()
	}
	var b strings.Builder
	title := appTitle.Render(" ⚙ GitHub Runners ")
	b.WriteString(title + dim.Render(fmt.Sprintf("  %d runner(s) · refresh %s", len(m.runners), refresh)) + "\n\n")

	if len(m.runners) == 0 {
		b.WriteString(dim.Render("  No managed runners yet. Run  gha add  to create some.\n"))
	} else {
		b.WriteString(m.table())
	}

	b.WriteString("\n")
	if m.status != "" {
		b.WriteString(yellow.Render("  "+m.status) + "\n")
	}
	b.WriteString(dim.Render("  ↑/↓ move · l logs · r restart · s stop · q quit"))
	return b.String()
}

func (m model) table() string {
	// Columns: NAME  KIND  STATE  CPU  MEM  JOB.
	// Pad with PLAIN text first (so widths line up), then apply color to the whole row —
	// coloring individual cells would let ANSI escape bytes throw off %-Ns padding.
	row := func(name, kind, state, cpu, mem, job string) string {
		return fmt.Sprintf(" %-16s %-8s %-12s %8s %-16s %s", trunc(name, 16), trunc(kind, 8),
			trunc(state, 12), trunc(cpu, 8), trunc(mem, 16), trunc(job, 30))
	}
	var b strings.Builder
	b.WriteString(header.Render(row("NAME", "KIND", "STATE", "CPU", "MEM", "JOB")) + "\n")
	for i, r := range m.runners {
		plain := row(r.Name, r.Kind, r.State, r.CPU, r.Mem, r.Job)
		switch {
		case i == m.cursor:
			b.WriteString(sel.Render(plain) + "\n")
		default:
			b.WriteString(stateStyle(r.State).Render(plain) + "\n")
		}
	}
	return box.Render(strings.TrimRight(b.String(), "\n"))
}

func (m model) logsView() string {
	var b strings.Builder
	b.WriteString(appTitle.Render(" 📜 logs: "+m.logsFor+" ") + dim.Render("  q/esc back") + "\n\n")
	lines := strings.Split(strings.TrimRight(m.logs, "\n"), "\n")
	// show the last N that fit the screen
	n := m.height - 5
	if n < 5 {
		n = 20
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	b.WriteString(strings.Join(lines, "\n"))
	return b.String()
}

// stateStyle returns the row color for a container state.
func stateStyle(s string) lipgloss.Style {
	switch s {
	case "running":
		return green
	case "restarting", "created", "paused":
		return yellow
	default:
		return red
	}
}

func trunc(s string, n int) string {
	// account for ANSI color codes by measuring the printable width
	if lipgloss.Width(s) <= n {
		return s
	}
	// naive trim for plain strings (colored fields are already short)
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
