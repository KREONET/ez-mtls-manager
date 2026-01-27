from flask import Blueprint, render_template, redirect, url_for, request, g, flash
from flask_login import login_required, current_user
from models import AuditLog, Certificate

bp = Blueprint('admin', __name__, url_prefix='/admin')


@bp.route("/cert")
@login_required
def admin_cert():
    if not current_user.is_admin:
        flash(g.trans.get("flash_admin_only"))
        return redirect(url_for("main.index"))

    page = request.args.get('page', 1, type=int)
    q = request.args.get('q', '', type=str)

    query = Certificate.query

    # Search filter
    if q:
        search = f"%{q}%"
        query = query.filter(
            (Certificate.idp.ilike(search)) |
            (Certificate.user_name.ilike(search)) |
            (Certificate.common_name.ilike(search)) |
            (Certificate.email.ilike(search)) |
            (Certificate.serial.ilike(search))
        )

    # Sort and Pagination
    pagination = query.order_by(
        Certificate.issued_at.desc()).paginate(
        page=page, per_page=100, error_out=False)

    return render_template("admin_cert.html", pagination=pagination, q=q)


@bp.route("/logs")
@login_required
def admin_logs():
    if not current_user.is_admin:
        flash(g.trans.get("flash_admin_only"))
        return redirect(url_for("main.index"))

    page = request.args.get('page', 1, type=int)
    q = request.args.get('q', '', type=str)

    query = AuditLog.query

    # Search filter
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

    # Sort and Pagination
    pagination = query.order_by(
        AuditLog.logged_at.desc()).paginate(
        page=page, per_page=100, error_out=False)

    return render_template("admin_logs.html", pagination=pagination, q=q)
