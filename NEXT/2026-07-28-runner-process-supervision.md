# Supervise and scrub scheduled runner processes

- Stop the pinned wrapper/helper/Listener/Worker topology as one bounded process
  group before deregistration, including a group-wide KILL for ignored TERM.
- Keep registration/removal sources in non-exported supervisor state and scrub
  credential-bearing and shell-injection variables from Listener/Worker.
- Make disposable-container marker absence observable and asserted in the live
  Docker lifecycle test.
