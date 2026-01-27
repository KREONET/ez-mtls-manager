# ez-mtls-manager

[🇰🇷 한국어 버전 설명 문서 (Korean Version)](README.ko.md)

**ez-mtls-manager** is a web-based system that allows users to issue and manage mTLS client certificates (`.p12`) themselves.

## Core Features

### 1. Authentication & User Management

- **Multi-IdP Support:** Supports OIDC ([KAFE](https://www.kafe.or.kr), [Auth0](https://auth0.com)) and [Atlassian Crowd](https://www.atlassian.com/software/crowd) as authentication sources, allowing unified management of internal/external users.
- **Multi-language Support:** Supports Korean and English, automatically switching based on browser language settings.

### 2. Self-Service Certificate Issuance

- **Easy Issuance:** Users can set their own passwords, generate `.p12` certificates, and download them.
- **Lifecycle Management:** The Renew button becomes active 7 days before certificate expiration.

### 3. Admin Dashboard & Auditing

- **Audit Logs:** Key actions such as certificate issuance, revocation, and logins are permanently recorded and can be viewed.

## Requirements

- **OS:** Ubuntu 24.04 LTS (Noble Numbat) or higher recommended

## Installation

On an Ubuntu 24.04 server, run the following command to automatically proceed with all installation steps including system packages, DB, CA, and application settings. Run as root:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/kreonet/ez-mtls-manager/main/deploy/install.sh)"
```

During script execution, you will be prompted for:
- **Step CA Name:** (Default: EZmTLS)
- **Certificate Validity:** (Default: 90 days)
- If `settings.py` or `password.txt` from a previous installation exists, it will be automatically detected and reused.

## Post-Installation

After the installation script completes, perform the following steps:

1.  **Edit Configuration:**
    Open `/opt/ez-mtls-manager/settings.py` and enter the `CROWD_...` or `OIDC_...` information appropriate for your environment.
    ```sh
    sudo vi /opt/ez-mtls-manager/settings.py
    ```
2.  **Nginx Connection:**
    Configure the reverse proxy referring to `deploy/nginx.conf.example`.
    (Use the existing Nginx and Certbot.)
    ```sh
    sudo cp /opt/ez-mtls-manager/deploy/nginx.conf.example /etc/nginx/sites-available/ez-mtls
    # Edit content (domain, etc.)
    sudo ln -s /etc/nginx/sites-available/ez-mtls /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    ```
3.  **Restart Service:**
    If you changed the settings, restart the service.
    ```sh
    sudo systemctl restart ez-mtls
    ```

# Manual

For detailed usage instructions, please refer to the manual - https://wiki.kreonet.net/ezmtls/

## License

This project is licensed under the **Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)**.
You are free to share and adapt the material for **non-commercial purposes only**, as long as you give appropriate credit.
See the [LICENSE](LICENSE) file for details.
