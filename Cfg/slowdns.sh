function ssh_slow(){
clear
print_install "Memasang SlowDNS Server"

# ================= PENGATURAN (ubah di sini) =================
# File slowdns-linux-amd64.tar.gz di root repo Anda (${REPO} = .../Sotgen/suryafebri/main/).
: "${SLOWDNS_URL:=${REPO}slowdns-linux-amd64.tar.gz}"
# Sidik jari (SHA256) file di atas, supaya file yang berubah/diganti orang lain ditolak.
: "${SLOWDNS_SHA256:=6aa42455cd142953270a342e3c24c9c946fdc4ef3cad1e5c02f27711ffc6ad41}"
: "${SLOWDNS_DIR:=/root/slowdns}"
# Tujuan SlowDNS (SSH di VPS ini). Ubah kalau SSH bukan di port 22.
: "${SLOWDNS_UPSTREAM:=127.0.0.1:22}"
# 1 = pakai ulang key lama (/etc/slowdns/server.key) supaya akun lama tetap jalan.
# 0 = buat key baru (public key berubah, user harus ganti public key di aplikasi).
: "${SLOWDNS_KEEP_OLD_KEY:=0}"
# =============================================================

local ns_old ns_domain lip f svc ganti
ns_old=$(cat /etc/xray/dns 2>/dev/null)
ns_domain=""
echo -e ""
echo -e "${YELLOW}----------------------------------------------${FONT}"
echo -e "              DOMAIN NS SLOWDNS"
echo -e "${YELLOW}----------------------------------------------${FONT}"
if [[ -n $ns_old ]]; then
echo -e " Domain NS saat ini : $ns_old"
read -p " Ganti domain NS? [y/N] : " ganti
if [[ $ganti != "y" && $ganti != "Y" ]]; then
ns_domain=$ns_old
fi
fi
if [[ -z $ns_domain ]]; then
while true; do
read -p " Masukkan domain NS baru (contoh: dns.domainanda.com) : " ns_domain
if [[ $ns_domain =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
break
fi
print_error "Domain tidak valid, coba lagi"
done
fi
echo -e " Domain NS dipakai  : $ns_domain"

# IP VPS yang dipakai keluar (dipakai sebagai listener UDP 53, menghindari bentrok dengan systemd-resolved)
lip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
if [[ -z $lip ]]; then
print_error "IP VPS tidak terdeteksi"
return 1
fi

# --- Hapus instalasi SlowDNS yang lama (dnstt: service server & client) ---
for svc in server client; do
f=/etc/systemd/system/$svc.service
if [ -f "$f" ] && grep -qE "dnstt|slowdns" "$f"; then
systemctl disable --now $svc >/dev/null 2>&1
rm -f "$f"
fi
done
# Kalau sudah pernah pasang versi baru: hentikan dulu & pakai pengaturan baru (key tetap dipertahankan)
if [ -f /etc/systemd/system/slowdns.service ]; then
systemctl stop slowdns >/dev/null 2>&1
[ -f "$SLOWDNS_DIR/install.sh" ] && bash "$SLOWDNS_DIR/install.sh" uninstall >/dev/null 2>&1
rm -f "$SLOWDNS_DIR/slowdns.env"
fi
systemctl daemon-reload

mkdir -p "$SLOWDNS_DIR"
if [ "$SLOWDNS_KEEP_OLD_KEY" = "1" ] && [ -s /etc/slowdns/server.key ] && [ -s /etc/slowdns/server.pub ] && [ ! -s "$SLOWDNS_DIR/server.key" ]; then
install -m 0600 /etc/slowdns/server.key "$SLOWDNS_DIR/server.key"
install -m 0644 /etc/slowdns/server.pub "$SLOWDNS_DIR/server.pub"
fi
rm -rf /etc/slowdns

# --- Unduh, cek keaslian, ekstrak ---
wget -q -O /tmp/slowdns.tar.gz "$SLOWDNS_URL"
if [ ! -s /tmp/slowdns.tar.gz ]; then
print_error "Gagal mengunduh SlowDNS dari $SLOWDNS_URL"
return 1
fi
if [ -n "$SLOWDNS_SHA256" ] && ! echo "$SLOWDNS_SHA256  /tmp/slowdns.tar.gz" | sha256sum -c --quiet - >/dev/null 2>&1; then
print_error "SHA256 file SlowDNS tidak cocok, instalasi dibatalkan"
rm -f /tmp/slowdns.tar.gz
return 1
fi
tar -xzf /tmp/slowdns.tar.gz -C "$SLOWDNS_DIR" slowdns install.sh
rm -f /tmp/slowdns.tar.gz
chown root:root "$SLOWDNS_DIR" "$SLOWDNS_DIR/slowdns" "$SLOWDNS_DIR/install.sh"
chmod 755 "$SLOWDNS_DIR" "$SLOWDNS_DIR/slowdns" "$SLOWDNS_DIR/install.sh"

# --- Jalankan installer dengan jawaban otomatis: IP, port, domain, tujuan ---
if ! printf '%s\n%s\n%s\n%s\n' "$lip" 53 "$ns_domain" "$SLOWDNS_UPSTREAM" | bash "$SLOWDNS_DIR/install.sh" install > /root/install.log 2>&1; then
cat /root/install.log
print_error "Instalasi SlowDNS gagal (log: /root/install.log)"
return 1
fi

# --- Kompatibilitas dengan menu/skrip lama ---
mkdir -p /etc/xray /etc/slowdns
echo "$ns_domain" > /etc/xray/dns
ln -sf "$SLOWDNS_DIR/server.pub" /etc/slowdns/server.pub

clear
echo -e "${YELLOW}----------------------------------------------${FONT}"
echo -e " NS Domain  : $ns_domain"
echo -e " Public Key : $(cat $SLOWDNS_DIR/server.pub)"
echo -e " Port       : UDP 53  (buka di firewall VPS & panel provider)"
echo -e " Catatan    : record NS $ns_domain harus menunjuk ke host VPS ini"
echo -e "${YELLOW}----------------------------------------------${FONT}"
sleep 3
print_success "SlowDNS"
}
