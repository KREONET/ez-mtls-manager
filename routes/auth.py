from flask import Blueprint, render_template, redirect, url_for, session, request, g, flash, current_app
from flask_login import login_user, login_required, logout_user, current_user
import logging
import settings
from models import User, AuditLog
import urllib.parse

bp = Blueprint('auth', __name__)


@bp.route("/login")
def login_selection():
    if current_user.is_authenticated:
        return redirect(url_for("auth.protected"))

    return render_template("login.html")


@bp.route("/login/oidc")
def login_oidc():
    if current_user.is_authenticated:
        return redirect(url_for("auth.protected"))

    provider = current_app.auth_providers.get("oidc")
    if not provider:
        return "OIDC Provider not configured.", 500
    return provider.login()


@bp.route("/login/crowd", methods=["GET", "POST"])
def login_crowd():
    if current_user.is_authenticated:
        return redirect(url_for("auth.protected"))

    provider = current_app.auth_providers.get("crowd")
    if not provider:
        return "Crowd Provider not configured.", 500

    if request.method == "GET":
        return render_template("login.html")

    username = request.form.get("username")
    password = request.form.get("password")

    ok, token = provider.authenticate(username, password, request.remote_addr)
    if not ok:
        AuditLog.log(
            idp=settings.CROWD_IDP_NAME,
            user_name=username,
            email=None,
            common_name=username,
            action="LOGIN_FAIL",
            detail=settings.CROWD_IDP_NAME,
            ip_address=request.remote_addr,
            user_agent=request.user_agent.string)
        flash(g.trans.get("flash_login_fail"))
        return redirect(url_for("auth.login_crowd"))

    # Create local session with Flask-Login on Crowd auth success
    # Also fetch full user details
    details = provider.get_user_details(username)
    email = None
    display_name = None
    cn = None
    if details:
        email = details.get("email")
        display_name = details.get("display-name")

        # Default CN is email
        cn = email

        # Custom CN logic for Shared Accounts
        if email and email in settings.SHARED_EMAIL_ACCOUNTS:
            # Use transformation function from settings
            cn = settings.generate_cn_for_shared_email_user(username)
            logging.info(
                f"[CROWD] Shared account detected ({email}). "
                f"Keeping original email for notifications, but set CN to: {cn}")

        # Save important info to session (for load_user)
        session["user_email"] = email
        session["user_display_name"] = display_name
        session["user_cn"] = cn

    # Fetch User Groups
    groups = provider.get_user_groups(username)
    session["user_groups"] = groups
    session["auth_method"] = settings.CROWD_IDP_NAME

    user = User(username, email, display_name, groups, cn=cn)
    login_user(user)
    AuditLog.log(
        idp=settings.CROWD_IDP_NAME,
        user_name=display_name,
        email=user.email,
        common_name=user.cn,
        action="LOGIN",
        detail=None,
        ip_address=request.remote_addr,
        user_agent=request.user_agent.string)

    return redirect(url_for("auth.protected"))


@bp.route("/callback")
def callback():
    provider = current_app.auth_providers.get("oidc")
    if not provider:
        return "OIDC Provider not configured.", 500

    try:
        user_info = provider.authorize()
    except Exception as e:
        logging.error(f"[OIDC] callback error: {e}")
        flash(g.trans.get("flash_oidc_error"))
        return redirect(url_for("auth.login_selection"))

    # OIDC Info Mapping
    username = user_info.get("preferred_username") or user_info.get(
        "email") or user_info.get("sub")
    email = user_info.get("email")
    display_name = user_info.get("name") or user_info.get("nickname")

    # Group info depends on OIDC provider settings (Handling as empty list or
    # custom claim check needed)
    groups = user_info.get("https://any-namespace/groups", [])  # Example

    # Determine CN (Email priority)
    cn = email if email else username

    session["user_email"] = email
    session["user_display_name"] = display_name
    session["user_groups"] = groups
    session["user_cn"] = cn
    session["auth_method"] = settings.OIDC_IDP_NAME

    user = User(username, email, display_name, groups, cn=cn)
    login_user(user)
    AuditLog.log(
        idp=settings.OIDC_IDP_NAME,
        user_name=display_name,
        email=user.email,
        common_name=user.cn,
        action="LOGIN",
        detail=None,
        ip_address=request.remote_addr,
        user_agent=request.user_agent.string)

    return redirect(url_for("auth.protected"))


@bp.route("/protected")
@login_required
def protected():
    return redirect(url_for("user.cert"))


@bp.route("/logout")
@login_required
def logout():
    auth_method = session.get("auth_method")
    if current_user.is_authenticated:
        AuditLog.log(
            idp=current_user.idp,
            user_name=current_user.display_name,
            email=current_user.email,
            common_name=current_user.cn,
            action="LOGOUT",
            detail=None,
            ip_address=request.remote_addr,
            user_agent=request.user_agent.string)
    logout_user()

    if auth_method == settings.OIDC_IDP_NAME and settings.OIDC_DOMAIN and settings.OIDC_CLIENT_ID:
        return_to = url_for("main.index", _external=True)

        params = {
            "returnTo": return_to,
            "client_id": settings.OIDC_CLIENT_ID
        }
        oidc_logout_url = f"https://{settings.OIDC_DOMAIN}/v2/logout?{
            urllib.parse.urlencode(params)}"
        logging.info(f"[OIDC] Redirecting to logout: {oidc_logout_url}")
        return redirect(oidc_logout_url)

    return redirect(url_for("main.index"))
