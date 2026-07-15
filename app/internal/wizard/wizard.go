// Package wizard drives the interactive "add runners" flow with Huh forms:
// pick a target (org/repo), choose which language kinds to add and HOW MANY of each,
// set labels/group/options, confirm, then build images and launch the containers.
package wizard

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"

	"github.com/Verjson/github-runner-docker-compose/app/internal/dockerx"
	"github.com/Verjson/github-runner-docker-compose/app/internal/ghc"
	"github.com/Verjson/github-runner-docker-compose/app/internal/kinds"
)

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7D56F4"))
	okStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575"))
	dimStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	errStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F87")).Bold(true)
)

// Plan is the fully-resolved set of runners to create.
type Plan struct {
	Target    ghc.Target
	Token     string
	Group     string
	Workdir   string
	Ephemeral bool
	MountSock bool
	Proxy     string
	NoProxy   string
	Specs     []dockerx.RunSpec
}

// Run executes the wizard end-to-end. login is the authenticated gh user (for display).
func Run(login, token string) error {
	fmt.Println(titleStyle.Render("＋ Add self-hosted runners"))
	fmt.Println(dimStyle.Render("   signed in as " + login))
	fmt.Println()

	target, err := chooseTarget()
	if err != nil {
		return err
	}

	fmt.Print(dimStyle.Render("Checking your access to " + target.Slug() + "… "))
	if err := ghc.Preflight(target); err != nil {
		fmt.Println(errStyle.Render("no"))
		return handleScope(target, err)
	}
	fmt.Println(okStyle.Render("ok"))

	counts, err := chooseCounts()
	if err != nil {
		return err
	}

	group := "Default"
	workdir := "_work"
	proxy := firstEnv("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")
	noProxy := firstEnv("NO_PROXY", "no_proxy")
	var ephemeral, mountSock bool
	opts := huh.NewForm(huh.NewGroup(
		huh.NewInput().Title("Runner group").Description("Org runners only; leave 'Default' for repos.").Value(&group),
		huh.NewInput().Title("Work folder").Value(&workdir),
		huh.NewConfirm().Title("Ephemeral runners?").Description("Each handles one job then re-registers.").Value(&ephemeral),
		huh.NewConfirm().Title("Mount host docker socket?").Description("Lets CI use Docker, but grants host-root. Trusted repos only.").Value(&mountSock),
		huh.NewInput().Title("HTTPS proxy (optional)").
			Description("For locked-down networks. Leave blank if outbound 443 is open.").
			Placeholder("http://proxy.internal:3128").Value(&proxy),
		huh.NewInput().Title("No-proxy hosts (optional)").
			Description("Comma-separated hosts that bypass the proxy.").Value(&noProxy),
	)).WithTheme(huh.ThemeCharm())
	if err := opts.Run(); err != nil {
		return err
	}

	plan := buildPlan(target, token, group, workdir, ephemeral, mountSock, proxy, noProxy, counts)
	printSummary(plan)

	confirm := true
	if err := huh.NewForm(huh.NewGroup(
		huh.NewConfirm().Title(fmt.Sprintf("Build & launch %d runner(s)?", len(plan.Specs))).Value(&confirm),
	)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
		return err
	}
	if !confirm {
		fmt.Println(dimStyle.Render("Cancelled."))
		return nil
	}

	return apply(plan)
}

// chooseTarget lets the user pick a repo/org from a list or type one in.
func chooseTarget() (ghc.Target, error) {
	const (
		modeRepo = "repo"
		modeOrg  = "org"
		modeType = "type"
	)
	mode := modeRepo
	if err := huh.NewForm(huh.NewGroup(
		huh.NewSelect[string]().
			Title("Where should these runners register?").
			Options(
				huh.NewOption("A repository I administer", modeRepo),
				huh.NewOption("An organization", modeOrg),
				huh.NewOption("Type owner/repo or org myself", modeType),
			).Value(&mode),
	)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
		return ghc.Target{}, err
	}

	switch mode {
	case modeRepo:
		fmt.Print(dimStyle.Render("Loading repos you can administer… "))
		repos, err := ghc.ListRepos(200)
		fmt.Println()
		if err != nil || len(repos) == 0 {
			fmt.Println(dimStyle.Render("(none found — enter one manually)"))
			return typeTarget()
		}
		sort.Strings(repos)
		var pick string
		if err := huh.NewForm(huh.NewGroup(
			huh.NewSelect[string]().Title("Repository").Height(12).
				Options(huh.NewOptions(repos...)...).Value(&pick),
		)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
			return ghc.Target{}, err
		}
		return ghc.ParseTarget(pick)
	case modeOrg:
		fmt.Print(dimStyle.Render("Loading your organizations… "))
		orgs, err := ghc.ListOrgs()
		fmt.Println()
		if err != nil || len(orgs) == 0 {
			fmt.Println(dimStyle.Render("(none found — enter one manually)"))
			return typeTarget()
		}
		var pick string
		if err := huh.NewForm(huh.NewGroup(
			huh.NewSelect[string]().Title("Organization").Height(12).
				Options(huh.NewOptions(orgs...)...).Value(&pick),
		)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
			return ghc.Target{}, err
		}
		return ghc.Target{IsOrg: true, Owner: pick}, nil
	default:
		return typeTarget()
	}
}

func typeTarget() (ghc.Target, error) {
	var raw string
	if err := huh.NewForm(huh.NewGroup(
		huh.NewInput().Title("Target").
			Placeholder("owner/repo   or   my-org   or   https://github.com/...").
			Validate(func(s string) error { _, err := ghc.ParseTarget(s); return err }).
			Value(&raw),
	)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
		return ghc.Target{}, err
	}
	return ghc.ParseTarget(raw)
}

// kindCount is how many runners the user wants for one language kind.
type kindCount struct {
	Kind  kinds.Kind
	Count int
}

// chooseCounts asks which languages to add, then how many of each — the core "nice interface".
func chooseCounts() ([]kindCount, error) {
	// Step 1: multi-select the languages.
	var picked []string
	opts := make([]huh.Option[string], 0, len(kinds.All))
	for _, k := range kinds.All {
		opts = append(opts, huh.NewOption(fmt.Sprintf("%-7s — %s", k.Name, k.Blurb), k.ID))
	}
	if err := huh.NewForm(huh.NewGroup(
		huh.NewMultiSelect[string]().
			Title("Which kinds of runners do you want?").
			Description("Space to toggle, enter to continue. Each kind is a preloaded toolchain image.").
			Options(opts...).
			Validate(func(v []string) error {
				if len(v) == 0 {
					return fmt.Errorf("pick at least one kind")
				}
				return nil
			}).
			Value(&picked),
	)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
		return nil, err
	}

	// Step 2: one count field per picked kind, all on a single screen.
	countStrs := make(map[string]*string, len(picked))
	fields := make([]huh.Field, 0, len(picked))
	for _, id := range picked {
		k, _ := kinds.ByID(id)
		s := "1"
		countStrs[id] = &s
		fields = append(fields, huh.NewInput().
			Title("How many "+k.Name+" runners?").
			Value(countStrs[id]).
			Validate(validPositiveInt))
	}
	if err := huh.NewForm(huh.NewGroup(fields...)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
		return nil, err
	}

	var result []kindCount
	for _, id := range picked {
		k, _ := kinds.ByID(id)
		n, _ := strconv.Atoi(strings.TrimSpace(*countStrs[id]))
		if n > 0 {
			result = append(result, kindCount{Kind: k, Count: n})
		}
	}
	return result, nil
}

func validPositiveInt(s string) error {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n < 0 {
		return fmt.Errorf("enter a number ≥ 0")
	}
	if n > 50 {
		return fmt.Errorf("that's a lot — cap is 50 per kind")
	}
	return nil
}

// buildPlan expands per-kind counts into concrete container specs with unique names.
func buildPlan(t ghc.Target, token, group, workdir string, ephemeral, mountSock bool, proxy, noProxy string, counts []kindCount) Plan {
	p := Plan{Target: t, Token: token, Group: group, Workdir: workdir, Ephemeral: ephemeral, MountSock: mountSock, Proxy: proxy, NoProxy: noProxy}
	existing := existingNames()
	for _, kc := range counts {
		labels := strings.Join(kc.Kind.Labels, ",")
		for i := 0; i < kc.Count; i++ {
			name := uniqueName(kc.Kind.ID, existing)
			existing[name] = true
			p.Specs = append(p.Specs, dockerx.RunSpec{
				Name: name, Image: kc.Kind.Image, URL: t.URL(), Token: token,
				Labels: labels, Group: group, Workdir: workdir,
				Ephemeral: ephemeral, MountSock: mountSock,
				Proxy: proxy, NoProxy: noProxy,
			})
		}
	}
	return p
}

// firstEnv returns the first non-empty value among the given env var names.
func firstEnv(keys ...string) string {
	for _, k := range keys {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return ""
}

// uniqueName picks kind-1, kind-2, … skipping names already taken by live containers.
func uniqueName(prefix string, taken map[string]bool) string {
	for i := 1; ; i++ {
		n := fmt.Sprintf("%s-%d", prefix, i)
		if !taken[n] {
			return n
		}
	}
}

func existingNames() map[string]bool {
	m := map[string]bool{}
	if rs, err := dockerx.List(); err == nil {
		for _, r := range rs {
			m[r.Name] = true
		}
	}
	return m
}

func printSummary(p Plan) {
	fmt.Println()
	fmt.Println(titleStyle.Render("Plan"))
	fmt.Printf("  Target    %s  (%s)\n", p.Target.Slug(), targetKind(p.Target))
	if p.Ephemeral {
		fmt.Println("  Mode      ephemeral (one job each)")
	}
	if p.Proxy != "" {
		fmt.Printf("  Proxy     %s\n", p.Proxy)
	}
	byKind := map[string]int{}
	for _, s := range p.Specs {
		byKind[imageKind(s.Image)]++
	}
	var keys []string
	for k := range byKind {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Printf("  %-9s %d runner(s)\n", k, byKind[k])
	}
	fmt.Printf("  %s\n", dimStyle.Render(fmt.Sprintf("%d container(s) total → names %s",
		len(p.Specs), joinNames(p.Specs))))
	fmt.Println()
}

// apply builds each needed image once, then launches every container.
func apply(p Plan) error {
	// Always ensure the base image exists first.
	fmt.Println(titleStyle.Render("Building images"))
	if err := dockerx.Build(kinds.Base.Dockerfile, kinds.Base.Image, "", os.Stdout); err != nil {
		return fmt.Errorf("building base image: %w", err)
	}
	built := map[string]bool{kinds.Base.Image: true}
	for _, s := range p.Specs {
		if built[s.Image] {
			continue
		}
		k, _ := kinds.ByID(imageKind(s.Image))
		fmt.Println(dimStyle.Render("→ " + k.Name))
		if err := dockerx.Build(k.Dockerfile, k.Image, kinds.Base.Image, os.Stdout); err != nil {
			return fmt.Errorf("building %s image: %w", k.Name, err)
		}
		built[s.Image] = true
	}

	fmt.Println()
	fmt.Println(titleStyle.Render("Launching runners"))
	for _, s := range p.Specs {
		if _, err := dockerx.Run(s); err != nil {
			fmt.Println(errStyle.Render("  ✗ " + s.Name + ": " + err.Error()))
			continue
		}
		fmt.Println(okStyle.Render("  ✓ "+s.Container()) + dimStyle.Render("  ["+s.Labels+"]"))
	}
	fmt.Println()
	fmt.Println(okStyle.Render("Done.") + dimStyle.Render("  Open the dashboard to watch them:  gha dashboard"))
	return nil
}

func targetKind(t ghc.Target) string {
	if t.IsOrg {
		return "org"
	}
	return "repo"
}

func imageKind(image string) string {
	if i := strings.LastIndex(image, ":"); i >= 0 {
		return image[i+1:]
	}
	return image
}

func joinNames(specs []dockerx.RunSpec) string {
	var n []string
	for _, s := range specs {
		n = append(n, s.Name)
	}
	return strings.Join(n, ", ")
}

// handleScope offers to run `gh auth refresh` when preflight fails on missing scope.
func handleScope(t ghc.Target, cause error) error {
	fmt.Println(errStyle.Render(cause.Error()))
	scope := "repo"
	if t.IsOrg {
		scope = "admin:org"
	}
	refresh := false
	if err := huh.NewForm(huh.NewGroup(
		huh.NewConfirm().Title("Grant the missing scope now via gh auth refresh -s " + scope + "?").Value(&refresh),
	)).WithTheme(huh.ThemeCharm()).Run(); err != nil {
		return err
	}
	if !refresh {
		return fmt.Errorf("cannot register runners without the %q scope", scope)
	}
	if err := ghc.RefreshScope(scope); err != nil {
		return fmt.Errorf("gh auth refresh failed: %w", err)
	}
	return ghc.Preflight(t)
}
