package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func certificateFor(addresses []net.IP) (tls.Certificate, error) {
	config, err := os.UserConfigDir()
	if err != nil {
		return tls.Certificate{}, err
	}
	dir := filepath.Join(config, "CanyonTavernLAN")
	if err = os.MkdirAll(dir, 0700); err != nil {
		return tls.Certificate{}, err
	}
	path := filepath.Join(dir, "host.pem")
	if data, err := os.ReadFile(path); err == nil {
		if cert, err := tls.X509KeyPair(data, data); err == nil {
			leaf, err := x509.ParseCertificate(cert.Certificate[0])
			if err == nil && time.Now().Add(24*time.Hour).Before(leaf.NotAfter) {
				matches := true
				for _, ip := range addresses {
					if leaf.VerifyHostname(ip.String()) != nil {
						matches = false
						break
					}
				}
				if matches {
					return cert, nil
				}
			}
		}
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 120))
	if err != nil {
		return tls.Certificate{}, err
	}
	leaf := &x509.Certificate{
		SerialNumber: serial, Subject: pkix.Name{CommonName: "Canyon Tavern LAN"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().AddDate(1, 0, 0),
		DNSNames: []string{"localhost"}, IPAddresses: addresses,
		KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, leaf, leaf, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	pk, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return tls.Certificate{}, err
	}
	data := append(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}),
		pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: pk})...)
	temp, err := os.CreateTemp(dir, "host-*.tmp")
	if err != nil {
		return tls.Certificate{}, err
	}
	defer os.Remove(temp.Name())
	_, writeErr := temp.Write(data)
	if err := temp.Close(); err != nil {
		return tls.Certificate{}, err
	}
	if writeErr != nil {
		return tls.Certificate{}, writeErr
	}
	if err := os.Rename(temp.Name(), path); err != nil {
		return tls.Certificate{}, err
	}
	return tls.X509KeyPair(data, data)
}

func fingerprint(cert tls.Certificate) string {
	hash := sha256.Sum256(cert.Certificate[0])
	return strings.ToUpper(fmt.Sprintf("% X", hash))
}
