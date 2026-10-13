# Sourced by run.sh. Nothing in the spec may reach the network, send a desktop
# notification, or read or write the real weather location, so:
#   - tests/fixtures/bin goes first on PATH (canned curl, silent notifier);
#   - HOME is a throwaway directory, which is where the plugin and
#     omarchy-weather-location keep the location (weather.json).
SPEC_SANDBOX=$(mktemp -d)
mkdir -p "$SPEC_SANDBOX/home"
export HOME="$SPEC_SANDBOX/home"
export PATH="$here/fixtures/bin:$PATH"

spec_teardown() {
  rm -rf "$SPEC_SANDBOX"
}
