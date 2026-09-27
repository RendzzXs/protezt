#!/bin/bash

# ================================================================
#   🛡️  PTERODACTYL OWNER-ONLY PROTECTION v1.0
#   Global protection via AppServiceProvider (anti-bypass)
#   Support: Pterodactyl 1.7 - 1.12+
#   - ID 1 = Owner → bebas semua
#   - ID 2+ = Admin biasa → cuma bisa lihat server sendiri
# ================================================================

set -o pipefail

# -------------------------------
# AUTO-DETECT PANEL PATH
# -------------------------------
detect_ptero_dir() {
    for dir in "/var/www/pterodactyl" "/var/www/ptero" "/home/pterodactyl" "/opt/pterodactyl"; do
        if [ -f "$dir/artisan" ] && [ -f "$dir/composer.json" ]; then
            echo "$dir"; return 0
        fi
    done
    return 1
}

PTERO_DIR="$(detect_ptero_dir)"
if [ -z "$PTERO_DIR" ]; then
    echo -e "\033[0;31m❌ Panel Pterodactyl tidak ditemukan!\033[0m"
    exit 1
fi

# -------------------------------
# PATH & FILE
# -------------------------------
PROVIDER_FILE="$PTERO_DIR/app/Providers/AppServiceProvider.php"
BACKUP_ROOT="$PTERO_DIR/.pterodactyl_protect"
LOG_FILE="$BACKUP_ROOT/protect.log"
SEC_LOG="$BACKUP_ROOT/security.log"
MW_OWNER="$PTERO_DIR/app/Http/Middleware/PterodactylOwnerOnly.php"
MW_SERVER="$PTERO_DIR/app/Http/Middleware/PterodactylServerAccess.php"
KERNEL_FILE="$PTERO_DIR/app/Http/Kernel.php"
ROUTE_BASE="$PTERO_DIR/routes/base.php"
ROUTE_ADMIN="$PTERO_DIR/routes/admin.php"
TARGET_FILE="$PTERO_DIR/resources/views/templates/base/core.blade.php"

# -------------------------------
# WARNA
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PINK='\033[0;95m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# -------------------------------
# UTIL
# -------------------------------
log_action() {
    mkdir -p "$BACKUP_ROOT"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Harus root! Coba: sudo bash $0${NC}"
        exit 1
    fi
}

check_deps() {
    local missing=()
    for cmd in curl php; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Dependency hilang: ${missing[*]}${NC}"
        exit 1
    fi
}

spinner() {
    local pid=$1 delay=0.1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while ps -p "$pid" > /dev/null 2>&1; do
        for f in "${frames[@]}"; do
            echo -ne "\r${CYAN}$f${NC} ${DIM}$2${NC}"
            sleep $delay
            ps -p "$pid" > /dev/null 2>&1 || break
        done
    done
    echo -ne "\r\033[K"
}

timestamp() { date '+%Y%m%d_%H%M%S'; }

# -------------------------------
# HEADER
# -------------------------------
show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${WHITE}${BOLD}    🛡️  PTERODACTYL OWNER-ONLY PROTECTION v1.0        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${DIM}         Global Protection (Anti-Bypass)              ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} ${GREEN}📁 Panel :${NC} ${WHITE}$PTERO_DIR${NC}"
    echo -e "${CYAN}║${NC} ${GREEN}👤 User  :${NC} ${WHITE}$(whoami)${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# -------------------------------
# BACKUP
# -------------------------------
backup_provider() {
    local ts=$(timestamp)
    local dir="$BACKUP_ROOT/$ts"
    mkdir -p "$dir"
    [ -f "$PROVIDER_FILE" ] && cp "$PROVIDER_FILE" "$dir/AppServiceProvider.php"
    [ -f "$TARGET_FILE" ] && cp "$TARGET_FILE" "$dir/core.blade.php"
    echo "$ts"
    log_action "BACKUP: $dir"
}

# -------------------------------
# INSTALL PROTECTION
# -------------------------------
install_protection() {
    show_header
    echo -e "${YELLOW}🛡️  INSTALL PTERODACTYL OWNER-ONLY PROTECTION${NC}\n"
    echo -e "${WHITE}Aturan:${NC}"
    echo -e "  ${GREEN}✓${NC} ID 1 (Owner)  : bebas semua menu & aksi"
    echo -e "  ${RED}✗${NC} ID 2+ (Admin) : cuma bisa lihat server miliknya"
    echo -e "  ${RED}✗${NC} ID 2+         : menu admin (Settings, API, Users, Nodes, dll) hidden + blocked"
    echo -e "  ${RED}✗${NC} ID 2+         : aksi (create/edit/delete) → 403"
    echo -e "  ${RED}✗${NC} ID 2+         : intip server orang → 404"
    echo ""
    echo -ne "${YELLOW}➤ Lanjutkan install? [y/N]: ${NC}"
    read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || return 0

    echo ""
    echo -e "${YELLOW}📦 Membuat backup...${NC}"
    local BK_TS=$(backup_provider)
    echo -e "${GREEN}✅ Backup: $BACKUP_ROOT/$BK_TS${NC}"

    # -------------------------------
    # 1. PASTIKAN PROVIDER FILE ADA
    # -------------------------------
    if [ ! -f "$PROVIDER_FILE" ]; then
        echo -e "${RED}❌ AppServiceProvider.php tidak ditemukan!${NC}"
        return 1
    fi

    # -------------------------------
    # 2. TULIS ULANG PROVIDER DENGAN PROTEKSI
    # -------------------------------
    echo -e "\n${YELLOW}📝 Menulis ulang AppServiceProvider.php...${NC}"

    # Cek dulu apakah udah pernah di-patch
    if grep -q "PTERODACTYL_OWNER_PROTECTION" "$PROVIDER_FILE"; then
        echo -e "${DIM}ℹ️  Proteksi sudah ada, skip.${NC}"
    else
        cat > "$PROVIDER_FILE" << 'PHPEOF'
<?php

namespace App\Providers;

use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;
use Illuminate\Routing\Events\RouteMatched;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->registerOwnerProtection();
    }

    /**
     * ============================================================
     *   PTERODACTYL_OWNER_PROTECTION
     *   Global protection - anti bypass
     *   - ID 1     : bebas semua
     *   - ID 2+    : read-only, cuma server sendiri
     * ============================================================
     */
    protected function registerOwnerProtection(): void
    {
        Event::listen(RouteMatched::class, function (RouteMatched $event) {

            $user = auth()->user();

            // Belum login → biar auth yang handle
            if (!$user) {
                return;
            }

            // ID 1 = Owner → bebas
            if ((int) $user->id === 1) {
                return;
            }

            $request = request();
            $path    = trim($request->path(), '/');
            $method  = $request->method();

            // Prefix admin yang HANYA boleh diakses ID 1
            $ownerOnlyPrefixes = [
                'admin',
            ];

            // Cek prefix
            foreach ($ownerOnlyPrefixes as $prefix) {
                if ($path === $prefix || str_starts_with($path, $prefix . '/')) {
                    // Khusus overview boleh lihat
                    if ($path === 'admin' || $path === 'admin/' || $path === 'admin/overview') {
                        // Lanjut cek aksi non-GET di bawah
                        break;
                    }
                    $this->logSecurity($request, $user, 'ADMIN_BLOCKED');
                    $this->deny($request, '🔒 Akses ditolak. Hanya Owner yang boleh mengakses menu ini.');
                    return;
                }
            }

            // Blokir aksi non-GET (create/edit/delete) di luar auth
            if (!in_array($method, ['GET', 'HEAD', 'OPTIONS'])) {
                // Skip auth routes biar login/logout tetap jalan
                if (str_starts_with($path, 'auth/') || $path === 'auth') {
                    return;
                }
                // Skip 2FA & password reset
                if (str_starts_with($path, 'auth/') || str_contains($path, 'password') || str_contains($path, 'two-factor')) {
                    return;
                }

                $this->logSecurity($request, $user, 'ACTION_BLOCKED');
                $this->deny($request, '🔒 Akses ditolak. Hanya Owner yang boleh melakukan aksi ini.');
                return;
            }

            // Cek akses server milik orang lain
            $this->checkServerAccess($request, $user);
        });
    }

    /**
     * Cek akses ke server
     */
    protected function checkServerAccess($request, $user): void
    {
        $path = trim($request->path(), '/');

        // Format: server/{uuid} atau server/{uuid}/...
        if (!preg_match('#^server/([a-zA-Z0-9\-]+)#', $path, $m)) {
            return;
        }

        $uuid = $m[1];
        if (empty($uuid)) {
            return;
        }

        // Lookup server
        try {
            $server = \Pterodactyl\Models\Server::where('uuid', $uuid)
                ->orWhere('uuidShort', $uuid)
                ->first();
        } catch (\Throwable $e) {
            return;
        }

        if (!$server) {
            return;
        }

        // Cek owner
        if ((int) $server->owner_id === (int) $user->id) {
            return;
        }

        // Cek subuser
        $isSubuser = false;
        try {
            $isSubuser = $server->subusers()
                ->where('user_id', $user->id)
                ->exists();
        } catch (\Throwable $e) {
            $isSubuser = false;
        }

        if ($isSubuser) {
            return;
        }

        // Bukan owner & bukan subuser → 404 nyamar
        $this->logSecurity($request, $user, 'SERVER_SNOOP_BLOCKED');
        abort(404);
    }

    /**
     * Kirim response deny
     */
    protected function deny($request, string $message): void
    {
        if ($request->expectsJson() || $request->ajax()) {
            abort(response()->json(['error' => $message], 403));
        }
        abort(redirect('/')->with('error', $message));
    }

    /**
     * Log ke file security.log
     */
    protected function logSecurity($request, $user, string $tag): void
    {
        $logDir = base_path('.pterodactyl_protect');
        if (!is_dir($logDir)) {
            @mkdir($logDir, 0755, true);
        }
        $line = sprintf(
            "[%s] %s | user_id=%s | ip=%s | method=%s | url=%s\n",
            date('Y-m-d H:i:s'),
            $tag,
            $user->id,
            $request->ip(),
            $request->method(),
            $request->fullUrl()
        );
        @file_put_contents($logDir . '/security.log', $line, FILE_APPEND);
    }
}
PHPEOF
        echo -e "${GREEN}✅ AppServiceProvider.php ditulis${NC}"
    fi

    # -------------------------------
    # 3. FRONTEND - SEMBUNYIIN MENU
    # -------------------------------
    echo -e "\n${YELLOW}🎨 Inject frontend protection...${NC}"
    if [ -f "$TARGET_FILE" ] && ! grep -q "PTERODACTYL_OWNER_PROTECTION" "$TARGET_FILE"; then
        php -r '
            $f = $argv[1];
            if (!file_exists($f)) exit(1);
            $c = file_get_contents($f);
            $script = <<<"JS"

    {{-- PTERODACTYL_OWNER_PROTECTION --}}
    <script>
        (function() {
            const isOwner = {{ auth()->check() && auth()->id() === 1 ? "true" : "false" }};
            if (isOwner) return;

            const css = `
                a[href*="/admin/settings"],
                a[href*="/admin/api"],
                a[href*="/admin/databases"],
                a[href*="/admin/locations"],
                a[href*="/admin/nodes"],
                a[href*="/admin/servers"],
                a[href*="/admin/users"],
                a[href*="/admin/mounts"],
                a[href*="/admin/nests"],
                a[href*="/admin/eggs"],
                a[href*="/admin/backups"],
                button[data-action="delete"],
                .btn-danger,
                [data-cy="delete-server"],
                [data-cy="new-server"],
                [data-cy="create-server"] {
                    display: none !important;
                }
            `;
            const s = document.createElement("style");
            s.textContent = css;
            document.head.appendChild(s);

            document.addEventListener("click", function(e) {
                const a = e.target.closest("a");
                if (!a) return;
                const href = a.getAttribute("href") || "";
                if (/^\/admin\/(settings|api|databases|locations|nodes|servers|users|mounts|nests|eggs|backups)/.test(href)) {
                    e.preventDefault();
                    e.stopPropagation();
                    alert("🔒 Akses ditolak. Hanya Owner yang boleh mengakses menu ini.");
                    return false;
                }
            }, true);

            console.log("%c🛡️ Pterodactyl Owner Protection aktif", "color:#4ecdc4;font-weight:bold;font-size:14px;");
        })();
    </script>
JS;
            $pos = strrpos($c, "@endsection");
            if ($pos !== false) {
                $c = substr($c, 0, $pos) . $script . "\n" . substr($c, $pos);
            } else {
                $c .= $script;
            }
            file_put_contents($f, $c);
        ' "$TARGET_FILE"
        grep -q "PTERODACTYL_OWNER_PROTECTION" "$TARGET_FILE" \
            && echo -e "${GREEN}✅ Frontend protection disuntik${NC}" \
            || echo -e "${RED}⚠️  Gagal inject frontend${NC}"
    else
        echo -e "${DIM}ℹ️  Frontend protection sudah ada${NC}"
    fi

    # -------------------------------
    # 4. CLEAR CACHE
    # -------------------------------
    echo -e "\n${YELLOW}🧹 Clear cache...${NC}"
    cd "$PTERO_DIR" 2>/dev/null
    (php artisan optimize:clear >/dev/null 2>&1) & spinner $! "Clear all cache..."
    (php artisan route:clear >/dev/null 2>&1) & spinner $! "Clear route cache..."
    (php artisan view:clear >/dev/null 2>&1) & spinner $! "Clear view cache..."
    (php artisan config:clear >/dev/null 2>&1) & spinner $! "Clear config cache..."

    log_action "INSTALL protection selesai (backup: $BK_TS)"

    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✅ PROTECTION BERHASIL DIPASANG! ✅               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🆔 ID 1 (Owner)  :${NC} ✅ Bebas semua akses"
    echo -e "${RED}🆔 ID 2+ (Admin) :${NC} ❌ Menu admin hidden + blocked"
    echo -e "${RED}🆔 ID 2+ (Admin) :${NC} ❌ Aksi (create/edit/delete) → 403"
    echo -e "${RED}🆔 ID 2+ (Admin) :${NC} ❌ Intip server orang → 404"
    echo -e "${GREEN}🆔 ID 2+ (Admin) :${NC} ✅ Cuma server miliknya sendiri"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📝 Log keamanan:${NC} $SEC_LOG"
    echo -e "${GREEN}🚀 Refresh browser (CTRL+SHIFT+R)!${NC}"
    echo ""
    echo -e "${DIM}ℹ️  Proteksi berjalan di level event RouteMatched —"
    echo -e "   nggak peduli route/kernel format apapun. PASTI WORK.${NC}"
}

# -------------------------------
# UNINSTALL
# -------------------------------
uninstall_protection() {
    show_header
    echo -e "${YELLOW}🗑️  UNINSTALL PROTECTION${NC}\n"
    echo -ne "${YELLOW}➤ Yakin mau hapus proteksi? [y/N]: ${NC}"
    read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || return 0

    local BK_TS=$(backup_provider)
    echo -e "${GREEN}✅ Backup: $BACKUP_ROOT/$BK_TS${NC}"

    # Tulis ulang provider bersih
    cat > "$PROVIDER_FILE" << 'PHPEOF'
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        //
    }
}
PHPEOF
    echo -e "${GREEN}✅ AppServiceProvider.php dibersihin${NC}"

    # Hapus JS injection
    if [ -f "$TARGET_FILE" ] && grep -q "PTERODACTYL_OWNER_PROTECTION" "$TARGET_FILE"; then
        php -r '
            $f = $argv[1];
            $c = file_get_contents($f);
            $c = preg_replace("/\s*\{\{-- PTERODACTYL_OWNER_PROTECTION --\}\}.*?<\/script>/s", "", $c);
            file_put_contents($f, $c);
        ' "$TARGET_FILE"
        echo -e "${GREEN}✅ Frontend protection dihapus${NC}"
    fi

    cd "$PTERO_DIR" 2>/dev/null
    (php artisan optimize:clear >/dev/null 2>&1) & spinner $! "Clear cache..."

    log_action "UNINSTALL protection selesai"
    echo -e "\n${GREEN}✅ Proteksi dihapus. Panel kembali normal.${NC}"
}

# -------------------------------
# STATUS
# -------------------------------
show_status() {
    show_header
    echo -e "${YELLOW}📊 STATUS PROTEKSI:${NC}\n"

    if grep -q "PTERODACTYL_OWNER_PROTECTION" "$PROVIDER_FILE" 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} Backend Protection : ${WHITE}AKTIF${NC} (AppServiceProvider)"
    else
        echo -e "  ${RED}❌${NC} Backend Protection : ${DIM}Tidak aktif${NC}"
    fi

    if grep -q "PTERODACTYL_OWNER_PROTECTION" "$TARGET_FILE" 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} Frontend Protection: ${WHITE}AKTIF${NC} (core.blade.php)"
    else
        echo -e "  ${RED}❌${NC} Frontend Protection: ${DIM}Tidak aktif${NC}"
    fi

    echo -e "\n  ${CYAN}📦 Total backup:${NC} $(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"

    if [ -f "$SEC_LOG" ]; then
        echo -e "\n${YELLOW}🔒 LOG KEAMANAN TERAKHIR:${NC}"
        tail -8 "$SEC_LOG" | sed 's/^/  /'
    else
        echo -e "\n${DIM}ℹ️  Belum ada aktivitas keamanan.${NC}"
    fi
}

# -------------------------------
# ROLLBACK
# -------------------------------
rollback_menu() {
    show_header
    echo -e "${YELLOW}🔄 DAFTAR BACKUP:${NC}\n"
    if [ ! -d "$BACKUP_ROOT" ] || [ -z "$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]; then
        echo -e "${RED}❌ Tidak ada backup!${NC}"; return 1
    fi
    local i=1 dirs=()
    while IFS= read -r d; do
        dirs+=("$d")
        echo -e "  ${CYAN}[$i]${NC} $(basename "$d")  ${DIM}($(date -r "$d" '+%d %b %Y %H:%M'))${NC}"
        i=$((i+1))
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r)
    echo ""
    echo -ne "${YELLOW}➤ Pilih nomor backup (0 batal): ${NC}"
    read -r pick
    [ "$pick" = "0" ] && return 0
    local chosen="${dirs[$((pick-1))]}"
    if [ -z "$chosen" ] || [ ! -d "$chosen" ]; then
        echo -e "${RED}❌ Backup tidak valid!${NC}"; return 1
    fi
    for f in "$chosen"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            AppServiceProvider.php) cp "$f" "$PROVIDER_FILE" ;;
            core.blade.php)         cp "$f" "$TARGET_FILE" ;;
        esac
    done
    cd "$PTERO_DIR" || return 1
    php artisan optimize:clear >/dev/null 2>&1
    log_action "ROLLBACK dari: $chosen"
    echo -e "\n${GREEN}✅ Rollback berhasil dari $(basename "$chosen")${NC}"
}

# -------------------------------
# MAIN
# -------------------------------
require_root
check_deps
mkdir -p "$BACKUP_ROOT"

while true; do
    show_header
    echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║           🛡️  PILIH MENU 🛡️                ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║                                          ║${NC}"
    echo -e "${WHITE}║  ${PURPLE}[1]${NC} 🛡️  INSTALL Protection            ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${YELLOW}[2]${NC} 🔓 HAPUS Protection              ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${BLUE}[3]${NC} 🔄 ROLLBACK dari Backup         ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN}[4]${NC} 📊 STATUS Proteksi              ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${RED}[x]${NC} ❌ KELUAR                       ${WHITE}║${NC}"
    echo -e "${WHITE}║                                          ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${YELLOW}➤ Pilih menu [1-4/x]: ${NC}"
    read -r MENU

    case $MENU in
        1) install_protection ;;
        2) uninstall_protection ;;
        3) rollback_menu ;;
        4) show_status ;;
        x|X)
            echo -e "\n${GREEN}✨ Thanks!${NC}\n"
            exit 0
            ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; continue ;;
    esac
    echo ""
    echo -ne "${CYAN}Tekan Enter untuk kembali...${NC}"
    read -r
done
