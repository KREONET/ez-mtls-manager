#!/bin/sh

# ==============================================================================
# EZ-mTLS Manager 설치 스크립트
#
# 이 스크립트는 Ubuntu 24.04 LTS 환경에서 EZ-mTLS Manager를 배포하기 위한 환경을 구성합니다.
# 실행 전 루트 권한(sudo)이 필요합니다.
# ==============================================================================

set -e

# 색상 코드
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "${GREEN}=== EZ-mTLS Manager 설치를 시작합니다 ===${NC}\n"

# 2. 환경 확인 (OS 및 사전 요구사항)
printf "${YELLOW}[1/7] 환경 호환성 검사 중...${NC}\n"

# 2-1. OS 버전 확인 (Ubuntu 24.04 이상)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    # 메이저 버전 추출 (예: 24.04 -> 24)
    MAJOR_VER=$(echo "$VERSION_ID" | cut -d. -f1)

    if [ "$NAME" != "Ubuntu" ] || [ -z "$MAJOR_VER" ] || [ "$MAJOR_VER" -lt 24 ]; then
        printf "${RED}[Error] 본 스크립트는 Ubuntu 24.04 LTS 이상 환경에서만 동작합니다.${NC}\n"
        printf "현재 감지된 환경: $PRETTY_NAME\n"
        exit 1
    fi
else
    printf "${RED}[Error] /etc/os-release 파일을 찾을 수 없습니다.${NC}\n"
    exit 1
fi

# 2-2. Nginx 및 Certbot 설치 여부 확인
if ! command -v nginx > /dev/null 2>&1 || ! command -v certbot > /dev/null 2>&1; then
    printf "${RED}[Error] Nginx 및 Certbot이 설치되어 있지 않습니다.${NC}\n"
    printf "${YELLOW}먼저 아래 명령어로 웹 서버와 SSL 도구를 설치하고 설정을 완료해주세요:${NC}\n"
    printf "  sudo apt update\n"
    printf "  sudo apt install -y nginx python3-certbot-nginx\n"
    printf "  # (선택) 도메인이 준비되었다면 SSL 발급 진행:\n"
    printf "  # sudo certbot --nginx\n"
    exit 1
fi

printf "${GREEN}환경 검사 완료.${NC}\n"

INSTALL_DIR="/opt/ez-mtls-manager"
REPO_URL="https://github.com/kreonet/ez-mtls-manager.git"

# APT 업데이트 함수 (7일 이내면 건너뜀)
update_apt_if_needed() {
    if [ -z "$(find /var/cache/apt/pkgcache.bin -mtime -7 2>/dev/null)" ]; then
        printf "${YELLOW}APT 캐시 업데이트 중...${NC}\n"
        apt update
    else
        echo "APT 캐시가 최신입니다 (7일 이내). 업데이트를 건너뜀니다."
    fi
}

# 로컬 설정 파일 확인 (디렉토리 이동 전)
LOCAL_SETTINGS_SRC=""
if [ -f "$(pwd)/settings.py" ]; then
    LOCAL_SETTINGS_SRC="$(pwd)/settings.py"
    printf "${GREEN}현재 디렉토리에서 settings.py를 발견했습니다. 설치 시 이를 EZmTLS Manager 설정 파일로 사용합니다.${NC}\n"
fi

# 로컬 비밀번호 파일 확인
LOCAL_STEP_CA_PASSWORD_FILE=""
if [ -f "$(pwd)/password.txt" ]; then
    LOCAL_STEP_CA_PASSWORD_FILE="$(pwd)/password.txt"
    printf "${GREEN}현재 디렉토리에서 password.txt를 발견했습니다. 설치 시 이를 STEP_CA_PASSWORD_FILE 로 사용합니다.${NC}\n"
fi

# 기존 설정값 미리 읽기 (settings.py가 있는 경우)
DEFAULT_CA_NAME="EZmTLS"
DEFAULT_VALID_DAYS=90

if [ -n "$LOCAL_SETTINGS_SRC" ]; then
    # pythonpath에 현재 디렉토리 추가하여 임포트
    DETECTED_CA_NAME=$(python3 -c "import sys; sys.path.append('$(pwd)'); import settings; print(getattr(settings, 'STEP_CA_NAME', ''))" 2>/dev/null)
    DETECTED_VALID_HOURS=$(python3 -c "import sys; sys.path.append('$(pwd)'); import settings; print(getattr(settings, 'STEP_CERT_VALID_HOURS', 0))" 2>/dev/null)
    
    if [ -n "$DETECTED_CA_NAME" ]; then
        printf "설정 파일에서 CA 이름을 감지했습니다: ${GREEN}$DETECTED_CA_NAME${NC}\n"
        DEFAULT_CA_NAME="$DETECTED_CA_NAME"
    fi
    
    if [ "$DETECTED_VALID_HOURS" -gt 0 ]; then
        DETECTED_DAYS=$((DETECTED_VALID_HOURS / 24))
        printf "설정 파일에서 인증서 유효기간을 감지했습니다: ${GREEN}${DETECTED_DAYS}일${NC}\n"
        DEFAULT_VALID_DAYS=$DETECTED_DAYS
    fi
fi

# 현재 디렉토리가 설치 경로가 아니라면 클론 또는 이동 처리
if [ "$(pwd)" != "$INSTALL_DIR" ]; then
    printf "${YELLOW}=== 설치 경로($INSTALL_DIR) 확인 중... ===${NC}\n"
    
    # git 설치 확인 (없으면 설치)
    if ! command -v git > /dev/null 2>&1; then
        printf "${YELLOW}Git 설치 중...${NC}\n"
        update_apt_if_needed
        apt install -y git
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        printf "${YELLOW}레포지토리 클론 중... ($REPO_URL)${NC}\n"
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        printf "${GREEN}설치 디렉토리가 이미 존재합니다. 해당 경로로 이동합니다.${NC}\n"
    fi
    
    cd "$INSTALL_DIR"
fi

# 3. 사용자 설정 입력
printf "${YELLOW}[2/9] 사용자 설정 입력${NC}\n"

# 3-1. CA 이름 입력
if [ -n "$STEP_CA_NAME" ]; then
    printf "환경 변수 STEP_CA_NAME이 감지되었습니다: ${GREEN}$STEP_CA_NAME${NC}\n"
else
    printf "Step CA의 이름을 입력하세요 (Enter 입력 시 기본값 '$DEFAULT_CA_NAME' 사용): "
    read USER_STEP_CA_NAME
    if [ -z "$USER_STEP_CA_NAME" ]; then
        export STEP_CA_NAME="$DEFAULT_CA_NAME"
    else
        export STEP_CA_NAME="$USER_STEP_CA_NAME"
    fi
fi

# 3-2. 도메인 입력 (FQDN)
DEFAULT_DOMAIN=$(hostname -f)
printf "Enter Domain Name (FQDN) for CRL/OCSP (Press Enter to use default '$DEFAULT_DOMAIN'): "
read USER_DOMAIN_NAME
if [ -z "$USER_DOMAIN_NAME" ]; then
    export DOMAIN_NAME="$DEFAULT_DOMAIN"
else
    export DOMAIN_NAME="$USER_DOMAIN_NAME"
fi

# 3-3. 인증서 유효기간 입력 (7~365일)
while true; do
    printf "인증서 유효기간(일)을 입력하세요 (7~365, Enter 입력 시 기본값 ${DEFAULT_VALID_DAYS}일): "
    read USER_VALID_DAYS
    
    if [ -z "$USER_VALID_DAYS" ]; then
        VALID_DAYS=$DEFAULT_VALID_DAYS
        break
    fi
    
    # POSIX compatible number check
    is_valid_number=0
    case "$USER_VALID_DAYS" in
        ""|*[!0-9]*) is_valid_number=0 ;;
        *) is_valid_number=1 ;;
    esac

    if [ "$is_valid_number" -eq 1 ] && [ "$USER_VALID_DAYS" -ge 7 ] && [ "$USER_VALID_DAYS" -le 365 ]; then
        VALID_DAYS=$USER_VALID_DAYS
        break
    else
        printf "${RED}[Error] 7에서 365 사이의 숫자를 입력해주세요.${NC}\n"
    fi
done

# 시간을 시간(Hour) 단위로 변환
CERT_VALID_HOURS=$((VALID_DAYS * 24))
printf "인증서 유효기간이 ${GREEN}${VALID_DAYS}일 (${CERT_VALID_HOURS}시간)${NC}으로 설정됩니다.\n"


# 4. 필수 패키지 설치
printf "${YELLOW}[3/9] 시스템 패키지 업데이트 및 설치 중...${NC}\n"
update_apt_if_needed
apt install -y curl vim git gpg ca-certificates libssl-dev

# 5. SmallStep CA 설치
printf "${YELLOW}[4/9] SmallStep CA 설치 중...${NC}\n"
if ! command -v step > /dev/null 2>&1; then
    curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc
    echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' | tee /etc/apt/sources.list.d/smallstep.list
    apt update
    apt install -y step-cli step-ca
else
    echo "SmallStep CA가 이미 설치되어 있습니다."
fi

# 6. 설정 파일 준비
printf "${YELLOW}[5/9] 설정 파일 준비 (settings.py)...${NC}\n"

# 6-1. settings.py 확보
if [ -n "$LOCAL_SETTINGS_SRC" ] && [ -f "$LOCAL_SETTINGS_SRC" ]; then
    printf "${GREEN}감지된 로컬 설정 파일을 사용합니다: $LOCAL_SETTINGS_SRC${NC}\n"
    cp "$LOCAL_SETTINGS_SRC" "$INSTALL_DIR/settings.py"
elif [ -f "$INSTALL_DIR/settings.py.example" ]; then
    echo "기본 예제 파일로부터 settings.py를 생성합니다."
    cp "$INSTALL_DIR/settings.py.example" "$INSTALL_DIR/settings.py"
else
    printf "${RED}[Warning] settings.py.example 파일을 찾을 수 없습니다.${NC}\n"
fi

# 6-2. DB 비밀번호 처리
# 현재 파일의 DB_PASSWORD 값을 읽음
CURRENT_DB_PASS=$(python3 -c "import sys; sys.path.append('$INSTALL_DIR'); import settings; print(getattr(settings, 'DB_PASSWORD', ''))" 2>/dev/null)

is_default_db_pass=0
case "$CURRENT_DB_PASS" in
    CHANGE_ME*) is_default_db_pass=1 ;;
esac

if [ -z "$CURRENT_DB_PASS" ] || [ "$is_default_db_pass" -eq 1 ]; then
    echo "새로운 DB 비밀번호를 생성합니다."
    DB_PASS=$(openssl rand -hex 12)
    sed -i "s/DB_PASSWORD = .*/DB_PASSWORD = \"${DB_PASS}\"/" "$INSTALL_DIR/settings.py"
else
    echo "기존 DB 비밀번호를 유지합니다."
    DB_PASS="$CURRENT_DB_PASS"
fi

# 6-3. Secret Key 처리
# 현재 파일의 FLASK_SECRET_KEY 값을 읽음
CURRENT_FLASK_SECRET_KEY=$(python3 -c "import sys; sys.path.append('$INSTALL_DIR'); import settings; print(getattr(settings, 'FLASK_SECRET_KEY', ''))" 2>/dev/null)

is_default_secret_key=0
case "$CURRENT_FLASK_SECRET_KEY" in
    CHANGE_ME*) is_default_secret_key=1 ;;
esac

if [ -z "$CURRENT_FLASK_SECRET_KEY" ] || [ "$is_default_secret_key" -eq 1 ]; then
    echo "새로운 Flask Secret Key를 생성합니다."
    NEW_SECRET_KEY=$(openssl rand -hex 32)
    # 기존 키가 있으면 교체, 없으면 추가
    if grep -q "FLASK_SECRET_KEY =" "$INSTALL_DIR/settings.py"; then
        sed -i "s/FLASK_SECRET_KEY = .*/FLASK_SECRET_KEY = \"${NEW_SECRET_KEY}\"/" "$INSTALL_DIR/settings.py"
    else
        echo "FLASK_SECRET_KEY = \"${NEW_SECRET_KEY}\"" >> "$INSTALL_DIR/settings.py"
    fi
fi

# 6-4. 유효기간 및 CA 이름 설정 업데이트 (공통)
if [ -f "$INSTALL_DIR/settings.py" ]; then
    sed -i "s/^CERT_VALID_HOURS = .*/CERT_VALID_HOURS = ${CERT_VALID_HOURS}/" "$INSTALL_DIR/settings.py"
    sed -i "s/^STEP_CA_NAME = .*/STEP_CA_NAME = \"${STEP_CA_NAME}\"/" "$INSTALL_DIR/settings.py"
fi


# 7. 데이터베이스 설치 및 초기화
printf "${YELLOW}[6/9] 데이터베이스(MariaDB) 설치 및 초기화 중...${NC}\n"
apt install -y mariadb-server

# 7-1. DB 사용자 및 보안 설정
echo "데이터베이스 사용자(ezmtls)를 설정합니다."
# 사용자 생성 (없으면 생성)
sudo mariadb -e "CREATE USER IF NOT EXISTS 'ezmtls'@'localhost' IDENTIFIED BY '${DB_PASS}';" >/dev/null 2>&1
# 비밀번호 동기화 (기존 사용자가 있어도 settings.py와 일치되도록 변경)
sudo mariadb -e "ALTER USER 'ezmtls'@'localhost' IDENTIFIED BY '${DB_PASS}';" >/dev/null 2>&1
# 권한 부여
sudo mariadb -e "GRANT ALL PRIVILEGES ON \`ezmtls\`.* TO 'ezmtls'@'localhost';" >/dev/null 2>&1
sudo mariadb -e "FLUSH PRIVILEGES;" >/dev/null 2>&1

# 7-2. DB 스키마 적용
if [ -f "$INSTALL_DIR/init_db.sql" ]; then
    sudo mariadb < "$INSTALL_DIR/init_db.sql"
    echo "데이터베이스 스키마가 적용되었습니다."
else
        printf "${RED}[Warning] init_db.sql 파일을 찾을 수 없어 DB 초기화를 건너뜁니다.${NC}\n"
fi

# 8. Python 및 애플리케이션 의존성 설치
printf "${YELLOW}[7/9] Python 패키지 설치 중...${NC}\n"
apt install -y python3-flask python3-flask-login python3-flask-sqlalchemy \
               python3-pymysql python3-flaskext.wtf python3-authlib \
               python3-dotenv python3-requests python3-cryptography \
               gunicorn python3-gunicorn

# 8. 서비스 계정 생성
printf "${YELLOW}[7/9] 서비스 계정(flask) 생성 중...${NC}\n"
if id "flask" > /dev/null 2>&1; then
    echo "flask 계정이 이미 존재합니다."
else
    useradd -m -s /bin/bash flask
    echo "flask 계정을 생성했습니다."
fi

# 9. Step CA 초기화
printf "${YELLOW}[8/9] Step CA 초기화 및 설정${NC}\n"

# (Prompt Logic removed - done in Step 3)

CA_DIR="/opt/ez-mtls-manager/step-ca"
STEP_CA_PASSWORD_FILE="$CA_DIR/password.txt"
SVC_USER="flask"
SVC_GROUP="flask"

echo "=== Step CA 초기화를 시작합니다 ($CA_DIR) ==="

# 9-1. 디렉토리 생성
if [ -d "$CA_DIR" ]; then
    echo "디렉토리 $CA_DIR 가 이미 존재합니다. 생성을 건너뜁니다."
else
    mkdir -p "$CA_DIR"
    echo "디렉토리 $CA_DIR 를 생성했습니다."
fi

# 9-2. 패스워드 파일 생성
if [ -f "$STEP_CA_PASSWORD_FILE" ]; then
    echo "비밀번호 파일이 이미 존재합니다."
elif [ -n "$LOCAL_STEP_CA_PASSWORD_FILE" ] && [ -f "$LOCAL_STEP_CA_PASSWORD_FILE" ]; then
    echo "감지된 로컬 비밀번호 파일을 복사합니다: $LOCAL_STEP_CA_PASSWORD_FILE"
    cp "$LOCAL_STEP_CA_PASSWORD_FILE" "$STEP_CA_PASSWORD_FILE"
    chmod 600 "$STEP_CA_PASSWORD_FILE"
else
    echo "새 비밀번호를 생성하는 중..."
    openssl rand -base64 32 > "$STEP_CA_PASSWORD_FILE"
    chmod 600 "$STEP_CA_PASSWORD_FILE"
fi

if [ -f "$INSTALL_DIR/settings.py" ]; then
    sed -i "s/STEP_CA_NAME = .*/STEP_CA_NAME = \"${STEP_CA_NAME}\"/" "$INSTALL_DIR/settings.py"
fi

# 9-3. CA 초기화
if [ -f "$CA_DIR/config/ca.json" ]; then
    echo "CA가 이미 초기화된 것으로 보입니다(ca.json 존재). 초기화를 건너뜁니다."
else
    echo "'step ca init' 실행 중..."
    
    export STEPPATH="$CA_DIR"
    
    step ca init \
        --name "$STEP_CA_NAME" \
        --dns "$DOMAIN_NAME" \
        --dns "localhost" \
        --address ":8443" \
        --provisioner "admin" \
        --password-file "$STEP_CA_PASSWORD_FILE" \
        --provisioner-password-file "$STEP_CA_PASSWORD_FILE" \
        --deployment-type standalone
        
    echo "CA 초기화가 완료되었습니다."
    
    # 9-4. 인증서 템플릿 생성 (CDP 포함)
    echo "인증서 템플릿 생성 (leaf.tpl)..."
    mkdir -p "$CA_DIR/templates"
    cat <<EOF > "$CA_DIR/templates/leaf.tpl"
{
    "subject": {{ toJson .Subject }},
    "sans": {{ toJson .SANs }},
{{- if .Token }}
    "token": "{{ .Token }}",
{{- end }}
    "keyUsage": ["digitalSignature", "keyEncipherment"],
    "extKeyUsage": ["serverAuth", "clientAuth"],
    "crlDistributionPoints": ["https://${DOMAIN_NAME}/crl"]
}
EOF

    # 9-5. ca.json 패치 (인증서 유효기간 및 템플릿 설정)
    echo "ca.json 패치 중 (인증서 유효기간, CRL, 템플릿 설정)..."
    # Python 스크립트 내 변수 주입을 위해 환경변수 export
    export PY_CERT_VALID_HOURS="${CERT_VALID_HOURS}h"
    
    python3 -c '
import json
import os

config_path = "/opt/ez-mtls-manager/step-ca/config/ca.json"
cert_duration = os.environ.get("PY_CERT_VALID_HOURS", "2160h")
default_duration = "720h" # Default 30 days

if os.path.exists(config_path):
    with open(config_path, "r") as f:
        data = json.load(f)
    
    updated = False

    # 1. Enable CRL (Duration 30 days)
    if "crl" not in data:
        data["crl"] = {"enabled": True, "generateOnRevoke": True, "duration": "720h"}
        updated = True
    else:
        # Update existing CRL settings
        if not data["crl"].get("enabled"):
            data["crl"]["enabled"] = True
            updated = True
        if not data["crl"].get("generateOnRevoke"):
            data["crl"]["generateOnRevoke"] = True
            updated = True
        if data["crl"].get("duration") != "720h":
            data["crl"]["duration"] = "720h"
            updated = True

    # 2. Find admin provisioner and add claims & template
    if "authority" in data and "provisioners" in data["authority"]:
        for prov in data["authority"]["provisioners"]:
            if prov["name"] == "admin":
                # Claims
                prov["claims"] = {
                    "enableSSHCA": True,
                    "maxTLSCertDuration": cert_duration,
                    "defaultTLSCertDuration": default_duration
                }
                # Template
                prov["options"] = {
                    "x509": {
                        "templateFile": "templates/leaf.tpl"
                    }
                }
                updated = True
    
    if updated:
        with open(config_path, "w") as f:
            json.dump(data, f, indent=4)
        print(f"ca.json 업데이트 성공 (CRL 30일, Templates 적용, Duration: {cert_duration})")
    else:
        print("ca.json 변경 사항 없음.")
'
fi

# 9-6. 권한 설정
echo "사용자 권한 설정 중 ($SVC_USER:$SVC_GROUP)..."
mkdir -p "$INSTALL_DIR/certs"
touch "$INSTALL_DIR/app.log"

# 앱 권한 설정
chown -R $SVC_USER:$SVC_GROUP "$INSTALL_DIR/certs"
chown -R $SVC_USER:$SVC_GROUP "$INSTALL_DIR/app.log"

# Step CA 권한 설정 (서비스가 flask 계정으로 실행되므로 필수)
chown -R $SVC_USER:$SVC_GROUP "$CA_DIR"

# settings.py 보안 강화 (소유자는 root, 그룹은 flask 읽기 전용)
if [ -f "$INSTALL_DIR/settings.py" ]; then
    chown root:$SVC_GROUP "$INSTALL_DIR/settings.py"
    chmod 640 "$INSTALL_DIR/settings.py"
fi

# 10. 서비스 등록 및 시작
printf "${YELLOW}[9/9] 서비스 등록 및 시작 중...${NC}\n"
cp deploy/ez-mtls.service /etc/systemd/system/
cp deploy/step-ca.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now step-ca
systemctl enable --now ez-mtls

printf "${GREEN}=== 설치가 완료되었습니다! ===${NC}\n"
printf "
다음 단계:
1. ${YELLOW}설정 파일 검토${NC}: '/opt/ez-mtls-manager/settings.py' 확인
2. ${YELLOW}Nginx 설정${NC}: 'deploy/nginx.conf.example'을 참고하여 '/etc/nginx/sites-available/'에 설정 추가
   (이미 설치된 Nginx와 Certbot을 사용하여 도메인을 연결하세요.)

서비스 상태 확인:
systemctl status step-ca
systemctl status ez-mtls
\n"
