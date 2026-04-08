class Blink < Formula
  desc "Block websites and all subdomains with math challenge to unlock"
  homepage "https://github.com/neilthomas/blink"
  url "https://github.com/neilthomas/blink/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"

  depends_on "dnsmasq"

  def install
    bin.install "blink"
  end

  def post_install
    # Create config directories
    (etc/"dnsmasq.d").mkpath
    (etc/"blink").mkpath

    # Create default config if it doesn't exist
    config_file = etc/"blink/config"
    unless config_file.exist?
      config_file.write "MATH_DIFFICULTY=times_tables\n"
    end
  end

  def caveats
    <<~EOS
      To complete setup:
        1. Start dnsmasq: sudo brew services start dnsmasq
        2. Set DNS to 127.0.0.1 in System Preferences > Network > DNS

      Usage:
        sudo blink linkedin.com     # Block with hard lock
        sudo blink -u linkedin.com  # Unblock (math challenge)
        sudo blink --setup          # Set difficulty
    EOS
  end

  test do
    assert_match "Block websites", shell_output("#{bin}/blink --help")
  end
end
