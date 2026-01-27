from flask import Blueprint, render_template, redirect, url_for, request, g, flash, current_app, send_file
from flask_login import login_required, current_user
import logging
import os
import re
from datetime import datetime, timedelta
import settings
from models import AuditLog, Certificate
from extensions import db

bp = Blueprint('user', __name__)


@bp.route("/cert")
@login_required
def cert():
    # Show active certificates
    certs = Certificate.query.filter_by(
        common_name=current_user.cn).order_by(
        Certificate.issued_at.desc()).all()

    # Check creation allowance (disable if valid cert > 7 days remaining)
    can_create = True
    active_cert = Certificate.query.filter_by(
        common_name=current_user.cn,
        status='valid').order_by(
        Certificate.expires_at.desc()).first()

    if active_cert:
        remaining = active_cert.expires_at - datetime.now()
        if remaining > timedelta(days=7):
            can_create = False

    is_admin = current_user.is_admin

    return render_template("cert.html", certs=certs,
                           can_create=can_create, is_admin=is_admin)


@bp.route("/log")
@login_required
def user_log():
    page = request.args.get('page', 1, type=int)
    q = request.args.get('q', '', type=str)

    query = AuditLog.query.filter_by(common_name=current_user.cn)

    if q:
        search = f"%{q}%"
        query = query.filter(
            (AuditLog.idp.ilike(search)) |
            (AuditLog.user_name.ilike(search)) |
            (AuditLog.common_name.ilike(search)) |
            (AuditLog.email.ilike(search)) |
            (AuditLog.action.ilike(search)) |
            (AuditLog.detail.ilike(search)) |
            (AuditLog.ip_address.ilike(search))
        )

    pagination = query.order_by(
        AuditLog.logged_at.desc()).paginate(
        page=page, per_page=100, error_out=False)

    return render_template("log.html", pagination=pagination, q=q)


@bp.route("/certificate/create", methods=["POST"])
@login_required
def create_certificate():
    p12_password = request.form.get("p12_password")

    # Password Complexity: Minimum 10 chars, Upper, Lower, Digit
    if not p12_password or len(p12_password) < 10:
        flash(g.trans.get("flash_pwd_min_len"))
        return redirect(url_for("user.cert"))
    if not re.search(r"[A-Z]", p12_password):
        flash(g.trans.get("flash_pwd_upper"))
        return redirect(url_for("user.cert"))
    if not re.search(r"[a-z]", p12_password):
        flash(g.trans.get("flash_pwd_lower"))
        return redirect(url_for("user.cert"))
    if not re.search(r"\d", p12_password):
        flash(g.trans.get("flash_pwd_digit"))
        return redirect(url_for("user.cert"))

    # Re-check allowance for safety
    active_cert = Certificate.query.filter_by(
        common_name=current_user.cn,
        status='valid').order_by(
        Certificate.expires_at.desc()).first()
    if active_cert:
        remaining = active_cert.expires_at - datetime.now()
        if remaining > timedelta(days=7):
            flash(g.trans.get("flash_cert_valid_exists"))
            return redirect(url_for("user.cert"))

    # Generate unique CN
    cn = current_user.cn

    try:
        # Issue P12
        p12_data = current_app.step_client.issue_p12(
            cn, p12_password, valid_hours=settings.STEP_CERT_VALID_HOURS)

    except Exception as e:
        logging.error(f"Cert generation failed: {e}")
        flash(f"{g.trans.get('flash_cert_create_error')}{str(e)}")
        return redirect(url_for("user.cert"))

    # Unpack p12 data
    p12_content, serial, not_after_str, not_before_str, sha1, sha256, crt_pem = p12_data

    # expires_at_str format: "2025-12-30T03:40:25Z"
    not_before = datetime.fromisoformat(not_before_str.replace("Z", "+00:00"))
    not_after = datetime.fromisoformat(not_after_str.replace("Z", "+00:00"))

    cert_entry = Certificate(
        idp=current_user.idp,
        user_name=current_user.display_name,
        email=current_user.email,
        common_name=cn,
        serial=serial,
        fingerprint_sha1=sha1,
        fingerprint_sha256=sha256,
        issued_at=not_before,
        expires_at=not_after
    )
    db.session.add(cert_entry)
    db.session.commit()

    # Save P12 and CRT files
    cert_dir = os.path.join(
        "/opt/ez-mtls-manager/certs", cn, str(cert_entry.id))
    os.makedirs(cert_dir, mode=0o700, exist_ok=True)

    p12_path = os.path.join(cert_dir, "client.p12")
    with open(p12_path, "wb") as f:
        f.write(p12_content)

    crt_path = os.path.join(cert_dir, "client.crt")
    with open(crt_path, "w") as f:
        f.write(crt_pem)

    flash(g.trans.get("flash_cert_create_success"))
    AuditLog.log(
        idp=current_user.idp,
        user_name=current_user.display_name,
        email=current_user.email,
        common_name=cn,
        action="CREATE",
        detail=f"ID={cert_entry.id}, CN={cn}",
        ip_address=request.remote_addr,
        user_agent=request.user_agent.string)
    return redirect(url_for("user.cert"))


@bp.route("/certificate/download/<int:cert_id>")
@login_required
def download_certificate(cert_id):
    cert = Certificate.query.get_or_404(cert_id)
    # Admin can download all, User can only download their own
    if not current_user.is_admin and cert.common_name != current_user.cn:
        return "Unauthorized", 403

    p12_path = os.path.join("/opt/ez-mtls-manager/certs",
                            cert.common_name, str(cert.id), "client.p12")
    if not os.path.exists(p12_path):
        return g.trans.get("error_file_not_found"), 404

    # Safe filename
    safe_cn = cert.common_name.replace("@", "_").replace(".", "_")
    download_name = f"{safe_cn}.p12"

    AuditLog.log(
        idp=current_user.idp,
        user_name=current_user.display_name,
        email=current_user.email,
        common_name=cert.common_name,
        action="DOWNLOAD",
        detail=f"ID={cert.id}, CN={cert.common_name}",
        ip_address=request.remote_addr,
        user_agent=request.user_agent.string)

    return send_file(p12_path, as_attachment=True, download_name=download_name)


@bp.route("/certificate/revoke/<int:cert_id>", methods=["POST"])
@login_required
def revoke_certificate(cert_id):
    cert = Certificate.query.get_or_404(cert_id)
    # Admin can revoke all, User can only revoke their own
    if not current_user.is_admin and cert.common_name != current_user.cn:
        return "Unauthorized", 403

    try:
        current_app.step_client.revoke_certificate(cert.serial)
        cert.status = 'revoked'
        db.session.commit()
        flash(g.trans.get("flash_cert_revoked"))
        AuditLog.log(
            idp=current_user.idp,
            user_name=current_user.display_name,
            email=current_user.email,
            common_name=cert.common_name,
            action="REVOKE",
            detail=f"ID={cert.id}, CN={cert.common_name}",
            ip_address=request.remote_addr,
            user_agent=request.user_agent.string)
    except Exception as e:
        flash(f"{g.trans.get('flash_revoke_failed')}{e}")

    # If referrer contains 'admin', redirect to admin page, otherwise to
    # certificate dashboard
    if "admin" in request.referrer:
        return redirect(url_for("admin.admin_cert"))
    return redirect(url_for("user.cert"))
