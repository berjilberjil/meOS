cask "meos" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/berjilberjil/meOS/releases/download/mac-build-10/MeOS.app.zip"
  name "meOS"
  desc "Personal life operating system"
  homepage "https://github.com/berjilberjil/meOS"

  depends_on macos: ">= :tahoe"

  app "MeOS.app"
end
