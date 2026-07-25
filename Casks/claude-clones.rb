# Homebrew cask for this repo, usable as a tap:
#
#   brew tap hudiohizari/claude-desktop-multi-account https://github.com/hudiohizari/claude-desktop-multi-account
#   brew install --cask claude-clones
#
# On each release, bump version and sha256 to the values the release notes print.
cask "claude-clones" do
  version "0.1.0"
  sha256 "2d9e67eb833a4f21f287aa838d3ba359b0d4a267e1bd8ba1c53f71e7feb8bdd4"

  url "https://github.com/hudiohizari/claude-desktop-multi-account/releases/download/v#{version}/ClaudeClones-v#{version}.zip"
  name "Claude Clones"
  desc "Run multiple Claude Desktop accounts side by side, with claude:// link routing"
  homepage "https://github.com/hudiohizari/claude-desktop-multi-account"

  depends_on macos: ">= :monterey"

  app "Claude Clones.app"

  # Profiles hold the logins, chats and Cowork VMs, so they are never removed
  # automatically. Delete them from the app, or by hand, when you mean to.
  uninstall quit: "com.local.claudeclones"

  zap trash: [
    "~/Library/Logs/ClaudeClones.log",
    "~/Library/Preferences/com.local.claudeclones.plist",
  ]

  caveats <<~EOS
    Profiles live in ~/.claude-instances and each launcher in ~/Applications.
    Uninstalling leaves both in place, so your logins and chats survive. Remove a
    profile from the app's menu when you actually want its data gone.
  EOS
end
