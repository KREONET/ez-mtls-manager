# from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import logging

from flask_login import UserMixin
import settings
from extensions import db

# db = SQLAlchemy() # Moved to extensions.py


class Certificate(db.Model):
    __tablename__ = 'certificates'

    id = db.Column(db.Integer, primary_key=True)
    idp = db.Column(db.String(20), nullable=True)
    user_name = db.Column(db.String(100), nullable=True)
    email = db.Column(db.String(255), nullable=True)
    common_name = db.Column(db.String(255), nullable=False)
    serial = db.Column(db.String(128), nullable=False)
    fingerprint_sha1 = db.Column(db.String(64), nullable=True)
    fingerprint_sha256 = db.Column(db.String(96), nullable=True)
    issued_at = db.Column(db.DateTime, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    status = db.Column(
        db.Enum(
            'valid',
            'revoked',
            'expired',
            name='cert_status_enum'),
        default='valid')

    def __repr__(self):
        return f"<Certificate {self.common_name} ({self.status})>"


class AuditLog(db.Model):
    __tablename__ = 'audit_logs'

    id = db.Column(db.Integer, primary_key=True)
    logged_at = db.Column(db.DateTime, default=datetime.utcnow)
    idp = db.Column(db.String(20), nullable=True)
    user_name = db.Column(db.String(100), nullable=True)
    email = db.Column(db.String(255), nullable=True)
    common_name = db.Column(db.String(255), nullable=False)
    action = db.Column(db.String(50), nullable=False)
    detail = db.Column(db.String(255), nullable=True)
    ip_address = db.Column(db.String(45), nullable=True)
    user_agent = db.Column(db.Text, nullable=True)

    def __repr__(self):
        return f"<AuditLog {self.common_name} - {self.action}>"

    @classmethod
    def log(cls, idp, user_name, email, common_name,
            action, detail, ip_address, user_agent):
        try:
            record = cls(
                idp=idp,
                user_name=user_name,
                email=email,
                common_name=common_name,
                action=action,
                detail=detail,
                ip_address=ip_address,
                user_agent=user_agent
            )
            db.session.add(record)
            db.session.commit()
        except Exception as e:
            logging.error(f"Audit log failed: {e}")
            db.session.rollback()


class User(UserMixin):
    def __init__(self, username, email=None,
                 display_name=None, groups=None, idp=None, cn=None):
        # User ID Unification: use email as canonical ID if available
        self.id = email if email else username
        self.username = username
        self.email = email
        self.display_name = display_name
        self.groups = groups or []
        self.idp = idp
        # CN (Common Name) for Certificate
        self.cn = cn if cn else self.id

    @property
    def is_admin(self):
        return self.email in settings.ADMIN_EMAILS
