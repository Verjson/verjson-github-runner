package dockerx

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDockerRunnerLifecycle(t *testing.T) {
	if testing.Short() {
		t.Skip("Docker lifecycle integration is disabled in short mode")
	}
	if err := exec.Command("docker", "info").Run(); err != nil {
		t.Skipf("Docker daemon is unavailable: %v", err)
	}

	image := fmt.Sprintf("verjson-runner-lifecycle-test:%d", time.Now().UnixNano())
	fixture := filepath.Join("..", "..", "..", "tests", "fixtures", "lifecycle-runner")
	build := exec.Command("docker", "build", "-q", "-t", image, fixture)
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build lifecycle fixture: %v: %s", err, output)
	}
	t.Cleanup(func() {
		_ = exec.Command("docker", "image", "rm", "-f", image).Run()
	})

	t.Run("ephemeral invocations use different clean writable layers", func(t *testing.T) {
		spec := lifecycleSpec("ephemeral-fresh", image, true)
		first := startAndObserve(t, spec)
		waitForLog(t, spec.Container(), "writable-layer marker absent")
		waitForContainerAbsence(t, spec.Container())
		second := startAndObserve(t, spec)
		waitForLog(t, spec.Container(), "writable-layer marker absent")
		waitForContainerAbsence(t, spec.Container())

		if first == second {
			t.Fatalf("ephemeral container identity was reused: %s", first)
		}
	})

	t.Run("ephemeral crash is removed without restart loop", func(t *testing.T) {
		spec := lifecycleSpec("crash-ephemeral", image, true)
		if _, err := Run(spec); err != nil {
			t.Fatalf("start crashing ephemeral fixture: %v", err)
		}
		waitForContainerAbsence(t, spec.Container())
		time.Sleep(500 * time.Millisecond)
		assertContainerAbsent(t, spec.Container())
	})

	t.Run("shutdown removes ephemeral container", func(t *testing.T) {
		spec := lifecycleSpec("shutdown-ephemeral", image, true)
		startAndObserve(t, spec)
		if err := Restart(spec.Name); err == nil || !strings.Contains(err.Error(), "cannot restart ephemeral") {
			t.Fatalf("ephemeral restart must fail closed, got: %v", err)
		}
		if err := Remove(spec.Name); err != nil {
			t.Fatalf("remove ephemeral fixture: %v", err)
		}
		waitForContainerAbsence(t, spec.Container())
	})

	t.Run("persistent mode keeps identity and writable layer across restart", func(t *testing.T) {
		spec := lifecycleSpec("persistent-compatible", image, false)
		first := startAndObserve(t, spec)
		t.Cleanup(func() {
			_ = Remove(spec.Name)
		})

		if err := Restart(spec.Name); err != nil {
			t.Fatalf("restart persistent fixture: %v", err)
		}
		second := inspectField(t, spec.Container(), "{{.Id}}")
		if first != second {
			t.Fatalf("persistent container identity changed: %s != %s", first, second)
		}
		waitForLog(t, spec.Container(), "writable-layer marker persisted")
	})
}

func lifecycleSpec(name, image string, ephemeral bool) RunSpec {
	return RunSpec{
		Name:      name,
		Image:     image,
		URL:       "https://github.com/Verjson/test",
		Token:     "integration-token",
		Labels:    "self-hosted",
		Group:     "test",
		Workdir:   "_work",
		Ephemeral: ephemeral,
	}
}

func startAndObserve(t *testing.T, spec RunSpec) string {
	t.Helper()
	id, err := Run(spec)
	if err != nil {
		t.Fatalf("start %s: %v", spec.Name, err)
	}
	if spec.Ephemeral {
		if got := inspectField(t, spec.Container(), "{{.HostConfig.RestartPolicy.Name}}"); got != "no" {
			t.Fatalf("ephemeral restart policy = %q, want no", got)
		}
		if got := inspectField(t, spec.Container(), "{{.HostConfig.AutoRemove}}"); got != "true" {
			t.Fatalf("ephemeral auto-remove = %q, want true", got)
		}
	}
	return id
}

func inspectField(t *testing.T, container, format string) string {
	t.Helper()
	output, err := exec.Command("docker", "inspect", "--format", format, container).CombinedOutput()
	if err != nil {
		t.Fatalf("inspect %s: %v: %s", container, err, output)
	}
	return strings.TrimSpace(string(output))
}

func waitForContainerAbsence(t *testing.T, container string) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if exec.Command("docker", "inspect", container).Run() != nil {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("container %s was not removed", container)
}

func assertContainerAbsent(t *testing.T, container string) {
	t.Helper()
	if output, err := exec.Command("docker", "inspect", container).CombinedOutput(); err == nil {
		t.Fatalf("container %s unexpectedly exists: %s", container, output)
	}
}

func waitForLog(t *testing.T, container, expected string) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		output, _ := exec.Command("docker", "logs", container).CombinedOutput()
		if strings.Contains(string(output), expected) {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("container %s logs never contained %q", container, expected)
}
