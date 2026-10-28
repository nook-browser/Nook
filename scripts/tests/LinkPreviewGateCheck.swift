import Foundation

@main
struct LinkPreviewGateCheck {
    static func main() {
        func may(_ s: String, priv: Bool = false, agent: Bool = false, blocked: Bool = false) -> Bool {
            LinkPreviewGate.mayFetch(url: URL(string: s)!, isPrivate: priv, isAgent: agent, blocked: blocked)
        }
        precondition(may("https://example.com/a?b=1"))
        precondition(may("http://example.org"))
        precondition(!may("https://example.com", priv: true))
        precondition(!may("https://example.com", agent: true))
        precondition(!may("https://example.com", blocked: true))
        for s in ["ftp://example.com", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,hi",
                  "https://localhost/", "https://LOCALHOST:8080/", "https://printer.local/", "https://foo.localhost/",
                  "https://10.0.0.1/", "https://172.16.5.5/", "https://172.31.255.255/", "https://192.168.1.1/",
                  "https://127.0.0.1:47823/mcp", "https://127.1.2.3/", "https://169.254.169.254/latest/meta-data",
                  "https://0.0.0.0/", "https://[::1]/", "https://[fe80::1]/", "https://[fd00::1]/",
                  "https://[::ffff:192.168.1.1]/", "https://2130706433/", "https://0x7f.0.0.1/",
                  "https://localhost./", "https://example.local./", "https://router/", "https://nas.lan/", "https://x.internal/",
                  "https://x.home.arpa/", "https://a.localhost/", "https://100.64.0.1/", "https://100.127.255.254/",
                  "https://224.0.0.1/", "https://198.18.0.1/", "https://198.19.255.255/", "https://240.0.0.1/",
                  "https://255.255.255.255/", "https://[::127.0.0.1]/", "https://[::7f00:1]/", "https://[::10.0.0.1]/",
                  "https://[64:ff9b::7f00:1]/", "https://[64:ff9b::a00:1]/", "https://[ff02::1]/", "https://127.0.0.1./"] {
            precondition(!may(s), "should refuse \(s)")
        }
        precondition(may("https://172.32.0.1/"), "172.32 is public")
        precondition(may("https://8.8.8.8/"))
        precondition(may("https://notlocal.com/"))
        precondition(may("https://100.128.0.1/") && may("https://198.20.0.1/") && may("https://223.1.1.1/"))
        precondition(may("https://[64:ff9b::808:808]/") && may("https://example.com./"))
        precondition(LinkPreviewGate.anyReserved([]) && LinkPreviewGate.anyReserved(["8.8.8.8", "10.0.0.5"]))
        precondition(!LinkPreviewGate.anyReserved(["8.8.8.8", "2606:4700::1111"]))
        print("LinkPreviewGateCheck ok")
    }
}
