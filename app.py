from flask import Flask, request, session, g
import settings
import logging
import os
import socket
import urllib3.util.connection as urllib3_cn
from werkzeug.middleware.proxy_fix import ProxyFix
from extensions import db, login_manager
from models import User
from messages import MESSAGES
from routes import main_bp, auth_bp, user_bp, admin_bp
from step_client import StepClient
from auth_oidc import OIDCAuthProvider
from auth_crowd import CrowdAuthProvider
import json
import sys
import re


def configure_logging(app):
    log_file = os.path.join(
        os.path.dirname(
            os.path.abspath(__file__)),
        'app.log')
    log_level = getattr(logging, settings.LOGLEVEL.upper(), logging.INFO)
    logging.basicConfig(
        filename=log_file,
        level=log_level,
        format='%(asctime)s %(levelname)s: %(message)s',
        force=True)

    # Enable Authlib & Requests logging based on LOGLEVEL
    logging.getLogger("authlib").setLevel(log_level)
    logging.getLogger("requests").setLevel(log_level)
    logging.getLogger("urllib3").setLevel(log_level)


def configure_services(app):
    auth_providers = {}

    # Initialize OIDC if configured
    if settings.OIDC_CLIENT_ID and settings.OIDC_DOMAIN:
        app.config["OIDC_CLIENT_ID"] = settings.OIDC_CLIENT_ID
        app.config["OIDC_CLIENT_SECRET"] = settings.OIDC_CLIENT_SECRET
        app.config["OIDC_DOMAIN"] = settings.OIDC_DOMAIN
        auth_providers["oidc"] = OIDCAuthProvider(app)

    # Initialize Crowd if configured
    if settings.CROWD_BASE_URL:
        auth_providers["crowd"] = CrowdAuthProvider(
            settings.CROWD_BASE_URL,
            settings.CROWD_APP_NAME,
            settings.CROWD_APP_PASSWORD
        )

    app.auth_providers = auth_providers

    # Initialize StepCA Client
    step_client = StepClient(
        step_path="/usr/bin/step",
        ca_url="https://localhost:8443",
        root_ca_path=settings.STEP_ROOT_CA,
        provisioner_password_file=settings.STEP_CA_PASSWORD_FILE
    )
    app.step_client = step_client


def validate_ca_config():
    """
    Validates consistency between Step CA config (ca.json) and App settings.
    If CA's maxTLSCertDuration is shorter than App's STEP_CERT_VALID_HOURS, abort startup.
    """
    # settings.STEP_CA_PATH example: "/opt/ez-mtls-manager/step-ca"
    ca_config_path = os.path.join(settings.STEP_CA_PATH, "config/ca.json")

    if not os.path.exists(ca_config_path):
        msg = f"FATAL: CA config not found at {
            ca_config_path}. Cannot validate configuration."
        logging.critical(msg)
        print(msg, file=sys.stderr)
        sys.exit(1)

    try:
        with open(ca_config_path, "r") as f:
            data = json.load(f)

        max_duration_str = "24h"  # Step CA Default

        # Find 'admin' provisioner
        found_provisioner = False
        if "authority" in data and "provisioners" in data["authority"]:
            for prov in data["authority"]["provisioners"]:
                if prov["name"] == "admin":
                    claims = prov.get("claims", {})
                    max_duration_str = claims.get(
                        "maxTLSCertDuration", max_duration_str)
                    found_provisioner = True
                    break

        if not found_provisioner:
            # Admin provisioner not found. Assuming default (24h).
            logging.warning(
                "Could not find 'admin' provisioner in ca.json. Assuming default duration.")

        # Parse duration (e.g. "2160h" -> 2160)
        match = re.match(r"(\d+)h", max_duration_str)
        if match:
            max_hours = int(match.group(1))
        else:
            msg = f"FATAL: Could not parse maxTLSCertDuration: {
                max_duration_str}"
            logging.critical(msg)
            print(msg, file=sys.stderr)
            sys.exit(1)

        needed_hours = settings.STEP_CERT_VALID_HOURS

        if max_hours != needed_hours:
            msg = (f"FATAL: CA configuration mismatch! "
                   f"CA maxTLSCertDuration ({max_hours}h) does NOT match "
                   f"settings.STEP_CERT_VALID_HOURS ({needed_hours}h). "
                   f"Configuration must be strictly synchronized. "
                   f"Please update ca.json and restart Step CA.")
            logging.critical(msg)
            print(msg, file=sys.stderr)
            sys.exit(1)

        logging.info(f"Config Check Passed: CA Max={
                     max_hours}h == App Req={needed_hours}h")

    except Exception as e:
        msg = f"FATAL: Failed to validate CA config: {e}"
        logging.critical(msg)
        print(msg, file=sys.stderr)
        sys.exit(1)


def allowed_gai_family():
    return socket.AF_INET


def create_app(config_object=settings):
    app = Flask(__name__)
    app.config.from_object(config_object)
    app.secret_key = settings.FLASK_SECRET_KEY

    # IPv4 enforcement
    urllib3_cn.allowed_gai_family = allowed_gai_family

    configure_logging(app)

    # Init Extensions
    app.config["SQLALCHEMY_DATABASE_URI"] = settings.SQLALCHEMY_DATABASE_URI
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = settings.SQLALCHEMY_TRACK_MODIFICATIONS
    db.init_app(app)

    login_manager.init_app(app)
    login_manager.login_view = "auth.login_selection"

    # Middleware
    app.wsgi_app = ProxyFix(
        app.wsgi_app,
        x_for=1,
        x_proto=1,
        x_host=1,
        x_prefix=1)

    # Services
    configure_services(app)

    # Validation
    validate_ca_config()

    # Blueprints
    app.register_blueprint(main_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(user_bp)
    app.register_blueprint(admin_bp)

    # Hooks
    @app.before_request
    def detect_language():
        lang = request.args.get("lang")
        if lang:
            session["lang"] = lang
        else:
            lang = session.get("lang")

        if not lang:
            # Detect language from header
            accept_lang = request.headers.get("Accept-Language", "")
            if "ko" in accept_lang:
                lang = "ko"
            else:
                lang = "en"

        # Default to EN if not supported
        if lang not in MESSAGES:
            lang = "en"

        g.lang = lang
        g.trans = MESSAGES[lang]

    @app.context_processor
    def inject_trans():
        return dict(
            t=g.trans,
            lang=g.lang,
            manual_url=app.config.get("MANUAL_URL", "#")
        )

    @app.template_filter('parse_ua')
    def parse_ua(ua_string):
        if not ua_string:
            return ""

        os_name = "Unknown OS"
        browser_name = "Unknown Browser"

        ua = ua_string.lower()

        # Detect OS
        if "windows" in ua:
            os_name = "Windows"
        elif "macintosh" in ua or "mac os" in ua:
            os_name = "macOS"
        elif "linux" in ua:
            os_name = "Linux"
        elif "android" in ua:
            os_name = "Android"
        elif "iphone" in ua or "ipad" in ua:
            os_name = "iOS"

        # Detect Browser
        if "edg/" in ua or "edge/" in ua:
            browser_name = "Edge"
        elif "chrome/" in ua:
            browser_name = "Chrome"
        elif "firefox/" in ua:
            browser_name = "Firefox"
        elif "safari/" in ua and "chrome" not in ua:
            browser_name = "Safari"
        elif "whale/" in ua:
            browser_name = "Whale"

        return f"{os_name} / {browser_name}"

    return app

# User Loader logic (linked to LoginManager)


@login_manager.user_loader
def load_user(user_id):
    # Restore user info from session
    email = session.get("user_email")
    display_name = session.get("user_display_name")
    groups = session.get("user_groups")
    idp = session.get("auth_method")
    cn = session.get("user_cn")
    return User(user_id, email, display_name, groups, idp, cn)


# Entry point for Gunicorn
app = create_app()

if __name__ == "__main__":
    with app.app_context():
        try:
            db.create_all()
            logging.info("Database tables verified/created.")
        except Exception as e:
            logging.error(f"DB Initialization failed: {e}")

    app.run(debug=(settings.LOGLEVEL == "DEBUG"))
