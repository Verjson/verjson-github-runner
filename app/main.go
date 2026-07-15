// Command gha is a small TUI/CLI to manage Dockerized GitHub Actions self-hosted runners:
// pick an org/repo, choose how many runners of each language kind, fetch tokens via the
// GitHub CLI automatically, build the images, launch the containers, and watch them live.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"

	"github.com/Verjson/github-runner-docker-compose/app/internal/dashboard"
	"github.com/Verjson/github-runner-docker-compose/app/internal/dockerx"
	"github.com/Verjson/github-runner-docker-compose/app/internal/ghc"
	"github.com/Verjson/github-runner-docker-compose/app/internal/netcheck"
	"github.com/Verjson/github-runner-docker-compose/app/internal/wizard"
)

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7D56F4"))
	okStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575"))
	errStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F87")).Bold(true)
	dimStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
)

func main() {
	cmd := ""
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}

	switch cmd {
	case "help", "-h", "--help":
		usage()
	case "up":
		if err := upFlow(); err != nil {
			fatal(err)
		}
	case "netcheck", "net":
		netcheck.Print()
	case "doctor":
		if err := doctor(); err != nil {
			fatal(err)
		}
	case "list", "ls":
		if err := ensureRepoRoot(); err != nil {
			fatal(err)
		}
		listRunners()
	case "dashboard", "dash", "monitor", "top":
		if err := ensureRepoRoot(); err != nil {
			fatal(err)
		}
		if err := dashboard.Run(); err != nil {
			fatal(err)
		}
	case "add", "":
		if err := runAdd(); err != nil {
			fatal(err)
		}
		if cmd == "" {
			// interactive default flow already handled the menu
		}
	default:
		fmt.Println(errStyle.Render("unknown command: " + cmd))
		usage()
		os.Exit(2)
	}
}

// runAdd is the default flow: preflight the environment, then either drop into the
// top-level menu (no subcommand) or go straight to the add wizard (`gha add`).
func runAdd() error {
	if err := ensureRepoRoot(); err != nil {
		return err
	}
	login, token, err := preflight()
	if err != nil {
		return err
	}
	if len(os.Args) > 1 && os.Args[1] == "add" {
		return wizard.Run(login, token)
	}
	return menu(login, token)
}

// upFlow is the one-command path: docker check → gh login (if needed) → network
// preflight → add-runners wizard (target, kinds, counts, proxy). Everything in one go.
func upFlow() error {
	if err := ensureRepoRoot(); err != nil {
		return err
	}
	if err := dockerx.EnsureReady(); err != nil {
		return err
	}

	// 1. Ensure gh is installed and authenticated, logging in interactively if needed.
	login, err := ghc.EnsureReady()
	if err != nil {
		if errors.Is(err, ghc.ErrNotInstalled) {
			return errors.New("GitHub CLI (gh) is not installed.\n  Install it: https://cli.github.com  then re-run: gha up")
		}
		if !errors.Is(err, ghc.ErrNotAuthed) {
			return err
		}
		fmt.Println(titleStyle.Render("GitHub login"))
		fmt.Println(dimStyle.Render("  You're not logged in — launching `gh auth login`…"))
		fmt.Println()
		if err := ghc.Login(); err != nil {
			return fmt.Errorf("gh auth login did not complete: %w", err)
		}
		if login, err = ghc.EnsureReady(); err != nil {
			return err
		}
	}
	fmt.Println(okStyle.Render("✓ ") + "signed in as " + login)
	fmt.Println()

	// 2. Network preflight — confirm outbound 443 to GitHub is open.
	if !netcheck.Print() {
		fmt.Println()
		proceed := false
		if err := huh.NewForm(huh.NewGroup(
			huh.NewConfirm().Title("Outbound checks failed. Continue anyway?").
				Description("Runners won't connect until 443 to GitHub is reachable.").Value(&proceed),
		)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
			return err
		}
		if !proceed {
			return nil
		}
	}
	fmt.Println()

	// 3. Straight into the add-runners wizard.
	token, err := ghc.Token()
	if err != nil {
		return err
	}
	return wizard.Run(login, token)
}

// menu is the top-level interactive chooser shown when `gha` is run with no subcommand.
func menu(login, token string) error {
	for {
		runners, _ := dockerx.List()
		choice := "add"
		if err := huh.NewForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("GitHub Runner Manager").
				Description(fmt.Sprintf("signed in as %s · %d runner(s) running", login, len(runners))).
				Options(
					huh.NewOption("➕  Add runners", "add"),
					huh.NewOption("📊  Open live dashboard", "dash"),
					huh.NewOption("📋  List runners", "list"),
					huh.NewOption("🌐  Network check (outbound 443)", "net"),
					huh.NewOption("🚪  Quit", "quit"),
				).Value(&choice),
		)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
			return err
		}
		switch choice {
		case "add":
			if err := wizard.Run(login, token); err != nil {
				fmt.Println(errStyle.Render(err.Error()))
			}
		case "dash":
			if err := dashboard.Run(); err != nil {
				return err
			}
		case "list":
			listRunners()
		case "net":
			netcheck.Print()
		case "quit":
			return nil
		}
	}
}

// preflight checks docker + gh and returns the gh login and OAuth token.
func preflight() (login, token string, err error) {
	if err := dockerx.EnsureReady(); err != nil {
		return "", "", err
	}
	login, err = ghc.EnsureReady()
	if err != nil {
		if errors.Is(err, ghc.ErrNotInstalled) {
			return "", "", errors.New("GitHub CLI (gh) is not installed.\n  Install it: https://cli.github.com  then run: gh auth login")
		}
		if errors.Is(err, ghc.ErrNotAuthed) {
			return "", "", errors.New("You're not logged in to gh.\n  Run: gh auth login")
		}
		return "", "", err
	}
	token, err = ghc.Token()
	if err != nil {
		return "", "", err
	}
	return login, token, nil
}

func doctor() error {
	fmt.Println(titleStyle.Render("Environment check"))
	check("docker", dockerx.EnsureReady())
	_, ghErr := ghc.EnsureReady()
	check("gh installed + authenticated", ghErr)
	if ghErr == nil {
		login, _ := ghc.CurrentLogin()
		fmt.Println(dimStyle.Render("  gh user: " + login))
	}
	if err := ensureRepoRoot(); err != nil {
		check("repo layout (images/)", err)
	} else {
		wd, _ := os.Getwd()
		check("repo layout (images/)", nil)
		fmt.Println(dimStyle.Render("  repo root: " + wd))
	}
	return nil
}

func check(name string, err error) {
	if err != nil {
		fmt.Printf("  %s %s\n", errStyle.Render("✗"), name)
		fmt.Println(dimStyle.Render("    " + err.Error()))
	} else {
		fmt.Printf("  %s %s\n", okStyle.Render("✓"), name)
	}
}

func listRunners() {
	runners, err := dockerx.Snapshot()
	if err != nil {
		fatal(err)
	}
	if len(runners) == 0 {
		fmt.Println(dimStyle.Render("No managed runners. Run `gha add` to create some."))
		return
	}
	fmt.Printf("%-16s %-8s %-12s %-8s %-16s %s\n", "NAME", "KIND", "STATE", "CPU", "MEM", "JOB")
	for _, r := range runners {
		fmt.Printf("%-16s %-8s %-12s %-8s %-16s %s\n", r.Name, r.Kind, r.State, r.CPU, r.Mem, r.Job)
	}
}

// ensureRepoRoot chdirs to the directory containing images/base.Dockerfile so that
// `docker build -f images/... .` resolves correctly regardless of where gha is invoked.
func ensureRepoRoot() error {
	candidates := []string{}
	if wd, err := os.Getwd(); err == nil {
		candidates = append(candidates, wd)
	}
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Dir(exe))
	}
	for _, start := range candidates {
		dir := start
		for {
			if _, err := os.Stat(filepath.Join(dir, "images", "base.Dockerfile")); err == nil {
				return os.Chdir(dir)
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return errors.New("could not locate the repo root (images/base.Dockerfile). Run gha from inside the github-runner checkout")
}

func usage() {
	fmt.Println(titleStyle.Render("gha — GitHub self-hosted runner manager"))
	fmt.Println(`
Usage:
  gha up           One command: gh login (if needed) → network check → add runners
  gha              Interactive menu (add runners / dashboard / list / net check)
  gha add          Add runners: pick target, kinds, and counts
  gha dashboard    btop-style live monitor (aliases: dash, top, monitor)
  gha list         Print a one-shot table of runners (alias: ls)
  gha netcheck     Test outbound 443 to GitHub (alias: net)
  gha doctor       Check docker + gh are ready
  gha help         This help

Auth is taken from your GitHub CLI session (gh auth login). No PAT to paste.`)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, errStyle.Render("error: ")+err.Error())
	os.Exit(1)
}
