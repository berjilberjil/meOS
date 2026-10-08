cask "myos" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/berjilberjil/MyOS/releases/download/mac-build-1/MyOS.app.zip"
  name "MyOS"
  desc "Personal life operating system"
  homepage "https://github.com/berjilberjil/MyOS"

  app "MyOS.app"
end
