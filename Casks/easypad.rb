cask "easypad" do
  version "1.1"
  sha256 "819d879ddd2e7d39fb6213b2027bd515b99ce4068c4dcfa89e3eced7546a69b3"

  url "https://github.com/dmnkx/homebrew-easypad/releases/download/v#{version}/EasyPad.zip"
  name "EasyPad"
  desc "Text editor modelled on Windows 11 Notepad"
  homepage "https://github.com/dmnkx/homebrew-easypad"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "EasyPad.app"

  # the app is ad-hoc signed, not notarized, so Gatekeeper would block the quarantined download
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/EasyPad.app"]
  end

  zap trash: [
    "~/Library/Application Support/EasyPad",
    "~/Library/Preferences/io.github.dmnkx.easypad.plist",
  ]
end
