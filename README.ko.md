# ez-mtls-manager

**ez-mtls-manager**는 사용자가 직접 mTLS 클라이언트 인증서(`.p12`)를 발급하고 관리할 수 있는 웹 기반 시스템입니다.

## 주요 기능

### 1. 인증 및 사용자 관리

- **Multi-IdP 지원:** 인증 소스로 OIDC([KAFE](https://www.kafe.or.kr), [Auth0](https://auth0.com)) 및 [Atlassian Crowd](https://www.atlassian.com/software/crowd)를 지원하며, 내부/외부 사용자 통합 관리가 가능합니다.
- **다국어 지원:** 한국어와 영어를 지원하며, 브라우저 언어 설정에 따라 자동으로 전환됩니다.

### 2. 셀프 서비스 인증서 발급

- **간편한 발급:** 사용자가 직접 비밀번호를 설정하고 `.p12` 인증서를 생성하여 다운로드할 수 있습니다.
- **수명 주기 관리:** 인증서 만료 7일 전부터 갱신(Renew) 버튼이 활성화됩니다.

### 3. 관리자 대시보드 및 감사

- **감사 로그:** 인증서 발급, 폐기, 로그인 등 주요 작업 이력을 영구적으로 기록하고 조회할 수 있습니다.

## 요구 사항

- **OS:** Ubuntu 24.04 LTS (Noble Numbat) 이상 권장

## 설치

Ubuntu 24.04 서버에서 다음 명령어를 실행하면 시스템 패키지, DB, CA, 애플리케이션 설정 등 모든 설치 과정이 자동으로 진행됩니다. 루트 권한으로 다음을 실행합니다.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/kreonet/ez-mtls-manager/main/deploy/install_ko.sh)"
```

스크립트 실행 중 다음 정보를 입력하게 됩니다:
- **Step CA 이름:** (기본값: EZmTLS)
- **인증서 유효기간:** (기본값: 90일)
- 이전에 생성한 `settings.py`나 `password.txt`가 있다면 자동으로 감지하여 재사용합니다.

## 설치 후 마무리

설치 스크립트 완료 후 다음 절차를 수행하세요.

1. **설정 파일 수정:**
    `/opt/ez-mtls-manager/settings.py`를 열어 `CROWD_...` 또는 `OIDC_...` 정보를 실제 환경에 맞게 입력합니다.
    ```sh
    sudo vi /opt/ez-mtls-manager/settings.py
    ```
2. **Nginx 연결:**
    `deploy/nginx.conf.example`을 참고하여 리버스 프록시를 설정합니다.
    (이미 설치된 Nginx와 Certbot을 활용하세요.)
    ```sh
    sudo cp /opt/ez-mtls-manager/deploy/nginx.conf.example /etc/nginx/sites-available/ez-mtls
    # 내용 수정 (도메인 등)
    sudo ln -s /etc/nginx/sites-available/ez-mtls /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    ```
3. **서비스 재시작:**
    설정을 변경했다면 서비스를 재시작합니다.
    ```sh
    sudo systemctl restart ez-mtls
    ```

# 설명서

자세한 사용 설명은 https://wiki.kreonet.net/ezmtls/ 을 참고 바랍니다.

## 라이선스 (License)

이 프로젝트는 **Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)** 라이선스 하에 배포됩니다.
**비상업적 용도**에 한하여 자유롭게 공유 및 변경할 수 있으며, 적절한 출처를 표시해야 합니다.
자세한 내용은 [LICENSE](LICENSE) 파일을 참고하세요.
