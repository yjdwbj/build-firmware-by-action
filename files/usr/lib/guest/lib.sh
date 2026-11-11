# Guest Wi-Fi common functions: shared by /usr/bin/guest-card and /www/cgi-bin/guest

GUEST_VF=/tmp/ndslog/vouchers.txt       # File containing internet access codes read by the openNDS theme_voucher
GUEST_CF=/tmp/ndslog/vouchers.created   # Generation time for each code (expires if unused within 24 hours)
GUEST_UNUSED_TTL=86400

guest_ssid()     { uci -q get wireless.guest_2g.ssid; }
guest_key()      { uci -q get wireless.guest_2g.key; }
guest_wifi_uri() { echo "WIFI:T:WPA;S:$(guest_ssid);P:$(guest_key);;"; }

# Current Guest Wi-Fi QR code (inline SVG)
guest_qr_svg() {
	qrencode -t SVG -s 8 -m 2 -o - "$(guest_wifi_uri)" | sed -n '/<svg/,$p'
}

_guest_rand4() { tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' </dev/urandom | head -c 4; }

_guest_rand8() { tr -dc '0-9' </dev/urandom | head -c 8; }

# guest_new_codes [hours] [number of codes] → Outputs one new internet access code per line (9 characters long, as required by openNDS)
guest_new_codes() {
	local h=$1 n=$2 i=0 c now
	now=$(date +%s)
	mkdir -p /tmp/ndslog
	touch "$GUEST_VF"
	while [ "$i" -lt "$n" ]; do
		c=$(_guest_rand8)
		grep -q "^$c," "$GUEST_VF" && continue
		echo "$c,0,0,0,0,$((h * 60)),0" >> "$GUEST_VF"
		echo "$c $now" >> "$GUEST_CF"
		echo "$c"
		i=$((i + 1))
	done
}

guest_css() {
cat <<'EOF'
<style>
:root{--bg:#f6f7f9;--fg:#111;--muted:#555;--card:#fff;--line:#d0d4da;--accent:#1f6feb;--danger:#c62828}
@media (prefers-color-scheme:dark){:root{--bg:#15171a;--fg:#e8e8e8;--muted:#a0a4aa;--card:#1f2226;--line:#3a3f46;--accent:#4c8dff;--danger:#ef5350}}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font-family:system-ui,sans-serif;line-height:1.5}
main{max-width:880px;margin:0 auto}
h1{font-size:22px;margin:4px 0 16px}
h2{font-size:17px;margin:24px 0 10px}
section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin-bottom:16px}
.wifi{display:flex;gap:20px;align-items:center;flex-wrap:wrap}
.qr{background:#fff;border-radius:8px;padding:6px;line-height:0}
.qr svg{width:200px;height:200px}
.big .qr svg{width:240px;height:240px}
.kv{font-size:15px}.kv b{font-family:ui-monospace,monospace;font-size:18px}
.muted{color:var(--muted);font-size:13px}
form.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
select,button{font-size:15px;padding:8px 12px;border-radius:6px;border:1px solid var(--line);background:var(--card);color:var(--fg)}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff}
button.danger{border-color:var(--danger);color:var(--danger)}
.msg{padding:10px 14px;border-radius:8px;border:1px solid var(--accent);margin-bottom:16px}
.cards{display:flex;flex-wrap:wrap;gap:12px}
.card{border:1px dashed var(--line);border-radius:8px;padding:14px;width:260px;text-align:center;background:var(--card)}
.card .qr{display:inline-block}
.code{font:bold 28px ui-monospace,monospace;letter-spacing:2px;margin:6px 0}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}
td.mono{font-family:ui-monospace,monospace}
td.mono,td.dur{white-space:nowrap}
section>h2:first-child{margin-top:0}
@media print{
  body{background:#fff;color:#000;padding:0}
  .noprint{display:none!important}
  section{border:0;padding:0}
  .card{break-inside:avoid;border-color:#888;background:#fff}
}
</style>
EOF
}

# guest_cards_html  Hours  Code 1  Code 2 ...  → Printable cards
guest_cards_html() {
	local h=$1 qr ssid stamp c
	shift
	qr=$(guest_qr_svg); ssid=$(guest_ssid); stamp=$(date '+%Y-%m-%d %H:%M')
	echo '<div class="cards">'
	for c in "$@"; do
cat <<EOF
<div class="card">
  <div>① 扫码连接 Wi-Fi「${ssid}」</div>
  <div class="qr">${qr}</div>
  <div>② 在弹出的页面输入上网码</div>
  <div class="code">${c}</div>
  <div class="muted">首次使用后 ${h} 小时内有效<br>24 小时内未使用自动作废<br>
  二维码当天有效（每天 04:00 更换）<br>生成于 ${stamp}</div>
</div>
EOF
	done
	echo '</div>'
}

# guest_list_html → Status table of all current internet access codes
guest_list_html() {
	[ -s "$GUEST_VF" ] || { echo '<p class="muted">暂无上网码。</p>'; return; }
	awk -F, -v now="$(date +%s)" -v ttl="$GUEST_UNUSED_TTL" -v cf="$GUEST_CF" '
	function dur(s,  h,m){ if (s < 0) s = 0; h = int(s/3600); m = int((s%3600)/60); return (h ? h "小时" : "") m "分" }
	BEGIN {
		while ((getline l < cf) > 0) { split(l, a, " "); created[a[1]] = a[2] }
		print "<table><tr><th>上网码</th><th>时长</th><th>状态</th></tr>"
	}
	{
		code = $1; mins = $6 + 0; used = $7 + 0
		if (used > 0) {
			left = used + mins*60 - now
			st = (left > 0) ? "使用中，剩余 " dur(left) : "已到期"
		} else if (code in created) {
			st = "未使用，" dur(created[code] + ttl - now) "后作废"
		} else st = "未使用"
		printf "<tr><td class=\"mono\">%s</td><td class=\"dur\">%d 小时</td><td>%s</td></tr>\n", code, mins/60, st
	}
	END { print "</table>" }' "$GUEST_VF"
}
