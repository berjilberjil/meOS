cask "meos" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/berjilberjil/meOS/releases/download/mac-build-9/meOS.app.zip"
  name "meOS"
  desc "Personal life operating system"
  homepage "https://github.com/berjilberjil/meOS"

  app "meOS.app"
end
