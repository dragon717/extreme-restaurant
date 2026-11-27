// Serve only the exported game. The same source builds the bundled Mac and Windows hosts.
package main

import (
	"crypto/sha256"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const identityPath = "/_canyon_host"

func openBrowser(address string) {
	var command *exec.Cmd
	if runtime.GOOS == "windows" {
		command = exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", address)
	} else {
		command = exec.Command("open", address)
	}
	if err := command.Run(); err != nil {
		fmt.Println("请在浏览器中打开上方地址。")
	}
}

func lanAddresses() []net.IP {
	var result []net.IP
	interfaces, _ := net.Interfaces()
	for _, nic := range interfaces {
		if nic.Flags&net.FlagUp == 0 || nic.Flags&(net.FlagLoopback|net.FlagPointToPoint) != 0 {
			continue
		}
		addresses, _ := nic.Addrs()
		for _, address := range addresses {
			ip, _, err := net.ParseCIDR(address.String())
			if err == nil && ip.To4() != nil && ip.IsGlobalUnicast() {
				result = append(result, ip.To4())
			}
		}
	}
	return result
}

func printAddresses(port int, addresses []net.IP) string {
	local := fmt.Sprintf("http://127.0.0.1:%d/", port)
	fmt.Println("本机游玩  ", local)
	for _, ip := range addresses {
		fmt.Printf("局域网    https://%s:%d/\n", ip, port+1)
	}
	return local
}

func sameHost(port int, id string) bool {
	client := &http.Client{Timeout: 400 * time.Millisecond}
	response, err := client.Get(fmt.Sprintf("http://127.0.0.1:%d%s", port, identityPath))
	if err != nil {
		return false
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 100))
	return err == nil && response.StatusCode == http.StatusOK && string(data) == id
}

func serveGame(site, id string) http.Handler {
	types := map[string]string{".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".ico": "image/x-icon"}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.URL.Path == identityPath {
			w.Header().Set("Cache-Control", "no-store")
			fmt.Fprint(w, id)
			return
		}
		name := strings.TrimPrefix(r.URL.Path, "/")
		if name == "" {
			name = "index.html"
		}
		mime, supported := types[filepath.Ext(name)]
		if !supported || strings.ContainsAny(name, "/\\:") || !(strings.HasPrefix(name, "index.") || name == "favicon.ico") {
			http.NotFound(w, r)
			return
		}
		file, err := os.Open(filepath.Join(site, name))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		defer file.Close()
		info, err := file.Stat()
		if err != nil || !info.Mode().IsRegular() {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", mime)
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeContent(w, r, name, info.ModTime(), file)
	})
}

func main() {
	port := flag.Int("port", 8179, "首选局域网端口")
	browse := flag.Bool("open", true, "启动后打开本机浏览器")
	flag.Parse()
	log.SetFlags(0)
	if *port < 1 || *port > 65534 {
		log.Fatal("端口须在 1 到 65534 之间。")
	}
	exe, err := os.Executable()
	if err != nil {
		log.Fatal(err)
	}
	site := filepath.Join(filepath.Dir(filepath.Dir(exe)), "site")
	for _, file := range []string{"index.html", "index.js", "index.wasm", "index.pck"} {
		if info, err := os.Stat(filepath.Join(site, file)); err != nil || info.Size() == 0 {
			log.Fatalf("缺少网页文件 %s，请先完整解压游戏包。", file)
		}
	}
	id := fmt.Sprintf("%x", sha256.Sum256([]byte("峡谷餐厅/web/"+site)))
	addresses := lanAddresses()
	for candidate := *port; candidate <= min(*port+19, 65534); candidate++ {
		listener, err := net.Listen("tcp4", "127.0.0.1:"+strconv.Itoa(candidate))
		if err != nil {
			if sameHost(candidate, id) {
				fmt.Println("这份峡谷餐厅已在运行。")
				local := printAddresses(candidate, addresses)
				if *browse {
					openBrowser(local)
				}
				return
			}
			continue
		}
		lan, err := net.Listen("tcp4", ":"+strconv.Itoa(candidate+1))
		if err != nil {
			listener.Close()
			continue
		}
		cert, err := certificateFor(append([]net.IP{net.IPv4(127, 0, 0, 1)}, addresses...))
		if err != nil {
			log.Fatal("创建局域网证书失败：", err)
		}
		handler := serveGame(site, id)
		secure := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 90 * time.Second,
			TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{cert}}}
		go func() { log.Fatal(secure.ServeTLS(lan, "", "")) }()
		fmt.Println("峡谷餐厅 · 网页版")
		local := printAddresses(candidate, addresses)
		fmt.Println("局域网证书 SHA-256：", fingerprint(cert))
		fmt.Println("同一网络的设备可打开局域网地址。保留此窗口，按 Ctrl+C 停止。")
		if *browse {
			go openBrowser(local)
		}
		server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 90 * time.Second}
		log.Fatal(server.Serve(listener))
	}
	log.Fatal("没有可用端口，请使用 -port 指定其他端口。")
}
